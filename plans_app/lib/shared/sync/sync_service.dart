import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:plans_app/shared/database/database_service.dart';
import 'package:plans_app/shared/sync/google_drive_api.dart';
import 'package:plans_app/shared/sync/sync_key_manager.dart';
import 'package:plans_app/features/tasks/providers/task_provider.dart';
import 'package:plans_app/features/projects/providers/project_provider.dart';
import 'package:plans_app/src/rust/api/sync.dart' as rust_sync;

enum SyncStatus { disconnected, authenticating, syncing, idle, error }

final syncServiceProvider = NotifierProvider<SyncService, SyncStatus>(SyncService.new);

class SyncService extends Notifier<SyncStatus> {
  late final GoogleDriveApi _driveApi;
  late final DatabaseService _db;

  bool _isSyncing = false;
  bool _dirty = false;
  Timer? _debounceTimer;
  DateTime _lastUploadTime = DateTime(2020);
  String? _lastError;
  String? _lastSyncedFrom;

  static const _debounceMs = Duration(seconds: 2);
  static const _minInterval = Duration(seconds: 30);

  // ── Getters (for UI) ──
  String? get lastError => _lastError;
  String? get lastSyncedFrom => _lastSyncedFrom;
  bool get isAuthenticated => _driveApi.isAuthenticated;
  String? get googleUserId => _driveApi.googleUserId;

  @override
  SyncStatus build() {
    _db = ref.read(databaseServiceProvider);
    _driveApi = GoogleDriveApi();
    ref.onDispose(() => _debounceTimer?.cancel());
    _init();
    return SyncStatus.disconnected;
  }

  Future<void> _init() async {
    try {
      if (await _driveApi.trySilentAuth()) {
        state = SyncStatus.idle;
        checkForUpdates();
      }
    } catch (_) {
      // Silently handle - tests or non-Flutter environments without binding
    }
  }

  Future<void> authenticate() async {
    state = SyncStatus.authenticating;
    try {
      await _driveApi.authenticate();
      state = SyncStatus.idle;
      unawaited(_doSync());
    } catch (e, st) {
      state = SyncStatus.error;
      _lastError = e.toString();
      debugPrint('SyncService.authenticate failed: $e\n$st');
    }
  }

  static const _signOutWaitCap = Duration(seconds: 10);

  Future<void> signOut() async {
    // Wait out any in-flight sync — it holds a reference to the Drive
    // account and would null-check-crash if signed out from under it. Capped
    // so a stuck sync (network calls now time out, but several can still
    // chain sequentially) can't block sign-out indefinitely; the user asked
    // to sign out, so proceed anyway past the cap.
    final deadline = DateTime.now().add(_signOutWaitCap);
    while (_isSyncing && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_isSyncing) {
      debugPrint('SyncService.signOut: proceeding past $_signOutWaitCap wait cap, sync still in flight');
    }
    try {
      await _driveApi.signOut();
    } catch (_) {
      // Ignore platform errors — reset local state regardless
    }
    state = SyncStatus.disconnected;
    _dirty = false;
    _debounceTimer?.cancel();
  }

  void markDirty() {
    _dirty = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceMs, _doSync);
  }

  Future<void> checkForUpdates() => _doSync();

  Future<void> _doSync() async {
    if (!isAuthenticated || _isSyncing) return;
    _isSyncing = true;
    state = SyncStatus.syncing;
    try {
      await _downloadIfNewer();
      await _uploadIfNeeded();
      state = SyncStatus.idle;
    } catch (e, st) {
      state = SyncStatus.error;
      _lastError = e.toString();
      debugPrint('SyncService._doSync failed: $e\n$st');
    }
    _isSyncing = false;
  }

  Future<void> _uploadIfNeeded() async {
    if (!_dirty) return;
    final wait = _minInterval - DateTime.now().difference(_lastUploadTime);
    if (wait > Duration.zero) {
      // Throttled — still dirty, so arm a retry for when the window opens.
      _debounceTimer?.cancel();
      _debounceTimer = Timer(wait, _doSync);
      return;
    }

    final userId = _driveApi.googleUserId;
    if (userId == null) throw Exception('Not authenticated');
    final key = SyncKeyManager.deriveKey(userId);
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/plans.db';
    final deviceId = await rust_sync.getOrCreateDeviceId();
    final name = _driveApi.googleDisplayName ?? 'Unknown';

    final result = await rust_sync.createSnapshot(
      key: key.toList(),
      dbPath: dbPath,
      deviceId: deviceId,
      deviceName: name,
      schemaVersion: 1,
      appVersion: '1.0.0',
    );

    await _driveApi.uploadSnapshot(
      result.encrypted,
      jsonDecode(result.manifestJson) as Map<String, dynamic>,
    );

    _dirty = false;
    _lastUploadTime = DateTime.now();
  }

  Future<void> _downloadIfNewer() async {
    final manifest = await _driveApi.fetchManifestJson();
    if (manifest == null) return;

    final remoteVer = manifest['snapshot_version'] as int;
    final local = jsonDecode(await rust_sync.getSyncState());
    if (remoteVer <= (local['snapshot_version'] as int? ?? 0)) return;

    final encrypted = await _driveApi.downloadSnapshot();
    final userId = _driveApi.googleUserId;
    if (userId == null) throw Exception('Not authenticated');
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/plans.db';

    // Snapshot local state as late as possible (right before the file swap)
    // to shrink the window in which a concurrent edit could land on the
    // about-to-be-replaced DB file and be lost.
    final localTasks = await _db.getTasks();
    final localProjects = await _db.getProjects();
    final localDeletedIds = Set<String>.from(DatabaseService.pendingLocalDeletions);

    await rust_sync.installSnapshot(
      encrypted: encrypted,
      manifestJson: jsonEncode(manifest),
      key: SyncKeyManager.deriveKey(userId).toList(),
      dbPath: dbPath,
    );

    await _db.restart();

    try {
      // Merge local data back using last-write-wins by updated_at. A single
      // row's failure is logged and skipped rather than aborting the whole
      // merge, so one bad row can't leave the rest of the merge half-applied.
      for (final task in localTasks) {
        try {
          await _db.upsertTask(task);
        } catch (e, st) {
          debugPrint('SyncService: upsertTask failed for ${task.id}: $e\n$st');
        }
      }
      for (final project in localProjects) {
        try {
          await _db.upsertProject(project);
        } catch (e, st) {
          debugPrint('SyncService: upsertProject failed for ${project.id}: $e\n$st');
        }
      }

      // Re-apply local soft-deletes that the remote snapshot may have overwritten.
      for (final id in localDeletedIds) {
        try {
          await _db.deleteTask(id);
        } catch (e, st) {
          debugPrint('SyncService: re-delete failed for $id: $e\n$st');
        }
      }
    } finally {
      // Always clear deletions and invalidate providers so in-memory state
      // can't permanently diverge from the DB file that was just swapped in,
      // even if a row above threw.
      await DatabaseService.clearPendingDeletions(localDeletedIds);
      ref.invalidate(tasksProvider);
      ref.invalidate(projectsProvider);
    }

    _lastSyncedFrom = '${manifest['device_name'] ?? 'device'} (v$remoteVer)';
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleDriveApi {
  static const _appDataScope = 'https://www.googleapis.com/auth/drive.appdata';
  // Without a timeout a stalled request hangs the sync pipeline forever:
  // `_isSyncing` never clears, so every later sync attempt silently no-ops.
  static const _networkTimeout = Duration(seconds: 20);

  final GoogleSignIn _signIn;
  final FlutterSecureStorage _secureStorage;
  GoogleSignInAccount? _account;

  GoogleDriveApi({
    GoogleSignIn? signIn,
    FlutterSecureStorage? secureStorage,
  }) : _signIn = signIn ?? GoogleSignIn(scopes: [_appDataScope]),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  bool get isAuthenticated => _account != null;
  String? get googleUserId => _account?.id;
  String? get googleDisplayName => _account?.displayName;

  Future<void> authenticate() async {
    _account = await _signIn.signIn();
    if (_account == null) throw Exception('Google Sign-In cancelled');
    await _secureStorage.write(key: 'sync_authed', value: 'true');
  }

  Future<void> signOut() async {
    try {
      await _signIn.signOut();
    } catch (_) {}
    try {
      await _secureStorage.delete(key: 'sync_authed');
    } catch (_) {}
    _account = null;
  }

  Future<bool> trySilentAuth() async {
    try {
      final val = await _secureStorage.read(key: 'sync_authed');
      if (val != 'true') return false;
    } catch (_) {
      return false;
    }
    try {
      _account = await _signIn.signInSilently();
      return _account != null;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final auth = await _account!.authentication.timeout(_networkTimeout);
    final token = auth.accessToken;
    if (token == null) throw Exception('No access token available');
    return {'Authorization': 'Bearer $token'};
  }

  Future<String?> _getFileId(String fileName, Map<String, String> headers) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files').replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name='$fileName'",
      'fields': 'files(id)',
    });
    final resp = await http.get(uri, headers: headers).timeout(_networkTimeout);
    if (resp.statusCode != 200) return null;
    final files = jsonDecode(resp.body)['files'] as List?;
    return files?.isNotEmpty == true ? files![0]['id'] as String : null;
  }

  Future<String> _createFile(String fileName, Map<String, String> headers) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files');
    final body = jsonEncode({'name': fileName, 'parents': ['appDataFolder']});
    final resp = await http.post(uri, headers: {
      ...headers, 'Content-Type': 'application/json',
    }, body: body).timeout(_networkTimeout);
    if (resp.statusCode != 200) throw Exception('Create file failed: ${resp.statusCode}');
    return jsonDecode(resp.body)['id'] as String;
  }

  Future<String> _findOrCreateFile(String fileName, Map<String, String> headers) async {
    return await _getFileId(fileName, headers) ?? await _createFile(fileName, headers);
  }

  Future<Map<String, dynamic>?> fetchManifestJson() async {
    final headers = await _authHeaders();
    final fileId = await _getFileId('plans_manifest.json', headers);
    if (fileId == null) return null;
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId')
        .replace(queryParameters: {'alt': 'media'});
    final resp = await http.get(uri, headers: headers).timeout(_networkTimeout);
    if (resp.statusCode != 200) return null;
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // Each snapshot's blob gets its own immutable, version-named file instead
  // of overwriting a single shared 'plans_snapshot.enc'. Two separate Drive
  // files (blob + manifest) can never be updated as one atomic unit, so a
  // shared mutable blob name let one device's upload silently overwrite the
  // blob a concurrent download was about to fetch for an older manifest it
  // had already read -- checksum mismatch. A per-version filename makes that
  // race impossible: once v5's blob is written it is never touched again.
  String _snapshotFileName(int version) => 'plans_snapshot_v$version.enc';

  Future<void> uploadSnapshot(Uint8List encryptedBytes, Map<String, dynamic> manifest) async {
    final headers = await _authHeaders();
    final version = manifest['snapshot_version'] as int;

    // Encrypted snapshot first (write data before commit pointer)
    final snapshotFileId = await _findOrCreateFile(_snapshotFileName(version), headers);
    final snapshotUri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$snapshotFileId')
        .replace(queryParameters: {'uploadType': 'media'});
    final snapshotResp = await http.patch(snapshotUri, headers: {
      ...headers, 'Content-Type': 'application/octet-stream',
    }, body: encryptedBytes).timeout(_networkTimeout);
    if (snapshotResp.statusCode != 200) {
      throw Exception('Snapshot upload failed: ${snapshotResp.statusCode}');
    }

    // Manifest JSON last (atomic commit pointer)
    final manifestFileId = await _findOrCreateFile('plans_manifest.json', headers);
    final manifestUri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$manifestFileId')
        .replace(queryParameters: {'uploadType': 'media'});
    final manifestResp = await http.patch(manifestUri, headers: {
      ...headers, 'Content-Type': 'application/json; charset=UTF-8',
    }, body: jsonEncode(manifest)).timeout(_networkTimeout);
    if (manifestResp.statusCode != 200) {
      throw Exception('Manifest upload failed: ${manifestResp.statusCode}');
    }

    // Best-effort cleanup of older snapshot blobs so appDataFolder doesn't
    // grow unbounded. Never let this fail the sync itself.
    try {
      await _deleteOldSnapshots(keepVersion: version, headers: headers);
    } catch (e, st) {
      debugPrint('GoogleDriveApi.uploadSnapshot: cleanup failed: $e\n$st');
    }
  }

  Future<void> _deleteOldSnapshots({required int keepVersion, required Map<String, String> headers}) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files').replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name contains 'plans_snapshot_v' and trashed=false",
      'fields': 'files(id,name)',
    });
    final resp = await http.get(uri, headers: headers).timeout(_networkTimeout);
    if (resp.statusCode != 200) return;
    final files = (jsonDecode(resp.body)['files'] as List?) ?? [];
    final keepName = _snapshotFileName(keepVersion);
    for (final f in files) {
      final name = f['name'] as String?;
      final id = f['id'] as String?;
      if (name == null || id == null || name == keepName) continue;
      final delUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$id');
      await http.delete(delUri, headers: headers).timeout(_networkTimeout);
    }
  }

  Future<Uint8List> downloadSnapshot(int version) async {
    final headers = await _authHeaders();
    var fileId = await _getFileId(_snapshotFileName(version), headers);
    // Fallback for snapshots uploaded before version-named blobs existed.
    fileId ??= await _getFileId('plans_snapshot.enc', headers);
    if (fileId == null) throw Exception('No snapshot on Drive');
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId')
        .replace(queryParameters: {'alt': 'media'});
    final resp = await http.get(uri, headers: headers).timeout(_networkTimeout);
    if (resp.statusCode != 200) throw Exception('Download failed: ${resp.statusCode}');
    return resp.bodyBytes;
  }
}

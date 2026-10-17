import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'alarm_info.dart';

/// Persists [AlarmInfo] entries to a JSON file in the app's documents
/// directory, debounced, so a pending full-screen alarm's task id/title/
/// style survives an app restart (flutter_local_notifications and the
/// alarm package have no "what did I schedule" API of their own).
///
/// macOS/web never write the file — full-screen alarm restore only applies
/// on mobile, so there's nothing there to persist.
class AlarmInfoStore {
  final Map<int, AlarmInfo> alarmInfos = {};
  Timer? _saveDebounce;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/_alarm_infos.json');
  }

  Future<void> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      alarmInfos.clear();
      for (final entry in raw.entries) {
        final id = int.tryParse(entry.key);
        if (id != null) {
          alarmInfos[id] = AlarmInfo.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      debugPrint('AlarmInfoStore: loaded ${alarmInfos.length} alarm infos');
    } catch (e, st) {
      debugPrint('AlarmInfoStore.load failed: $e\n$st');
    }
  }

  void scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    if (kIsWeb || Platform.isMacOS) return;
    try {
      final file = await _file();
      final raw = <String, dynamic>{
        for (final e in alarmInfos.entries) '${e.key}': e.value.toJson(),
      };
      await file.writeAsString(jsonEncode(raw));
    } catch (e, st) {
      debugPrint('AlarmInfoStore._save failed: $e\n$st');
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Baked in at release-build time via `--dart-define=APP_VERSION=` (tag without
/// its leading "v"). Debug/dev builds fall back to 0.0.0, which is always
/// "outdated" relative to any real release — fine, since the check only runs
/// in release mode anyway.
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');

const _repo = 'Dheeraj-Murthy/Plans';
const _checkInterval = Duration(hours: 6);
const _prefsLastChecked = 'update_last_checked_at';
const _prefsDismissed = 'update_dismissed_version';

class UpdateInfo {
  final String version;
  final String url;
  const UpdateInfo(this.version, this.url);
}

class UpdateNotifier extends Notifier<UpdateInfo?> {
  @override
  UpdateInfo? build() {
    if (kReleaseMode) {
      _check();
    }
    return null;
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final lastChecked = prefs.getInt(_prefsLastChecked) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastChecked < _checkInterval.inMilliseconds) return;

    try {
      final response = await http
          .get(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'))
          .timeout(const Duration(seconds: 10));
      await prefs.setInt(_prefsLastChecked, now);
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = body['tag_name'] as String?;
      if (tag == null || tag.isEmpty) return;
      final remoteVersion = tag.startsWith('v') ? tag.substring(1) : tag;
      final url = body['html_url'] as String? ?? 'https://github.com/$_repo/releases/latest';

      if (!_isNewer(remoteVersion, kAppVersion)) return;
      if (prefs.getString(_prefsDismissed) == remoteVersion) return;

      state = UpdateInfo(remoteVersion, url);
    } catch (_) {
      // Offline or GitHub unreachable — silently skip, retry next launch/interval.
    }
  }

  Future<void> dismiss() async {
    final info = state;
    if (info == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDismissed, info.version);
    state = null;
  }

  bool _isNewer(String remote, String local) {
    List<int> parse(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final r = parse(remote);
    final l = parse(local);
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateInfo?>(UpdateNotifier.new);

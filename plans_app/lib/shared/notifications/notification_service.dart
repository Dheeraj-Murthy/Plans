import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../../features/tasks/models/task.dart';
import 'alarm_full_screen_screen.dart';
import 'reminder_style.dart';

class _AlarmInfo {
  final String taskId;
  final String title;
  final ReminderStyle style;
  _AlarmInfo(this.taskId, this.title, this.style);

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'title': title,
    'style': style.name,
  };

  static _AlarmInfo fromJson(Map<String, dynamic> json) => _AlarmInfo(
    json['taskId'] as String,
    json['title'] as String,
    ReminderStyle.values.firstWhere(
      (s) => s.name == json['style'],
      orElse: () => ReminderStyle.notification,
    ),
  );
}

class NotificationService {
  // flutter_local_notifications used for macOS scheduling + Android permission
  static final _fln = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static GlobalKey<NavigatorState>? navigatorKey;
  static final Map<int, _AlarmInfo> _alarmInfos = {};
  static int? _currentFullScreenAlarmId;
  static Timer? _saveDebounce;

  static Future<void> init() async {
    if (kIsWeb || _initialized) return;
    try {
      if (Platform.isMacOS) {
        await _initMacOS();
      } else {
        await _initMobile();
      }
    } catch (e, st) {
      debugPrint('NotificationService.init failed: $e\n$st');
    }
  }

  // ── macOS ────────────────────────────────────────────────────────────────

  static Future<void> _initMacOS() async {
    tz.initializeTimeZones();
    final localTz = (await FlutterTimezone.getLocalTimezone()).identifier;
    try {
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    debugPrint('NotificationService: macOS tz=$localTz');

    const settings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await _fln.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onResponse,
    );

    await _fln
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    final permStatus = await _fln
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.checkPermissions();
    _initialized = permStatus?.isEnabled == true;
    debugPrint('NotificationService: macOS initialized=$_initialized');
  }

  // ── iOS / Android ────────────────────────────────────────────────────────

  static Future<void> _initMobile() async {
    await Alarm.init();
    debugPrint('NotificationService: Alarm.init() done');

    // Initialize timezone data for Android notification scheduling.
    if (!Platform.isIOS) {
      try {
        tz.initializeTimeZones();
        final localTz = (await FlutterTimezone.getLocalTimezone()).identifier;
        try {
          tz.setLocalLocation(tz.getLocation(localTz));
        } catch (_) {
          tz.setLocalLocation(tz.UTC);
        }
      } catch (_) {}
    }

    // Initialize flutter_local_notifications on both platforms.
    // Permission requests happen later in requestMobilePermissions()
    // after the Activity is guaranteed attached (post-runApp).
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _fln.initialize(settings: settings);
    _initialized = true;

    // Pre-create a high-importance channel for Android notifications.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final androidPlugin = _fln.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            'plans_notifications',
            'Plans reminders',
            description: 'Task due reminders',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
      } catch (_) {}
    }

    // Restore persisted alarm metadata so full-screen alarms survive app restart.
    await _loadAlarmInfos();

    Alarm.ringing.listen((alarmSet) async {
      for (final alarm in alarmSet.alarms) {
        if (_currentFullScreenAlarmId == alarm.id) {
          debugPrint('NotificationService: already showing full-screen alarm id=${alarm.id} — skip');
          continue;
        }
        final info = _alarmInfos[alarm.id];
        if (info != null && info.style == ReminderStyle.fullScreenAlarm) {
          if (navigatorKey?.currentContext == null) {
            debugPrint('NotificationService: cannot show full-screen alarm — no navigator context');
            continue;
          }
          _currentFullScreenAlarmId = alarm.id;
          navigatorKey!.currentState!.push(
            MaterialPageRoute(
              builder: (_) => AlarmFullScreenScreen(
                alarmId: alarm.id,
                taskId: info.taskId,
                taskTitle: info.title,
              ),
            ),
          );
        } else {
          debugPrint('NotificationService: notification looping id=${alarm.id} "${alarm.notificationSettings.title}"');
        }
      }
    });
  }

  static void _onResponse(NotificationResponse response) {}

  // ── Alarm info persistence ────────────────────────────────────────────────

  static Future<File> _alarmInfosFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/_alarm_infos.json');
  }

  static Future<void> _loadAlarmInfos() async {
    try {
      final file = await _alarmInfosFile();
      if (!file.existsSync()) return;
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _alarmInfos.clear();
      for (final entry in raw.entries) {
        final id = int.tryParse(entry.key);
        if (id != null) {
          _alarmInfos[id] = _AlarmInfo.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      debugPrint('NotificationService: loaded ${_alarmInfos.length} alarm infos');
    } catch (e, st) {
      debugPrint('NotificationService._loadAlarmInfos failed: $e\n$st');
    }
  }

  static void _scheduleSaveAlarmInfos() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveAlarmInfos());
    });
  }

  static Future<void> _saveAlarmInfos() async {
    if (kIsWeb || Platform.isMacOS) return;
    try {
      final file = await _alarmInfosFile();
      final raw = <String, dynamic>{
        for (final e in _alarmInfos.entries) '${e.key}': e.value.toJson(),
      };
      await file.writeAsString(jsonEncode(raw));
    } catch (e, st) {
      debugPrint('NotificationService._saveAlarmInfos failed: $e\n$st');
    }
  }

  // ── ID helpers ───────────────────────────────────────────────────────────

  static int _dueId(String taskId) {
    final h = taskId.hashCode.abs() % 0x3FFFFFFF;
    return h == 0 ? 1 : h;
  }

  static int _reminderId(String taskId) {
    final h = (_dueId(taskId) + 0x40000000) % 0x7FFFFFFF;
    return h == 0 ? 1 : h;
  }

  /// Request notification permissions on mobile.
  ///
  /// Must be called AFTER [init] and after the Activity is attached
  /// (e.g. after `runApp()` or from a widget's `initState`).
  /// On Android 13+ this shows the system POST_NOTIFICATIONS dialog.
  /// On iOS this shows the system notification permission dialog.
  static Future<void> requestMobilePermissions() async {
    if (kIsWeb || Platform.isMacOS) return;
    try {
      if (Platform.isAndroid) {
        final androidPlugin = _fln
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidPlugin?.requestNotificationsPermission();
        debugPrint('NotificationService: Android POST_NOTIFICATIONS granted=$granted');
        final fsGranted = await androidPlugin?.requestFullScreenIntentPermission();
        debugPrint('NotificationService: Android USE_FULL_SCREEN_INTENT granted=$fsGranted');
        await androidPlugin?.requestExactAlarmsPermission();
      } else {
        final iosPlugin = _fln
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        final granted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('NotificationService: iOS permission granted=$granted');
      }
    } catch (e, st) {
      debugPrint('NotificationService.requestMobilePermissions failed: $e\n$st');
    }
  }

  // ── Permission status ────────────────────────────────────────────────────

  static Future<bool> get areNotificationsEnabled async {
    if (kIsWeb || Platform.isMacOS) return true;
    try {
      if (Platform.isAndroid) {
        final androidPlugin = _fln.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await androidPlugin?.areNotificationsEnabled() ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────

  static Future<void> scheduleForTask(
    Task task, {
    ReminderStyle? style,
    bool persist = true,
  }) async {
    if (!_initialized) {
      debugPrint('NotificationService: skip — not initialized');
      return;
    }
    if (task.dueDate == null || task.isCompleted) {
      await cancelForTask(task.id);
      return;
    }

    final now = DateTime.now();
    final dueTime = task.dueDate!;
    final secondsPast = now.difference(dueTime).inSeconds;
    debugPrint(
      'NotificationService: scheduleForTask "${task.title}" due=$dueTime secondsPast=$secondsPast',
    );

    if (secondsPast >= 60 && task.priority == TaskPriority.critical) {
      // Don't reset an already-pending alarm on every app launch.
      if (_alarmInfos.containsKey(_dueId(task.id))) return;
    }

    await cancelForTask(task.id);

    if (!dueTime.isAfter(now)) return;

    final fireAt = dueTime;

    final dueStyle = style ?? ReminderStyle.notification;
    final dueId = _dueId(task.id);
    _alarmInfos[dueId] = _AlarmInfo(task.id, task.title, dueStyle);
    await _scheduleNotification(
      id: dueId,
      title: task.title,
      body: 'Due now',
      at: fireAt,
      style: dueStyle,
    );

    if (dueStyle != ReminderStyle.fullScreenAlarm) {
      final rem = task.reminderMinutes;
      if (rem != null && rem > 0) {
        final reminderTime = dueTime.subtract(Duration(minutes: rem));
        if (reminderTime.isAfter(now)) {
          final remId = _reminderId(task.id);
          _alarmInfos[remId] = _AlarmInfo(task.id, task.title, ReminderStyle.notification);
          await _scheduleNotification(
            id: remId,
            title: task.title,
            body: 'Due in $rem ${rem == 1 ? "minute" : "minutes"}',
            at: reminderTime,
            style: ReminderStyle.notification,
          );
        }
      }
    }

    if (persist) _scheduleSaveAlarmInfos();
  }

  static Future<void> cancelForTask(String taskId) async {
    if (!_initialized) return;
    _currentFullScreenAlarmId = null;
    _alarmInfos.remove(_dueId(taskId));
    _alarmInfos.remove(_reminderId(taskId));
    if (Platform.isMacOS) {
      await _fln.cancel(id: _dueId(taskId));
      await _fln.cancel(id: _reminderId(taskId));
    } else {
      await Alarm.stop(_dueId(taskId));
      await Alarm.stop(_reminderId(taskId));
      await _fln.cancel(id: _dueId(taskId));
      await _fln.cancel(id: _reminderId(taskId));
    }
    _scheduleSaveAlarmInfos();
  }

  static Future<void> snooze({
    required int alarmId,
    required String taskId,
    required String taskTitle,
    required int minutes,
  }) async {
    if (!_initialized) return;
    _currentFullScreenAlarmId = null;
    final fireAt = DateTime.now().add(Duration(minutes: minutes));
    _alarmInfos[alarmId] = _AlarmInfo(taskId, taskTitle, ReminderStyle.fullScreenAlarm);
    await _scheduleNotification(
      id: alarmId,
      title: taskTitle,
      body: 'Snoozed',
      at: fireAt,
      style: ReminderStyle.fullScreenAlarm,
    );
    _scheduleSaveAlarmInfos();
  }

  static Future<void> rescheduleAll(List<Task> tasks) async {
    if (!_initialized) return;
    if (!Platform.isMacOS) {
      _currentFullScreenAlarmId = null;
      for (final id in _alarmInfos.keys) {
        await Alarm.stop(id);
        await _fln.cancel(id: id);
      }
      _alarmInfos.clear();
      await _fln.cancelAll();
    }
    final now = DateTime.now();
    for (final task in tasks) {
      if (!task.isCompleted && task.dueDate != null && task.dueDate!.isAfter(now)) {
        await scheduleForTask(task, style: _styleForPriority(task.priority), persist: false);
      }
    }
    _scheduleSaveAlarmInfos();
  }

  static ReminderStyle _styleForPriority(TaskPriority priority) {
    return priority == TaskPriority.critical
        ? ReminderStyle.fullScreenAlarm
        : ReminderStyle.notification;
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    ReminderStyle style = ReminderStyle.notification,
  }) async {
    if (Platform.isMacOS) {
      await _scheduleMacOS(id: id, title: title, body: body, at: at);
    } else if (style == ReminderStyle.fullScreenAlarm) {
      await _scheduleAlarm(
        id: id,
        title: title,
        body: body,
        at: at,
        style: style,
      );
    } else {
      await _scheduleAndroidNotification(
        id: id,
        title: title,
        body: body,
        at: at,
      );
    }
  }

  static Future<void> _scheduleMacOS({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    try {
      final tzAt = tz.TZDateTime.from(at, tz.local);
      await _fln.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzAt,
        notificationDetails: const NotificationDetails(
          macOS: DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      debugPrint('NotificationService: macOS scheduled id=$id "$title" at $tzAt');
    } catch (e, st) {
      debugPrint('NotificationService._scheduleMacOS failed: $e\n$st');
    }
  }

  static Future<void> _scheduleAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    ReminderStyle style = ReminderStyle.notification,
  }) async {
    try {
      await Alarm.set(
        alarmSettings: AlarmSettings(
          id: id,
          dateTime: at,
          assetAudioPath: null,
          loopAudio: true,
          vibrate: true,
          warningNotificationOnKill: Platform.isIOS,
          androidFullScreenIntent: style == ReminderStyle.fullScreenAlarm,
          androidStopAlarmOnTermination: false,
          volumeSettings: const VolumeSettings.fixed(volume: 1.0),
          notificationSettings: NotificationSettings(
            title: title,
            body: body,
            icon: 'ic_stat_notification',
          ),
        ),
      );
      debugPrint('NotificationService: alarm set id=$id "$title" at $at');
    } catch (e, st) {
      debugPrint('NotificationService._scheduleAlarm failed: $e\n$st');
    }
  }

  /// Schedules a notification via flutter_local_notifications on Android.
  ///
  /// This is a reliability layer — if the alarm plugin's foreground service
  /// notification is suppressed (e.g. Android 12+ restrictions), this ensures
  /// the user still gets a visible notification in the tray.
  static Future<void> _scheduleAndroidNotification({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    if (kIsWeb || Platform.isIOS || Platform.isMacOS) return;
    try {
      final tzAt = tz.TZDateTime.from(at, tz.local);
      await _fln.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzAt,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'plans_notifications',
            'Plans reminders',
            channelDescription: 'Task due reminders',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_notification',
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint('NotificationService: fln scheduled id=$id "$title" at $tzAt');
    } catch (e, st) {
      debugPrint('NotificationService._scheduleAndroidNotification failed: $e\n$st');
    }
  }
}

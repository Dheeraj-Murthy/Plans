import 'reminder_style.dart';

/// What NotificationService needs to remember about a pending alarm/
/// notification so it can be restored after an app restart (flutter_local_
/// notifications and the alarm package don't let you read back what you
/// scheduled — this is PlansApp's own record of it).
class AlarmInfo {
  final String taskId;
  final String title;
  final ReminderStyle style;

  AlarmInfo(this.taskId, this.title, this.style);

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'title': title,
        'style': style.name,
      };

  static AlarmInfo fromJson(Map<String, dynamic> json) => AlarmInfo(
        json['taskId'] as String,
        json['title'] as String,
        ReminderStyle.values.firstWhere(
          (s) => s.name == json['style'],
          orElse: () => ReminderStyle.notification,
        ),
      );
}

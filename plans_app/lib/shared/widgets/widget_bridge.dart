import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import '../../features/tasks/models/task.dart';
import '../../features/projects/models/project.dart';

class WidgetBridge {
  static const _widgetName = 'PlansAppWidgetProvider';

  static Future<void> notifyUpdate({
    List<Task>? allTasks,
    List<Project>? allProjects,
  }) async {
    try {
      if (allTasks != null) {
        await _saveTasks(allTasks);
      }
      if (allProjects != null) {
        await _saveProjects(allProjects);
      }
      await HomeWidget.updateWidget(
        androidName: _widgetName,
        qualifiedAndroidName: 'com.plansapp.widget.$_widgetName',
        iOSName: 'PlansWidget',
      );
    } catch (_) {}
  }

  static Map<String, dynamic> _taskToJson(Task t) {
    return {
      'id': t.id,
      'title': t.title,
      'due_date': t.dueDate?.millisecondsSinceEpoch,
      'priority': t.priority.index,
      'is_completed': t.isCompleted,
      'project_id': t.projectId,
    };
  }

  static Future<void> _saveTasks(List<Task> allTasks) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final inboxTasks = allTasks
        .where((t) =>
            !t.isCompleted &&
            (t.projectId == 'default' || t.dueDate != null))
        .toList();
    final todayTasks = allTasks
        .where((t) =>
            t.dueDate != null &&
            t.dueDate!.isAfter(todayStart) &&
            t.dueDate!.isBefore(todayEnd) &&
            !t.isCompleted)
        .toList();
    final completedTasks = allTasks.where((t) => t.isCompleted).take(50).toList();

    await HomeWidget.saveWidgetData<String>(
      'widget_tasks_inbox',
      jsonEncode(inboxTasks.map(_taskToJson).toList()),
    );
    await HomeWidget.saveWidgetData<String>(
      'widget_tasks_today',
      jsonEncode(todayTasks.map(_taskToJson).toList()),
    );
    await HomeWidget.saveWidgetData<String>(
      'widget_tasks_completed',
      jsonEncode(completedTasks.map(_taskToJson).toList()),
    );

    final projectIds = allTasks.map((t) => t.projectId).toSet();
    for (final projectId in projectIds) {
      final projectTasks =
          allTasks.where((t) => t.projectId == projectId && !t.isCompleted).toList();
      await HomeWidget.saveWidgetData<String>(
        'widget_tasks_project:$projectId',
        jsonEncode(projectTasks.map(_taskToJson).toList()),
      );
    }
  }

  static Future<void> _saveProjects(List<Project> allProjects) async {
    await HomeWidget.saveWidgetData<String>(
      'widget_projects',
      jsonEncode(allProjects
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'color_index': p.colorIndex,
              })
          .toList()),
    );
  }
}

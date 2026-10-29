import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plans_app/src/rust/api.dart' as rust_api;
import 'package:plans_app/src/rust/api/tasks.dart' as rust_tasks;
import 'package:plans_app/src/rust/api/projects.dart' as rust_projects;
import 'package:plans_app/src/rust/api/subtasks.dart' as rust_subtasks;
import 'package:plans_app/src/rust/models.dart' as rust_models;
import 'package:plans_app/features/tasks/models/task.dart';
import 'package:plans_app/features/projects/models/project.dart';
import 'package:plans_app/features/tasks/models/subtask.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  throw UnimplementedError('DatabaseService must be overridden in ProviderScope');
});

class DatabaseService {
  // Task IDs soft-deleted locally but not yet confirmed merged by a sync.
  // Persisted so a delete made just before app close/crash doesn't get
  // overwritten back to "active" by the next snapshot download.
  static final pendingLocalDeletions = <String>{};
  static const _pendingDeletionsKey = 'pending_local_deletions';

  static Future<void> loadPendingDeletions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_pendingDeletionsKey);
      if (saved != null) pendingLocalDeletions.addAll(saved);
    } catch (e, st) {
      debugPrint('DatabaseService.loadPendingDeletions failed: $e\n$st');
    }
  }

  static Future<void> _persistPendingDeletions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pendingDeletionsKey, pendingLocalDeletions.toList());
    } catch (e, st) {
      debugPrint('DatabaseService._persistPendingDeletions failed: $e\n$st');
    }
  }

  static Future<void> clearPendingDeletions(Iterable<String> ids) async {
    pendingLocalDeletions.removeAll(ids);
    await _persistPendingDeletions();
  }

  Future<List<Task>> getTasks() async {
    try {
      final raw = await rust_tasks.getAllTasks();
      final tasks = raw.map(_rustTaskToDomain).toList();
      final counts = await rust_subtasks.getSubtaskCounts();
      if (counts.isEmpty) return tasks;
      final byTaskId = {for (final c in counts) c.taskId: c};
      return tasks.map((t) {
        final c = byTaskId[t.id];
        if (c == null) return t;
        return t.copyWith(
          subtaskTotal: c.total.toInt(),
          subtaskCompleted: c.completed.toInt(),
        );
      }).toList();
    } catch (e, st) {
      debugPrint('DatabaseService.getTasks failed: $e\n$st');
      rethrow;
    }
  }

  Future<List<Subtask>> getSubtasks(String taskId) async {
    try {
      final raw = await rust_subtasks.getSubtasks(taskId: taskId);
      return raw.map(_rustSubtaskToDomain).toList();
    } catch (e, st) {
      debugPrint('DatabaseService.getSubtasks failed: $e\n$st');
      rethrow;
    }
  }

  Future<Subtask> insertSubtask(String taskId, String title) async {
    try {
      final raw = await rust_subtasks.createSubtask(taskId: taskId, title: title);
      return _rustSubtaskToDomain(raw);
    } catch (e, st) {
      debugPrint('DatabaseService.insertSubtask failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateSubtask(Subtask subtask) async {
    try {
      final json = jsonEncode({
        'id': subtask.id,
        'task_id': subtask.taskId,
        'title': subtask.title,
        'is_completed': subtask.isCompleted,
        'sort_order': subtask.sortOrder,
        'created_at': subtask.createdAt.millisecondsSinceEpoch,
        'updated_at': subtask.updatedAt.millisecondsSinceEpoch,
      });
      await rust_subtasks.updateSubtask(subtaskJson: json);
    } catch (e, st) {
      debugPrint('DatabaseService.updateSubtask failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteSubtask(String id) async {
    try {
      await rust_subtasks.deleteSubtask(id: id);
    } catch (e, st) {
      debugPrint('DatabaseService.deleteSubtask failed: $e\n$st');
      rethrow;
    }
  }

  Future<Task> insertTask({
    required String title,
    String? description,
    DateTime? dueDate,
    int priority = 0,
    String projectId = 'default',
    int? reminderMinutes,
    String? recurrence,
  }) async {
    try {
      final raw = await rust_tasks.createTask(
        title: title,
        description: description,
        dueDate: dueDate?.millisecondsSinceEpoch,
        priority: priority,
        projectId: projectId,
        reminderMinutes: reminderMinutes,
        recurrence: recurrence,
      );
      return _rustTaskToDomain(raw);
    } catch (e, st) {
      debugPrint('DatabaseService.insertTask failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateTask(Task task) async {
    try {
      final json = jsonEncode({
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'due_date': task.dueDate?.millisecondsSinceEpoch,
        'priority': task.priority.index,
        'is_completed': task.isCompleted,
        'is_deleted': task.isDeleted,
        'project_id': task.projectId,
        'created_at': task.createdAt.millisecondsSinceEpoch,
        'updated_at': task.updatedAt.millisecondsSinceEpoch,
        'sort_order': task.sortOrder,
        'reminder_minutes': task.reminderMinutes,
        'recurrence': task.recurrence,
      });
      await rust_tasks.updateTask(taskJson: json);
    } catch (e, st) {
      debugPrint('DatabaseService.updateTask failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> reorderTasks(List<String> orderedIds) async {
    try {
      await rust_tasks.reorderTasks(taskIds: orderedIds);
    } catch (e, st) {
      debugPrint('DatabaseService.reorderTasks failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteTask(String id) async {
    try {
      await rust_tasks.deleteTask(id: id);
      pendingLocalDeletions.add(id);
      await _persistPendingDeletions();
    } catch (e, st) {
      debugPrint('DatabaseService.deleteTask failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> restoreTask(String id) async {
    try {
      await rust_tasks.restoreTask(id: id);
      pendingLocalDeletions.remove(id);
      await _persistPendingDeletions();
    } catch (e, st) {
      debugPrint('DatabaseService.restoreTask failed: $e\n$st');
      rethrow;
    }
  }

  // Two devices can each independently advance the same missed recurring
  // task to its next occurrence (see TasksNotifier.advanceMissedRecurringTasks)
  // before either has seen the other's change — each inserts a new row with
  // its own random id, so the sync merge's last-write-wins-by-id upsert
  // can't tell they're the same logical "next occurrence" and both survive.
  // Detects groups of incomplete, non-deleted tasks sharing
  // (project, recurrence rule, title) — which only happens via that race,
  // never from a user deliberately creating two distinct recurring tasks
  // with identical text in the same project — and keeps the earliest-due
  // one, soft-deleting the rest. Returns [tasks] with any deleted
  // duplicates removed, so callers can use the result as fresh state.
  Future<List<Task>> dedupeRecurrenceRollovers(List<Task> tasks) async {
    final groups = <String, List<Task>>{};
    for (final t in tasks) {
      if (t.isCompleted || t.recurrence == null) continue;
      final key = '${t.projectId}|${t.recurrence}|${t.title}';
      groups.putIfAbsent(key, () => []).add(t);
    }

    final toRemove = <String>{};
    for (final group in groups.values) {
      if (group.length < 2) continue;
      group.sort((a, b) {
        final ad = a.dueDate;
        final bd = b.dueDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
      for (final dup in group.skip(1)) {
        try {
          await deleteTask(dup.id);
          toRemove.add(dup.id);
        } catch (e, st) {
          debugPrint(
            'DatabaseService.dedupeRecurrenceRollovers: delete failed for ${dup.id}: $e\n$st',
          );
        }
      }
    }

    if (toRemove.isEmpty) return tasks;
    return tasks.where((t) => !toRemove.contains(t.id)).toList();
  }

  Future<void> clearCompleted() async {
    try {
      await rust_tasks.clearCompleted();
    } catch (e, st) {
      debugPrint('DatabaseService.clearCompleted failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> upsertTask(Task task) async {
    try {
      final json = jsonEncode({
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'due_date': task.dueDate?.millisecondsSinceEpoch,
        'priority': task.priority.index,
        'is_completed': task.isCompleted,
        'is_deleted': task.isDeleted,
        'project_id': task.projectId,
        'created_at': task.createdAt.millisecondsSinceEpoch,
        'updated_at': task.updatedAt.millisecondsSinceEpoch,
        'sort_order': task.sortOrder,
        'reminder_minutes': task.reminderMinutes,
        'recurrence': task.recurrence,
      });
      await rust_tasks.upsertTask(taskJson: json);
    } catch (e, st) {
      debugPrint('DatabaseService.upsertTask failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> upsertProject(Project project) async {
    try {
      final json = jsonEncode({
        'id': project.id,
        'name': project.name,
        'color_index': project.colorIndex,
        'updated_at': project.updatedAt.millisecondsSinceEpoch,
      });
      await rust_projects.upsertProject(projectJson: json);
    } catch (e, st) {
      debugPrint('DatabaseService.upsertProject failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> restart() async {
    final dir = await getApplicationDocumentsDirectory();
    await rust_api.initDatabase(path: '${dir.path}/plans.db');
  }

  Future<List<Project>> getProjects() async {
    try {
      final raw = await rust_projects.getAllProjects();
      return raw.map(_rustProjectToDomain).toList();
    } catch (e, st) {
      debugPrint('DatabaseService.getProjects failed: $e\n$st');
      rethrow;
    }
  }

  Future<Project> insertProject({
    required String name,
    required int colorIndex,
  }) async {
    try {
      final raw = await rust_projects.createProject(
        name: name,
        colorIndex: colorIndex,
      );
      return _rustProjectToDomain(raw);
    } catch (e, st) {
      debugPrint('DatabaseService.insertProject failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateProject(Project project) async {
    try {
      await rust_projects.updateProject(
        id: project.id,
        name: project.name,
        colorIndex: project.colorIndex,
      );
    } catch (e, st) {
      debugPrint('DatabaseService.updateProject failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteProject(String id) async {
    try {
      await rust_projects.deleteProject(id: id);
    } catch (e, st) {
      debugPrint('DatabaseService.deleteProject failed: $e\n$st');
      rethrow;
    }
  }

  Task _rustTaskToDomain(rust_models.Task t) {
    return Task(
      id: t.id,
      title: t.title,
      description: t.description,
      dueDate: t.dueDate != null
          ? DateTime.fromMillisecondsSinceEpoch(t.dueDate!)
          : null,
      priority: TaskPriority.values[t.priority.toInt()],
      isCompleted: t.isCompleted,
      isDeleted: t.isDeleted,
      projectId: t.projectId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(t.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t.updatedAt),
      sortOrder: t.sortOrder.toInt(),
      reminderMinutes: t.reminderMinutes?.toInt(),
      recurrence: t.recurrence,
    );
  }

  Subtask _rustSubtaskToDomain(rust_models.Subtask s) {
    return Subtask(
      id: s.id,
      taskId: s.taskId,
      title: s.title,
      isCompleted: s.isCompleted,
      sortOrder: s.sortOrder.toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(s.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(s.updatedAt),
    );
  }

  Project _rustProjectToDomain(rust_models.Project p) {
    return Project(
      id: p.id,
      name: p.name,
      colorIndex: p.colorIndex.toInt(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(p.updatedAt.toInt()),
    );
  }
}

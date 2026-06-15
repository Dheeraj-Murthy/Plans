import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:plans_app/src/rust/api.dart' as rust_api;
import 'package:plans_app/src/rust/api/tasks.dart' as rust_tasks;
import 'package:plans_app/src/rust/api/projects.dart' as rust_projects;
import 'package:plans_app/src/rust/models.dart' as rust_models;
import 'package:plans_app/features/tasks/models/task.dart';
import 'package:plans_app/features/projects/models/project.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  throw UnimplementedError('DatabaseService must be overridden in ProviderScope');
});

class DatabaseService {
  // Task IDs soft-deleted this session; cleared after a successful sync merge.
  static final pendingLocalDeletions = <String>{};

  Future<List<Task>> getTasks() async {
    try {
      final raw = await rust_tasks.getAllTasks();
      return raw.map(_rustTaskToDomain).toList();
    } catch (e, st) {
      debugPrint('DatabaseService.getTasks failed: $e\n$st');
      return [];
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
    } catch (e, st) {
      debugPrint('DatabaseService.deleteTask failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> restoreTask(String id) async {
    try {
      await rust_tasks.restoreTask(id: id);
      pendingLocalDeletions.remove(id);
    } catch (e, st) {
      debugPrint('DatabaseService.restoreTask failed: $e\n$st');
      rethrow;
    }
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
      return [];
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

  Project _rustProjectToDomain(rust_models.Project p) {
    return Project(
      id: p.id,
      name: p.name,
      colorIndex: p.colorIndex.toInt(),
    );
  }
}

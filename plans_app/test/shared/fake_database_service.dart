import 'package:plans_app/features/projects/models/project.dart';
import 'package:plans_app/features/tasks/models/task.dart';
import 'package:plans_app/shared/database/database_service.dart';
import 'package:uuid/uuid.dart';

class FakeDatabaseService extends DatabaseService {
  final List<Task> _tasks = [];
  final List<Project> _projects = [];

  void seedProject(Project p) => _projects.add(p);

  @override
  Future<List<Task>> getTasks() async => List.from(_tasks);

  @override
  Future<List<Project>> getProjects() async => List.from(_projects);

  @override
  Future<Task> insertTask({
    required String title,
    String? description,
    DateTime? dueDate,
    int priority = 0,
    String projectId = 'default',
    int? reminderMinutes,
    String? recurrence,
  }) async {
    final task = Task(
      id: const Uuid().v4(),
      title: title,
      description: description,
      dueDate: dueDate,
      priority: TaskPriority.values[priority],
      projectId: projectId,
      reminderMinutes: reminderMinutes,
      recurrence: recurrence,
    );
    _tasks.add(task);
    return task;
  }

  @override
  Future<void> updateTask(Task task) async {
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) _tasks[idx] = task;
  }

  final List<Task> _deleted = [];

  @override
  Future<void> deleteTask(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      _deleted.add(_tasks[idx]);
      _tasks.removeAt(idx);
    }
  }

  @override
  Future<void> restoreTask(String id) async {
    final task = _deleted.where((t) => t.id == id).firstOrNull;
    if (task != null) {
      _deleted.removeWhere((t) => t.id == id);
      _tasks.add(task);
    }
  }

  @override
  Future<void> clearCompleted() async {
    _tasks.removeWhere((t) => t.isCompleted);
  }

  @override
  Future<Project> insertProject({
    required String name,
    required int colorIndex,
  }) async {
    final project = Project(
      id: const Uuid().v4(),
      name: name,
      colorIndex: colorIndex,
    );
    _projects.add(project);
    return project;
  }

  @override
  Future<void> updateProject(Project project) async {
    final idx = _projects.indexWhere((p) => p.id == project.id);
    if (idx >= 0) _projects[idx] = project;
  }

  @override
  Future<void> reorderTasks(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      final idx = _tasks.indexWhere((t) => t.id == orderedIds[i]);
      if (idx >= 0) _tasks[idx] = _tasks[idx].copyWith(sortOrder: i);
    }
  }

  @override
  Future<void> restart() async {}

  @override
  Future<void> deleteProject(String id) async {
    _projects.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> upsertTask(Task task) async {
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      if (task.updatedAt.isAfter(_tasks[idx].updatedAt)) {
        _tasks[idx] = task;
      }
    } else {
      _tasks.add(task);
    }
  }

  @override
  Future<void> upsertProject(Project project) async {
    final idx = _projects.indexWhere((p) => p.id == project.id);
    if (idx >= 0) {
      _projects[idx] = project;
    } else {
      _projects.add(project);
    }
  }
}

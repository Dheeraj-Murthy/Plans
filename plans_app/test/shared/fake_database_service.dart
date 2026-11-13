import 'package:plans_app/features/projects/models/project.dart';
import 'package:plans_app/features/tasks/models/task.dart';
import 'package:plans_app/features/tasks/models/subtask.dart';
import 'package:plans_app/features/budget/models/expense_category.dart';
import 'package:plans_app/features/budget/models/budget_transaction.dart';
import 'package:plans_app/features/budget/models/budget_settings.dart';
import 'package:plans_app/shared/database/database_service.dart';
import 'package:uuid/uuid.dart';

class FakeDatabaseService extends DatabaseService {
  final List<Task> _tasks = [];
  final List<Project> _projects = [];
  final List<Subtask> _subtasks = [];
  final List<ExpenseCategory> _categories = [];
  final List<BudgetTransaction> _transactions = [];
  BudgetSettings _settings = BudgetSettings();

  void seedProject(Project p) => _projects.add(p);
  void seedExpenseCategory(ExpenseCategory c) => _categories.add(c);

  @override
  Future<List<Task>> getTasks() async => List.from(_tasks);

  @override
  Future<List<Subtask>> getSubtasks(String taskId) async =>
      _subtasks.where((s) => s.taskId == taskId).toList();

  @override
  Future<Subtask> insertSubtask(String taskId, String title) async {
    final subtask = Subtask(
      id: const Uuid().v4(),
      taskId: taskId,
      title: title,
      sortOrder: _subtasks.where((s) => s.taskId == taskId).length,
    );
    _subtasks.add(subtask);
    return subtask;
  }

  @override
  Future<void> updateSubtask(Subtask subtask) async {
    final idx = _subtasks.indexWhere((s) => s.id == subtask.id);
    if (idx >= 0) _subtasks[idx] = subtask;
  }

  @override
  Future<void> deleteSubtask(String id) async {
    _subtasks.removeWhere((s) => s.id == id);
  }

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
    String? id,
  }) async {
    // Mirrors the real create_task's ON CONFLICT(id) DO NOTHING: a
    // caller-supplied id that already exists returns the existing row
    // instead of adding a duplicate, so provider tests can exercise the
    // same two-devices-race-to-the-same-id collapse the real DB does.
    if (id != null) {
      final existing = _tasks.where((t) => t.id == id).firstOrNull;
      if (existing != null) return existing;
    }
    final task = Task(
      id: id ?? const Uuid().v4(),
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

  // ── Budget: expense categories ──────────────────────────────────────

  @override
  Future<List<ExpenseCategory>> getExpenseCategories() async => List.from(_categories);

  @override
  Future<ExpenseCategory> insertExpenseCategory({
    required String name,
    required int colorIndex,
  }) async {
    final category = ExpenseCategory(id: const Uuid().v4(), name: name, colorIndex: colorIndex);
    _categories.add(category);
    return category;
  }

  @override
  Future<void> updateExpenseCategory(ExpenseCategory category) async {
    final idx = _categories.indexWhere((c) => c.id == category.id);
    if (idx >= 0) _categories[idx] = category;
  }

  @override
  Future<void> deleteExpenseCategory(String id) async {
    _categories.removeWhere((c) => c.id == id);
  }

  @override
  Future<void> upsertExpenseCategory(ExpenseCategory category) async {
    final idx = _categories.indexWhere((c) => c.id == category.id);
    if (idx >= 0) {
      _categories[idx] = category;
    } else {
      _categories.add(category);
    }
  }

  // ── Budget: transactions ─────────────────────────────────────────────

  @override
  Future<List<BudgetTransaction>> getBudgetTransactions() async => List.from(_transactions);

  @override
  Future<BudgetTransaction> insertBudgetTransaction({
    required TransactionType type,
    required double amount,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
  }) async {
    final transaction = BudgetTransaction(
      id: const Uuid().v4(),
      type: type,
      amount: amount,
      categoryId: type == TransactionType.expense ? (categoryId ?? 'other') : null,
      note: note,
      occurredAt: occurredAt,
    );
    _transactions.insert(0, transaction);
    return transaction;
  }

  @override
  Future<void> updateBudgetTransaction(BudgetTransaction transaction) async {
    final idx = _transactions.indexWhere((t) => t.id == transaction.id);
    if (idx >= 0) _transactions[idx] = transaction;
  }

  @override
  Future<void> deleteBudgetTransaction(String id) async {
    _transactions.removeWhere((t) => t.id == id);
  }

  @override
  Future<void> upsertBudgetTransaction(BudgetTransaction transaction) async {
    final idx = _transactions.indexWhere((t) => t.id == transaction.id);
    if (idx >= 0) {
      _transactions[idx] = transaction;
    } else {
      _transactions.add(transaction);
    }
  }

  // ── Budget: settings ──────────────────────────────────────────────────

  @override
  Future<BudgetSettings> getBudgetSettings() async => _settings;

  @override
  Future<BudgetSettings> updateBudgetSettings({required String currencySymbol}) async {
    _settings = _settings.copyWith(currencySymbol: currencySymbol, updatedAt: DateTime.now());
    return _settings;
  }

  @override
  Future<DateTime> resetBudget() async {
    final now = DateTime.now();
    _settings = _settings.copyWith(resetAt: now, updatedAt: now);
    return now;
  }
}

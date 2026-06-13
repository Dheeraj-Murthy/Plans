import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../../projects/providers/project_provider.dart';
import '../../../shared/database/database_service.dart';
import '../../../shared/helpers/recurrence.dart';
import '../../../shared/notifications/notification_service.dart';
import '../../../shared/notifications/reminder_style.dart';
import '../../../shared/sync/sync_service.dart';
import '../../../shared/widgets/widget_bridge.dart';

sealed class UndoAction {}

class TaskDeleted extends UndoAction {
  final Task task;
  TaskDeleted(this.task);
}

class TaskToggled extends UndoAction {
  final String id;
  final bool wasCompleted;
  TaskToggled(this.id, this.wasCompleted);
}

final undoStackProvider =
    NotifierProvider<UndoStackNotifier, List<UndoAction>>(
  UndoStackNotifier.new,
);

class _LastUndoActionNotifier extends Notifier<UndoAction?> {
  @override
  UndoAction? build() => null;
  void set(UndoAction? action) => state = action;
}

final lastUndoActionProvider =
    NotifierProvider<_LastUndoActionNotifier, UndoAction?>(
  _LastUndoActionNotifier.new,
);

class UndoStackNotifier extends Notifier<List<UndoAction>> {
  @override
  List<UndoAction> build() => [];

  void push(UndoAction action) => state = [...state, action];

  UndoAction? pop() {
    if (state.isEmpty) return null;
    final action = state.last;
    state = state.sublist(0, state.length - 1);
    return action;
  }
}

final tasksProvider =
    NotifierProvider<TasksNotifier, List<Task>>(TasksNotifier.new);

class _StringNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final searchQueryProvider =
    NotifierProvider<_StringNotifier, String>(_StringNotifier.new);

class _CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void request() => state++;
}

final composerFocusRequestProvider =
    NotifierProvider<_CounterNotifier, int>(_CounterNotifier.new);
final searchFocusRequestProvider =
    NotifierProvider<_CounterNotifier, int>(_CounterNotifier.new);

final todayCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(tasksProvider);
  final now = DateTime.now();
  return tasks.where((t) {
    if (t.isCompleted) return false;
    final due = t.dueDate;
    if (due == null) return false;
    return due.year == now.year &&
        due.month == now.month &&
        due.day == now.day;
  }).length;
});

final timelineCountProvider = Provider<int>((ref) {
  return ref.watch(tasksProvider).where((t) {
    if (t.isCompleted) return false;
    return t.dueDate != null;
  }).length;
});

final completedCountProvider = Provider<int>((ref) {
  return ref.watch(tasksProvider).where((t) => t.isCompleted).length;
});

final projectTaskCountsProvider = Provider<Map<String, int>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final counts = <String, int>{};
  for (final t in tasks) {
    if (!t.isCompleted) {
      counts[t.projectId] = (counts[t.projectId] ?? 0) + 1;
    }
  }
  return counts;
});

final projectTaskCountProvider = Provider.family<int, String>((ref, projectId) {
  return ref.watch(projectTaskCountsProvider)[projectId] ?? 0;
});

final filteredTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final SidebarSelection selection = ref.watch(sidebarSelectionProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase().trim();

  var filtered = switch (selection) {
    ViewSelection(:final view) => switch (view) {
        ViewType.inbox => tasks.where((t) => !t.isCompleted).toList(),
        ViewType.timeline => tasks.where((t) {
            if (t.isCompleted) return false;
            return t.dueDate != null;
          }).toList()..sort((a, b) => a.dueDate!.compareTo(b.dueDate!)),
        ViewType.today => tasks.where((t) {
            if (t.isCompleted) return false;
            final due = t.dueDate;
            if (due == null) return false;
            final now = DateTime.now();
            return due.year == now.year &&
                due.month == now.month &&
                due.day == now.day;
          }).toList(),
        ViewType.completed => tasks.where((t) => t.isCompleted).toList(),
      },
    ProjectSelection(:final projectId) =>
      tasks.where((t) => t.projectId == projectId).toList(),
  };

  if (query.isNotEmpty) {
    filtered = filtered.where((t) {
      return t.title.toLowerCase().contains(query) ||
          (t.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  return filtered;
});

class TasksNotifier extends Notifier<List<Task>> {
  late DatabaseService _db;
  Timer? _widgetUpdateTimer;

  @override
  List<Task> build() {
    _db = ref.read(databaseServiceProvider);
    ref.onDispose(() => _widgetUpdateTimer?.cancel());
    _load();
    ref.listen(projectsProvider, (prev, next) {
      if (prev == null || prev.length <= next.length) return;
      final activeIds = next.map((p) => p.id).toSet();
      state = state.map((t) => activeIds.contains(t.projectId)
          ? t
          : t.copyWith(projectId: 'default')).toList();
    });
    return [];
  }

  void _debouncedWidgetUpdate() {
    _widgetUpdateTimer?.cancel();
    _widgetUpdateTimer = Timer(const Duration(seconds: 2), () {
      WidgetBridge.notifyUpdate(allTasks: state);
    });
  }

  void _load() {
    unawaited(
      _db.getTasks().then((tasks) {
        state = tasks;
        NotificationService.rescheduleAll(tasks);
        WidgetBridge.notifyUpdate(allTasks: state, allProjects: ref.read(projectsProvider));
      }).catchError((e, st) {
        debugPrint('TasksNotifier._load failed: $e\n$st');
      }),
    );
  }

  Future<Task> addTask({
    required String title,
    String? description,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.none,
    String projectId = 'default',
    int? reminderMinutes,
    String? recurrence,
  }) async {
    final task = await _db.insertTask(
      title: title,
      description: description,
      dueDate: dueDate,
      priority: priority.index,
      projectId: projectId,
      reminderMinutes: reminderMinutes,
      recurrence: recurrence,
    );
    state = [...state, task];
    ref.read(syncServiceProvider.notifier).markDirty();
    NotificationService.scheduleForTask(
      task,
      style: task.priority == TaskPriority.high
          ? ReminderStyle.fullScreenAlarm
          : ReminderStyle.notification,
    );
    _debouncedWidgetUpdate();
    return task;
  }

  bool toggleTask(String id) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return false;

    final task = state[index];
    final wasCompleted = task.isCompleted;
    final toggled = task.copyWith(isCompleted: !wasCompleted);

    final newState = List<Task>.of(state);
    newState[index] = toggled;
    state = newState;

    unawaited(_db.updateTask(toggled));
    ref.read(syncServiceProvider.notifier).markDirty();
    if (toggled.isCompleted) {
      unawaited(NotificationService.cancelForTask(id));
    } else {
      unawaited(NotificationService.scheduleForTask(
        toggled,
        style: toggled.priority == TaskPriority.critical
            ? ReminderStyle.fullScreenAlarm
            : ReminderStyle.notification,
      ));
    }

    if (!wasCompleted) {
      if (task.recurrence != null && task.dueDate != null) {
        final rule = Recurrence.fromStorage(task.recurrence!);
        final nextDue = rule.nextOccurrence(task.dueDate!);
        if (nextDue != null) {
          unawaited(_db.insertTask(
            title: task.title,
            description: task.description,
            dueDate: nextDue,
            priority: task.priority.index,
            projectId: task.projectId,
            reminderMinutes: task.reminderMinutes,
            recurrence: task.recurrence,
          ).then((nextTask) {
            state = [...state, nextTask];
            ref.read(syncServiceProvider.notifier).markDirty();
            NotificationService.scheduleForTask(
              nextTask,
              style: nextTask.priority == TaskPriority.high
                  ? ReminderStyle.fullScreenAlarm
                  : ReminderStyle.notification,
            );
          }));
        }
      }
    }
    _debouncedWidgetUpdate();
    return wasCompleted;
  }

  Task? deleteTask(String id) {
    final task = state.where((t) => t.id == id).firstOrNull;
    state = state.where((t) => t.id != id).toList();
    unawaited(_db.deleteTask(id));
    ref.read(syncServiceProvider.notifier).markDirty();
    NotificationService.cancelForTask(id);
    _debouncedWidgetUpdate();
    return task;
  }

  Future<void> restoreTask(Task task) async {
    await _db.restoreTask(task.id);
    ref.read(syncServiceProvider.notifier).markDirty();
    state = [...state, task];
    NotificationService.scheduleForTask(
      task,
      style: task.priority == TaskPriority.high
          ? ReminderStyle.fullScreenAlarm
          : ReminderStyle.notification,
    );
    _debouncedWidgetUpdate();
  }

  void clearCompleted() {
    final completed = state.where((t) => t.isCompleted).toList();
    if (completed.isEmpty) return;
    for (final t in completed) {
      unawaited(_db.deleteTask(t.id));
      NotificationService.cancelForTask(t.id);
    }
    state = state.where((t) => !t.isCompleted).toList();
    ref.read(syncServiceProvider.notifier).markDirty();
    _debouncedWidgetUpdate();
  }

  void updateTask(String id, Task updated) {
    final idx = state.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final newState = List<Task>.of(state);
    newState[idx] = updated;
    state = newState;
    unawaited(_db.updateTask(updated));
    ref.read(syncServiceProvider.notifier).markDirty();
    unawaited(NotificationService.scheduleForTask(
      updated,
      style: updated.priority == TaskPriority.high
          ? ReminderStyle.fullScreenAlarm
          : ReminderStyle.notification,
    ));
    _debouncedWidgetUpdate();
  }

  void reorderTask(int oldIndex, int newIndex) {
    final tasks = List<Task>.from(state);
    final moved = tasks.removeAt(oldIndex);
    tasks.insert(newIndex, moved);
    state = tasks;
    unawaited(_db.reorderTasks(tasks.map((t) => t.id).toList()));
    ref.read(syncServiceProvider.notifier).markDirty();
    _debouncedWidgetUpdate();
  }
}

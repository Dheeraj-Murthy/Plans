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
  TaskToggled(this.id);
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

  static const _maxSize = 50;

  void push(UndoAction action) {
    final capped = [...state, action];
    if (capped.length > _maxSize) {
      state = capped.sublist(capped.length - _maxSize);
    } else {
      state = capped;
    }
  }

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

final inboxCountProvider = Provider<int>((ref) {
  return ref.watch(tasksProvider).where((t) {
    if (t.isCompleted) return false;
    return t.projectId == 'default' || t.dueDate != null;
  }).length;
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
        ViewType.inbox => tasks.where((t) {
            if (t.isCompleted) return false;
            return t.projectId == 'default' || t.dueDate != null;
          }).toList(),
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
  bool _advancingMissedRecurrence = false;
  final Completer<void> _firstLoadCompleter = Completer<void>();

  // Callers that need `state` to actually reflect the DB (e.g. applying a
  // widget toggle by id) must await this first — `build()` returns `[]`
  // synchronously and `_load()` populates state asynchronously after, so
  // reading `state` right after provider creation can race ahead of it.
  Future<void> get firstLoad => _firstLoadCompleter.future;

  @override
  List<Task> build() {
    _db = ref.read(databaseServiceProvider);
    ref.onDispose(() => _widgetUpdateTimer?.cancel());
    _load();
    return [];
  }

  // Called by ProjectsNotifier.deleteProject right after the DB delete
  // succeeds, so in-memory task state mirrors the DB-level reassignment
  // (rust `delete_project` already does `project_id='default'` for this
  // project's tasks). Previously this was inferred reactively via
  // `ref.listen(projectsProvider, ...)` watching for the list shrinking —
  // but `ProjectsNotifier.build()` also transiently resets to `[]` on every
  // rebuild (including the one `SyncService` triggers via
  // `ref.invalidate(projectsProvider)` after every sync), which that listener
  // couldn't tell apart from a real deletion, so a sync could reassign every
  // task to 'default' in memory. Calling this explicitly, only at the actual
  // deletion site, removes that race entirely.
  void reassignTasksFromDeletedProject(String projectId) {
    state = state
        .map((t) => t.projectId == projectId
            ? t.copyWith(projectId: 'default')
            : t)
        .toList();
  }

  void _debouncedWidgetUpdate() {
    _widgetUpdateTimer?.cancel();
    _widgetUpdateTimer = Timer(const Duration(seconds: 2), () {
      WidgetBridge.notifyUpdate(allTasks: state);
    });
  }

  // Called by SubtasksNotifier after any add/toggle/remove so the task
  // list's "n/m" progress chip stays in sync without a full reload.
  void patchSubtaskCounts(String taskId, int total, int completed) {
    final idx = state.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final newState = List<Task>.of(state);
    newState[idx] = newState[idx].copyWith(
      subtaskTotal: total,
      subtaskCompleted: completed,
    );
    state = newState;
  }

  void _load() {
    unawaited(
      _db.getTasks().then((tasks) async {
        final deduped = await _db.dedupeRecurrenceRollovers(tasks);
        state = deduped;
        NotificationService.rescheduleAll(deduped);
        WidgetBridge.notifyUpdate(allTasks: state, allProjects: ref.read(projectsProvider));
        await advanceMissedRecurringTasks();
      }).catchError((e, st) {
        debugPrint('TasksNotifier._load failed: $e\n$st');
      }).whenComplete(() {
        if (!_firstLoadCompleter.isCompleted) _firstLoadCompleter.complete();
      }),
    );
  }

  // A recurring task only advanced to its next occurrence when completed
  // (see toggleTask), so missing one (never completing it) silently broke
  // the series — no next occurrence ever got created, so it stayed quiet
  // forever after. This catches any recurring task whose due date has
  // already passed and are still incomplete, and rolls the series forward
  // to the next future occurrence, independent of whether the missed one
  // ever gets completed. Call on app launch and on resume from background.
  Future<void> advanceMissedRecurringTasks() async {
    if (_advancingMissedRecurrence) return;
    _advancingMissedRecurrence = true;
    try {
      await _advanceMissedRecurringTasks();
    } finally {
      _advancingMissedRecurrence = false;
    }
  }

  Future<void> _advanceMissedRecurringTasks() async {
    final now = DateTime.now();
    for (final task in List<Task>.of(state)) {
      if (task.recurrence == null || task.dueDate == null) continue;
      if (task.isCompleted || !task.dueDate!.isBefore(now)) continue;

      final rule = Recurrence.fromStorage(task.recurrence!);
      var nextDue = rule.nextOccurrence(task.dueDate!);
      // Catch up past any other occurrences also already missed (e.g. the
      // app wasn't opened for several days) without creating one task per
      // skipped day — only the next upcoming occurrence is created.
      var guard = 0;
      while (nextDue != null && !nextDue.isAfter(now) && guard < 1000) {
        nextDue = rule.nextOccurrence(nextDue);
        guard++;
      }
      if (nextDue == null) continue;

      try {
        // Detach the series from the missed task so it can't be re-rolled
        // forward again on the next launch — it stays as a missed, visible,
        // completable task, while the new one carries the series onward.
        final detached = task.copyWith(recurrence: null);
        await _db.updateTask(detached);
        final nextTask = await _db.insertTask(
          title: task.title,
          description: task.description,
          dueDate: nextDue,
          priority: task.priority.index,
          projectId: task.projectId,
          reminderMinutes: task.reminderMinutes,
          recurrence: task.recurrence,
        );
        final idx = state.indexWhere((t) => t.id == task.id);
        final newState = List<Task>.of(state);
        if (idx != -1) newState[idx] = detached;
        newState.add(nextTask);
        state = newState;
        ref.read(syncServiceProvider.notifier).markDirty();
        unawaited(NotificationService.scheduleForTask(
          nextTask,
          style: nextTask.priority == TaskPriority.critical
              ? ReminderStyle.fullScreenAlarm
              : ReminderStyle.notification,
        ));
      } catch (e, st) {
        debugPrint('TasksNotifier.advanceMissedRecurringTasks failed for ${task.id}: $e\n$st');
      }
    }
  }

  // A fire-and-forget DB write failed after an optimistic state update
  // already applied. Reload from the DB so in-memory state can't stay
  // permanently out of sync with what was actually persisted.
  void _revertOnError(Object e, StackTrace st, String op) {
    debugPrint('TasksNotifier: $op failed, reloading from DB: $e\n$st');
    _load();
  }

  // The Android homescreen widget's "Add task" button runs in its own,
  // separate FlutterEngine (QuickAddActivity) — a totally different Dart
  // isolate from the one backing a MainActivity that's already alive in the
  // background. It writes the new task straight to the shared SQLite file,
  // but there's no in-memory channel back to this container, so without an
  // explicit re-read, this engine's `state` silently falls behind the DB
  // until the app is fully restarted. Call on resume to pick up anything
  // another engine/process wrote while this one was backgrounded.
  Future<void> refreshFromDb() async {
    try {
      final tasks = await _db.getTasks();
      final deduped = await _db.dedupeRecurrenceRollovers(tasks);
      state = deduped;
      NotificationService.rescheduleAll(deduped);
      WidgetBridge.notifyUpdate(
        allTasks: state,
        allProjects: ref.read(projectsProvider),
      );
    } catch (e, st) {
      debugPrint('TasksNotifier.refreshFromDb failed: $e\n$st');
    }
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
    // Awaited (unlike toggleTask/updateTask's fire-and-forget scheduling):
    // callers of addTask (e.g. the quick-add widget flow) may tear down
    // this engine's Activity immediately after this returns, which would
    // otherwise race ahead of the in-flight platform channel call and
    // crash the notification plugin mid-call, silently dropping the alarm.
    try {
      await NotificationService.scheduleForTask(
        task,
        style: task.priority == TaskPriority.critical
            ? ReminderStyle.fullScreenAlarm
            : ReminderStyle.notification,
      );
    } catch (e, st) {
      debugPrint('TasksNotifier.addTask: scheduleForTask failed: $e\n$st');
    }
    // Immediate, not the 2s-debounced _debouncedWidgetUpdate() other
    // mutations use — a single quick-add is a deliberate one-off action
    // (not a rapid-fire burst like reordering), and callers like
    // QuickAddActivity/QuickAddServer may tear down shortly after this
    // returns, which would otherwise race the debounce timer and drop the
    // widget refresh entirely.
    await WidgetBridge.notifyUpdate(
      allTasks: state,
      allProjects: ref.read(projectsProvider),
    );
    return task;
  }

  bool toggleTask(String id) {
    final index = state.indexWhere((t) => t.id == id);
    if (index == -1) return false;

    final task = state[index];
    final wasCompleted = task.isCompleted;
    var toggled = task.copyWith(isCompleted: !wasCompleted);

    DateTime? nextDue;
    if (!wasCompleted && task.recurrence != null && task.dueDate != null) {
      final rule = Recurrence.fromStorage(task.recurrence!);
      nextDue = rule.nextOccurrence(task.dueDate!);
      if (nextDue != null) {
        // Detach the series from the just-completed occurrence — mirrors
        // _advanceMissedRecurringTasks's detach. Without this, the original
        // task kept recurrence != null after completion, so if the resume
        // sweep's missed-recurrence check raced this call (e.g. completing
        // via the widget while the app was backgrounded), both paths rolled
        // the same series forward and created two "next" tasks.
        toggled = toggled.copyWith(recurrence: null);
      }
    }

    final newState = List<Task>.of(state);
    newState[index] = toggled;
    state = newState;

    unawaited(_db.updateTask(toggled).catchError((e, st) => _revertOnError(e, st, 'toggleTask')));
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
          style: nextTask.priority == TaskPriority.critical
              ? ReminderStyle.fullScreenAlarm
              : ReminderStyle.notification,
        );
      }).catchError((e, st) => _revertOnError(e, st, 'recurrence insertTask')));
    }
    _debouncedWidgetUpdate();
    return wasCompleted;
  }

  Task? deleteTask(String id) {
    final task = state.where((t) => t.id == id).firstOrNull;
    state = state.where((t) => t.id != id).toList();
    unawaited(_db.deleteTask(id).catchError((e, st) => _revertOnError(e, st, 'deleteTask')));
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
      style: task.priority == TaskPriority.critical
          ? ReminderStyle.fullScreenAlarm
          : ReminderStyle.notification,
    );
    _debouncedWidgetUpdate();
  }

  void clearCompleted() {
    final completed = state.where((t) => t.isCompleted).toList();
    if (completed.isEmpty) return;
    for (final t in completed) {
      unawaited(_db.deleteTask(t.id).catchError((e, st) => _revertOnError(e, st, 'clearCompleted')));
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
    unawaited(_db.updateTask(updated).catchError((e, st) => _revertOnError(e, st, 'updateTask')));
    ref.read(syncServiceProvider.notifier).markDirty();
    unawaited(NotificationService.scheduleForTask(
      updated,
      style: updated.priority == TaskPriority.critical
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
    unawaited(_db.reorderTasks(tasks.map((t) => t.id).toList())
        .catchError((e, st) => _revertOnError(e, st, 'reorderTask')));
    ref.read(syncServiceProvider.notifier).markDirty();
    _debouncedWidgetUpdate();
  }
}

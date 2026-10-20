import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plans_app/features/tasks/models/task.dart';
import 'package:plans_app/features/tasks/providers/task_provider.dart';
import 'package:plans_app/shared/database/database_service.dart';
import '../shared/fake_database_service.dart';

ProviderContainer createContainer(DatabaseService db) {
  return ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWithValue(db),
    ],
  );
}

Future<void> waitForTasks(ProviderContainer c) async {
  c.read(tasksProvider);
  await Future(() {});
  await Future(() {});
}

void main() {
  group('TasksNotifier', () {
    test('starts with empty list', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await waitForTasks(container);
      expect(container.read(tasksProvider), isEmpty);
      container.dispose();
    });

    test('addTask adds a task', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await waitForTasks(container);
      await container.read(tasksProvider.notifier).addTask(title: 'Test task');
      expect(container.read(tasksProvider).length, 1);
      container.dispose();
    });

    test('toggleTask flips isCompleted', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await waitForTasks(container);
      await container.read(tasksProvider.notifier).addTask(title: 'Toggle me');
      final added = container.read(tasksProvider).first;
      expect(added.isCompleted, false);
      container.read(tasksProvider.notifier).toggleTask(added.id);
      expect(container.read(tasksProvider).first.isCompleted, true);
      container.read(tasksProvider.notifier).toggleTask(added.id);
      expect(container.read(tasksProvider).first.isCompleted, false);
      container.dispose();
    });

    test('deleteTask removes task', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await waitForTasks(container);
      await container.read(tasksProvider.notifier).addTask(title: 'Delete me');
      final added = container.read(tasksProvider).first;
      container.read(tasksProvider.notifier).deleteTask(added.id);
      expect(container.read(tasksProvider), isEmpty);
      container.dispose();
    });

    test('updateTask replaces task fields', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await waitForTasks(container);
      await container.read(tasksProvider.notifier).addTask(title: 'Original');
      final original = container.read(tasksProvider).first;
      final updated = original.copyWith(
        title: 'Updated', priority: TaskPriority.high,
      );
      container.read(tasksProvider.notifier).updateTask(original.id, updated);
      expect(container.read(tasksProvider).first.title, 'Updated');
      expect(container.read(tasksProvider).first.priority, TaskPriority.high);
      container.dispose();
    });

    test('advanceMissedRecurringTasks rolls a missed daily task forward', () async {
      final db = FakeDatabaseService();
      final missed = await db.insertTask(
        title: 'Take pills',
        dueDate: DateTime.now().subtract(const Duration(days: 3)),
        recurrence: 'daily|1',
        priority: TaskPriority.critical.index,
      );
      final container = createContainer(db);
      await waitForTasks(container);
      await waitForTasks(container);

      final tasks = container.read(tasksProvider);
      final stillMissed = tasks.firstWhere((t) => t.id == missed.id);
      expect(stillMissed.recurrence, isNull,
          reason: 'series should detach from the missed occurrence');
      expect(stillMissed.isCompleted, false,
          reason: 'the missed task itself stays as-is, just detached');

      final next = tasks.firstWhere((t) => t.id != missed.id);
      expect(next.title, 'Take pills');
      expect(next.recurrence, 'daily|1');
      expect(next.dueDate!.isAfter(DateTime.now()), true,
          reason: 'next occurrence must be rolled forward into the future');
      container.dispose();
    });

    test('advanceMissedRecurringTasks leaves on-time recurring tasks alone', () async {
      final db = FakeDatabaseService();
      await db.insertTask(
        title: 'Future daily',
        dueDate: DateTime.now().add(const Duration(hours: 1)),
        recurrence: 'daily|1',
      );
      final container = createContainer(db);
      await waitForTasks(container);
      await waitForTasks(container);

      expect(container.read(tasksProvider).length, 1);
      expect(container.read(tasksProvider).first.recurrence, 'daily|1');
      container.dispose();
    });

    test('toggleTask on a recurring task detaches recurrence from the completed original', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await waitForTasks(container);
      await container.read(tasksProvider.notifier).addTask(
        title: 'Daily standup',
        dueDate: DateTime.now().add(const Duration(hours: 1)),
        recurrence: 'daily|1',
      );
      final original = container.read(tasksProvider).first;

      container.read(tasksProvider.notifier).toggleTask(original.id);
      await Future(() {});
      await Future(() {});

      final tasks = container.read(tasksProvider);
      expect(tasks.length, 2);
      final completed = tasks.firstWhere((t) => t.id == original.id);
      expect(completed.isCompleted, true);
      expect(completed.recurrence, isNull,
          reason: 'completed occurrence must not still own the series, or a '
              'later missed-recurrence sweep could roll it forward again '
              'and create a duplicate "next" task');

      final next = tasks.firstWhere((t) => t.id != original.id);
      expect(next.recurrence, 'daily|1');
      expect(next.isCompleted, false);

      // A sweep right after completing must not create a second "next" task.
      await container.read(tasksProvider.notifier).advanceMissedRecurringTasks();
      expect(container.read(tasksProvider).length, 2);
      container.dispose();
    });

    // test('clearCompleted removes only completed tasks', () async {
    //   final db = FakeDatabaseService();
    //   final container = createContainer(db);
    //   await waitForTasks(container);
    //   await container.read(tasksProvider.notifier).addTask(title: 'Keep me');
    //   await container.read(tasksProvider.notifier).addTask(title: 'Remove me');
    //   await container.read(tasksProvider.notifier).addTask(title: 'Also keep');
    //   final tasks = container.read(tasksProvider);
    //   container.read(tasksProvider.notifier).toggleTask(tasks[1].id);
    //   await container.read(tasksProvider.notifier).clearCompleted();
    //   expect(container.read(tasksProvider).length, 2);
    //   expect(container.read(tasksProvider).any((t) => t.title == 'Remove me'), false);
    //   container.dispose();
    // });
  });

  group('filteredTasksProvider', () {
    test('shows all tasks for inbox view', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await waitForTasks(container);
      await container.read(tasksProvider.notifier).addTask(title: 'A');
      await container.read(tasksProvider.notifier).addTask(title: 'B');
      expect(container.read(filteredTasksProvider).length, 2);
      container.dispose();
    });
  });

  group('todayCountProvider', () {
    test('counts tasks due today', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await waitForTasks(container);
      await container.read(tasksProvider.notifier).addTask(
        title: 'Due today', dueDate: DateTime.now(),
      );
      await container.read(tasksProvider.notifier).addTask(
        title: 'Due tomorrow', dueDate: DateTime.now().add(const Duration(days: 1)),
      );
      expect(container.read(todayCountProvider), 1);
      container.dispose();
    });
  });
}

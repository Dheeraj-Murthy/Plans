import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plans_app/features/tasks/providers/subtask_provider.dart';
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

Future<void> flush(ProviderContainer c) async {
  await Future(() {});
  await Future(() {});
}

void main() {
  group('SubtasksNotifier', () {
    test('add appends a subtask', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      final task = await container.read(tasksProvider.notifier).addTask(title: 'Parent');
      await flush(container);

      await container.read(subtasksProvider(task.id).notifier).add('Step 1');
      expect(container.read(subtasksProvider(task.id)).length, 1);
      expect(container.read(subtasksProvider(task.id)).first.title, 'Step 1');
      container.dispose();
    });

    test('toggle flips completion and rename edits title', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      final task = await container.read(tasksProvider.notifier).addTask(title: 'Parent');
      await flush(container);

      final notifier = container.read(subtasksProvider(task.id).notifier);
      await notifier.add('Step 1');
      final sub = container.read(subtasksProvider(task.id)).first;

      await notifier.toggle(sub.id);
      expect(container.read(subtasksProvider(task.id)).first.isCompleted, true);

      await notifier.rename(sub.id, 'Renamed');
      expect(container.read(subtasksProvider(task.id)).first.title, 'Renamed');
      container.dispose();
    });

    test('remove deletes a subtask', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      final task = await container.read(tasksProvider.notifier).addTask(title: 'Parent');
      await flush(container);

      final notifier = container.read(subtasksProvider(task.id).notifier);
      await notifier.add('Step 1');
      final sub = container.read(subtasksProvider(task.id)).first;
      await notifier.remove(sub.id);

      expect(container.read(subtasksProvider(task.id)), isEmpty);
      container.dispose();
    });

    test('completing the last subtask auto-completes the parent task', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      final task = await container.read(tasksProvider.notifier).addTask(title: 'Parent');
      await flush(container);

      final notifier = container.read(subtasksProvider(task.id).notifier);
      await notifier.add('Step 1');
      await notifier.add('Step 2');
      final subs = container.read(subtasksProvider(task.id));

      await notifier.toggle(subs[0].id);
      expect(
        container.read(tasksProvider).firstWhere((t) => t.id == task.id).isCompleted,
        false,
        reason: 'parent should stay open while any subtask is incomplete',
      );

      await notifier.toggle(subs[1].id);
      expect(
        container.read(tasksProvider).firstWhere((t) => t.id == task.id).isCompleted,
        true,
        reason: 'parent should auto-complete once every subtask is done',
      );
      container.dispose();
    });

    test('unchecking a subtask on a completed parent reopens it', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      final task = await container.read(tasksProvider.notifier).addTask(title: 'Parent');
      await flush(container);

      final notifier = container.read(subtasksProvider(task.id).notifier);
      await notifier.add('Step 1');
      final sub = container.read(subtasksProvider(task.id)).first;
      await notifier.toggle(sub.id); // completes the only subtask -> auto-completes parent

      expect(
        container.read(tasksProvider).firstWhere((t) => t.id == task.id).isCompleted,
        true,
      );

      await notifier.toggle(sub.id); // reopen the subtask
      expect(
        container.read(tasksProvider).firstWhere((t) => t.id == task.id).isCompleted,
        false,
        reason: 'parent should reopen once a subtask is unchecked',
      );
      container.dispose();
    });

    test('progress counts patch onto the parent task', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      final task = await container.read(tasksProvider.notifier).addTask(title: 'Parent');
      await flush(container);

      final notifier = container.read(subtasksProvider(task.id).notifier);
      await notifier.add('Step 1');
      await notifier.add('Step 2');
      final subs = container.read(subtasksProvider(task.id));
      await notifier.toggle(subs[0].id);

      final parent = container.read(tasksProvider).firstWhere((t) => t.id == task.id);
      expect(parent.subtaskTotal, 2);
      expect(parent.subtaskCompleted, 1);
      container.dispose();
    });
  });
}

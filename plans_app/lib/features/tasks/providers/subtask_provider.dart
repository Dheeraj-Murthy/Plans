import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/subtask.dart';
import '../providers/task_provider.dart';
import '../../../shared/database/database_service.dart';

final subtasksProvider =
    NotifierProvider.family<SubtasksNotifier, List<Subtask>, String>(
  (taskId) => SubtasksNotifier(taskId),
);

class SubtasksNotifier extends Notifier<List<Subtask>> {
  final String taskId;
  SubtasksNotifier(this.taskId);

  late DatabaseService _db;

  @override
  List<Subtask> build() {
    _db = ref.read(databaseServiceProvider);
    _load();
    return [];
  }

  void _load() {
    _db.getSubtasks(taskId).then((subtasks) {
      state = subtasks;
    }).catchError((e, st) {
      debugPrint('SubtasksNotifier._load failed for $taskId: $e\n$st');
    });
  }

  Future<void> add(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final subtask = await _db.insertSubtask(taskId, trimmed);
    state = [...state, subtask];
    _syncCounts();
  }

  Future<void> rename(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final idx = state.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = state[idx].copyWith(title: trimmed);
    await _db.updateSubtask(updated);
    final newState = List<Subtask>.of(state);
    newState[idx] = updated;
    state = newState;
  }

  Future<void> toggle(String id) async {
    final idx = state.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final updated = state[idx].copyWith(isCompleted: !state[idx].isCompleted);
    await _db.updateSubtask(updated);
    final newState = List<Subtask>.of(state);
    newState[idx] = updated;
    state = newState;
    _syncCounts();
    _syncParentCompletion();
  }

  Future<void> remove(String id) async {
    await _db.deleteSubtask(id);
    state = state.where((s) => s.id != id).toList();
    _syncCounts();
    _syncParentCompletion();
  }

  void _syncCounts() {
    final total = state.length;
    final completed = state.where((s) => s.isCompleted).length;
    ref.read(tasksProvider.notifier).patchSubtaskCounts(taskId, total, completed);
  }

  // Subtasks act as a completion gate on the parent: finishing the last one
  // auto-completes the task, and reopening one un-completes it again.
  // Reuses toggleTask's existing side effects (notification cancel/
  // reschedule, recurrence advance, undo stack) instead of duplicating them.
  void _syncParentCompletion() {
    if (state.isEmpty) return;
    final allComplete = state.every((s) => s.isCompleted);
    final tasks = ref.read(tasksProvider);
    final parent = tasks.where((t) => t.id == taskId).firstOrNull;
    if (parent == null) return;
    if (parent.isCompleted != allComplete) {
      ref.read(tasksProvider.notifier).toggleTask(taskId);
    }
  }
}

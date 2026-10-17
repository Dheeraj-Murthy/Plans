import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/subtask_provider.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import 'subtask_row.dart';

/// The composer's subtasks checklist. Collapsed behind a plain
/// "+ Add subtask" button by default, so a task without subtasks doesn't
/// carry a big empty section — expands (and stays expanded) once there's
/// something to show, either existing subtasks or one the user just added.
///
/// A task that doesn't exist yet has no id to attach real subtasks to, so
/// for that case the caller owns a staged title list instead ([stagedTitles]
/// / [onStagedTitlesChanged]); the caller is responsible for creating the
/// real subtasks once the task itself has been saved. Pass [taskId] once the
/// task is real and this widget talks to [subtasksProvider] directly.
class SubtasksSection extends ConsumerStatefulWidget {
  final String? taskId;
  final List<String> stagedTitles;
  final ValueChanged<List<String>> onStagedTitlesChanged;
  final bool initiallyExpanded;

  const SubtasksSection({
    super.key,
    required this.taskId,
    required this.stagedTitles,
    required this.onStagedTitlesChanged,
    required this.initiallyExpanded,
  });

  @override
  ConsumerState<SubtasksSection> createState() => _SubtasksSectionState();
}

class _SubtasksSectionState extends ConsumerState<SubtasksSection> {
  final _newSubtaskController = TextEditingController();
  final _focusNode = FocusNode();
  late bool _expanded = widget.initiallyExpanded;

  @override
  void dispose() {
    _newSubtaskController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _addSubtask(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final taskId = widget.taskId;
    if (taskId != null) {
      ref.read(subtasksProvider(taskId).notifier).add(trimmed);
    } else {
      widget.onStagedTitlesChanged([...widget.stagedTitles, trimmed]);
    }
    _newSubtaskController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return GestureDetector(
        onTap: _expand,
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 18, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Add subtask',
              style: AppTypography.label.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[];
    final taskId = widget.taskId;
    if (taskId != null) {
      for (final s in ref.watch(subtasksProvider(taskId))) {
        rows.add(SubtaskRow(
          title: s.title,
          isCompleted: s.isCompleted,
          onToggle: () => ref.read(subtasksProvider(taskId).notifier).toggle(s.id),
          onDelete: () => ref.read(subtasksProvider(taskId).notifier).remove(s.id),
        ));
      }
    } else {
      for (var i = 0; i < widget.stagedTitles.length; i++) {
        final title = widget.stagedTitles[i];
        rows.add(SubtaskRow(
          title: title,
          isCompleted: false,
          onDelete: () {
            final updated = [...widget.stagedTitles]..removeAt(i);
            widget.onStagedTitlesChanged(updated);
          },
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.checklist_rounded, size: 20, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Text('Subtasks', style: AppTypography.label.copyWith(color: AppColors.textMuted)),
          ],
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ...rows,
        ],
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: TextField(
            controller: _newSubtaskController,
            focusNode: _focusNode,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            decoration: InputDecoration(
              hintText: 'Add subtask...',
              hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: _addSubtask,
          ),
        ),
      ],
    );
  }
}

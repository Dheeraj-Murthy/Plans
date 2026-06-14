import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../widgets/add_task_sheet.dart';
import '../../../theme/app_animations.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import '../../../shared/widgets/app_checkbox.dart';
import '../../../shared/widgets/hover_action_icon.dart';
import '../../../shared/widgets/priority_dot.dart';

class TaskTile extends ConsumerStatefulWidget {
  final Task task;
  final int index;
  final bool showTime;
  final bool showFullDate;
  final String? projectName;
  final Color? projectColor;

  const TaskTile({
    super.key,
    required this.task,
    required this.index,
    this.showTime = false,
    this.showFullDate = false,
    this.projectName,
    this.projectColor,
  });

  @override
  ConsumerState<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends ConsumerState<TaskTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _formatDueDate(DateTime? date) {
    if (date == null) return '';
    if (widget.showFullDate) {
      return '${_months[date.month - 1]} ${date.day}';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(date.year, date.month, date.day);
    final diff = due.difference(today).inDays;

    return switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => '${date.month}/${date.day}',
    };
  }

  String _formatTime(DateTime date) {
    final h = date.hour;
    final m = date.minute;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  bool get _hasTime {
    final due = widget.task.dueDate;
    return due != null && (due.hour != 0 || due.minute != 0);
  }

  bool get _isOverdue {
    final due = widget.task.dueDate;
    if (due == null) return false;
    if (widget.task.isCompleted) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(due.year, due.month, due.day);
    return dueDate.isBefore(today);
  }

  void _openEditSheet() {
    final screenHeight = MediaQuery.of(context).size.height;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss task details',
      barrierColor: Colors.black45,
      transitionDuration: AppAnimations.normal,
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
              .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: AppAnimations.easeOut,
                ),
              ),
          child: child,
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;
        final margin = isMobile ? 0.05 : 0.2;
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned(
                  top: screenHeight * 0.2,
                  bottom: screenHeight * 0.2,
                  left: screenWidth * margin,
                  right: screenWidth * margin,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AddTaskSheet(existingTask: widget.task),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _cyclePriority() {
    final values = TaskPriority.values;
    final current = widget.task.priority;
    final next = values[(current.index + 1) % values.length];
    final updated = widget.task.copyWith(priority: next);
    ref.read(tasksProvider.notifier).updateTask(widget.task.id, updated);
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final hasDescription =
        task.description != null &&
        task.description!.isNotEmpty &&
        !task.isCompleted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => Future.delayed(
          const Duration(milliseconds: 200),
          () {
            if (mounted) setState(() => _isPressed = false);
          },
        ),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
              decoration: BoxDecoration(
                color: _isPressed
                    ? AppColors.elevated
                    : _isHovered
                        ? AppColors.surface
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: EdgeInsets.only(top: hasDescription ? 4 : 2, bottom: 2),
              child: Row(
                crossAxisAlignment: hasDescription
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    child: AnimatedOpacity(
                      duration: AppAnimations.fast,
                      opacity: _isHovered ? 1.0 : 0.0,
                      child: ReorderableDragStartListener(
                        index: widget.index,
                        child: Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: AppColors.textMuted.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedContainer(
                          duration: AppAnimations.normal,
                          curve: AppAnimations.easeOut,
                          width: 3,
                          height: task.isCompleted ? 0 : 20,
                          decoration: BoxDecoration(
                            color: switch (task.priority) {
                              TaskPriority.critical => AppColors.priorityCritical,
                              TaskPriority.high => AppColors.priorityHigh,
                              TaskPriority.medium => AppColors.priorityMedium,
                              TaskPriority.low => AppColors.priorityLow,
                              TaskPriority.none => Colors.transparent,
                            },
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                  const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Checkbox + title on same row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  AppCheckbox(
                                    value: task.isCompleted,
                                    onChanged: (_) {
                                      final wasCompleted = ref
                                          .read(tasksProvider.notifier)
                                          .toggleTask(task.id);
                                      if (!wasCompleted) {
                                        final action = TaskToggled(task.id, false);
                                        ref.read(undoStackProvider.notifier).push(action);
                                        ref.read(lastUndoActionProvider.notifier).set(action);
                                      }
                                    },
                                    color: switch (task.priority) {
                                      TaskPriority.critical =>
                                        AppColors.priorityCritical,
                                      TaskPriority.high =>
                                        AppColors.priorityHigh,
                                      TaskPriority.medium =>
                                        AppColors.priorityMedium,
                                      TaskPriority.low => AppColors.priorityLow,
                                      TaskPriority.none => null,
                                    },
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _openEditSheet,
                                      child: AnimatedDefaultTextStyle(
                                        duration: AppAnimations.medium,
                                        curve: AppAnimations.easeOut,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.bodyMedium
                                            .copyWith(
                                              color: task.isCompleted
                                                  ? AppColors.textMuted
                                                  : AppColors.textPrimary,
                                            ),
                                        child: task.isCompleted
                                            ? _StrikethroughText(
                                                text: task.title,
                                                style: AppTypography.bodyMedium
                                                    .copyWith(
                                                      color:
                                                          AppColors.textMuted,
                                                    ),
                                              )
                                            : Text(task.title),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (task.description != null &&
                                  task.description!.isNotEmpty &&
                                  !task.isCompleted)
                                Padding(
                                  // 18 (checkbox) + 12 (md spacing) = offset aligns with title
                                  padding: const EdgeInsets.only(
                                    left: 30,
                                    top: 4,
                                  ),
                                  child: Text(
                                    task.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Metadata row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Priority dot
                      if (task.priority != TaskPriority.none &&
                          !task.isCompleted)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: PriorityDot(priority: task.priority),
                        ),

                      // Project pill
                      if (widget.projectName != null && !task.isCompleted)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (widget.projectColor ?? Colors.grey).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.projectName!,
                              style: AppTypography.label.copyWith(
                                fontSize: 11,
                                color: widget.projectColor,
                              ),
                            ),
                          ),
                        ),

                      // Recurrence icon
                      if (task.recurrence != null && !task.isCompleted)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.repeat_outlined,
                            size: 12,
                            color: AppColors.accent.withValues(alpha: 0.7),
                          ),
                        ),

                      // Due date pill
                      if (task.dueDate != null && !task.isCompleted)
                        AnimatedOpacity(
                          duration: AppAnimations.fast,
                          opacity: _isHovered ? 0 : 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _isOverdue
                                      ? AppColors.danger.withValues(alpha: 0.12)
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _formatDueDate(task.dueDate),
                                  style: AppTypography.label.copyWith(
                                    fontSize: 11,
                                    color: _isOverdue
                                        ? AppColors.danger
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ),
                              if (widget.showTime && _hasTime) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _formatTime(task.dueDate!),
                                    style: AppTypography.label.copyWith(
                                      fontSize: 11,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                      // Hover actions
                      if (_isHovered)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HoverActionIcon(
                              icon: Icons.flag_outlined,
                              onTap: _cyclePriority,
                            ),
                            const SizedBox(width: 2),
                            HoverActionIcon(
                              icon: Icons.delete_outline_rounded,
                              onTap: () {
                                final deleted = ref
                                    .read(tasksProvider.notifier)
                                    .deleteTask(task.id);
                                if (deleted != null) {
                                  final action = TaskDeleted(deleted);
                                  ref.read(undoStackProvider.notifier).push(action);
                                  ref.read(lastUndoActionProvider.notifier).set(action);
                                }
                              },
                            ),
                            const SizedBox(width: 2),
                            HoverActionIcon(
                              icon: Icons.more_horiz_rounded,
                              onTap: _openEditSheet,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(width: 5),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 0.5,
              color: AppColors.border,
            ),
          ],
        ),
        ),
      );
  }
}

class _StrikethroughText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _StrikethroughText({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppAnimations.medium,
      curve: AppAnimations.easeOut,
      builder: (context, value, child) {
        return Stack(
          children: [
            Text(text, style: style),
            Positioned(
              bottom: (style.fontSize ?? 14) * 0.4,
              left: 0,
              right: 0,
              child: FractionallySizedBox(
                widthFactor: value,
                child: Container(
                  height: 1,
                  color: AppColors.textMuted.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

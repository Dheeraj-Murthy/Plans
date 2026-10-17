import 'package:flutter/material.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

/// One checklist line for a subtask — used by both the composer
/// (editable, with a delete button) and the task list's inline
/// expanded view (read/toggle only, no delete button).
class SubtaskRow extends StatelessWidget {
  final String title;
  final bool isCompleted;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;
  final double iconSize;

  const SubtaskRow({
    super.key,
    required this.title,
    required this.isCompleted,
    this.onToggle,
    this.onDelete,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Icon(
              isCompleted
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: iconSize,
              color: isCompleted ? AppColors.accent : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: AppTypography.bodySmall.copyWith(
                color: isCompleted ? AppColors.textMuted : AppColors.textSecondary,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (onDelete != null)
            GestureDetector(
              onTap: onDelete,
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

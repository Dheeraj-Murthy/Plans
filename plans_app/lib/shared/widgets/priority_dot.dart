import 'package:flutter/material.dart';
import '../../features/tasks/models/task.dart';
import '../../theme/app_theme.dart';

class PriorityDot extends StatelessWidget {
  final TaskPriority priority;
  final double size;

  const PriorityDot({
    super.key,
    required this.priority,
    this.size = 6,
  });

  Color? get _color {
    return switch (priority) {
      TaskPriority.critical => AppColors.priorityCritical,
      TaskPriority.high => AppColors.priorityHigh,
      TaskPriority.medium => AppColors.priorityMedium,
      TaskPriority.low => AppColors.priorityLow,
      TaskPriority.none => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_color == null) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _color,
        shape: BoxShape.circle,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/tasks/models/task.dart';
import '../../features/projects/providers/project_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';

IconData projectIcon(String name) {
  return switch (name.toLowerCase()) {
    'work' => Icons.work_outline_rounded,
    'personal' => Icons.person_outline_rounded,
    'ideas' => Icons.lightbulb_outline_rounded,
    'inbox' => Icons.inbox_rounded,
    _ => Icons.folder_outlined,
  };
}

Future<TaskPriority?> showPriorityMenu(
    BuildContext context, GlobalKey anchorKey) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return null;
  final offset = box.localToGlobal(Offset.zero);
  final size = box.size;
  return showMenu<TaskPriority>(
    context: context,
    position: RelativeRect.fromLTRB(
      offset.dx, offset.dy,
      offset.dx + size.width, offset.dy,
    ),
    items: [
      for (final p in TaskPriority.values)
        PopupMenuItem(
          value: p,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                p == TaskPriority.none
                    ? Icons.flag_outlined
                    : Icons.flag_rounded,
                size: 16,
                color: switch (p) {
                  TaskPriority.critical => AppColors.priorityCritical,
                  TaskPriority.high => AppColors.priorityHigh,
                  TaskPriority.medium => AppColors.priorityMedium,
                  TaskPriority.low => AppColors.priorityLow,
                  TaskPriority.none => AppColors.textMuted,
                },
              ),
              const SizedBox(width: 8),
              Text(
                p == TaskPriority.none ? 'None' : p.name,
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
    ],
  );
}

Future<String?> showProjectMenu(
    BuildContext context, GlobalKey anchorKey, WidgetRef ref) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return null;
  final projects = ref.read(projectsProvider);
  if (projects.isEmpty) return null;
  final offset = box.localToGlobal(Offset.zero);
  final size = box.size;
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      offset.dx, offset.dy,
      offset.dx + size.width, offset.dy,
    ),
    items: [
      for (int i = 0; i < projects.length; i++)
        if (projects[i].id != 'default')
          PopupMenuItem(
            value: projects[i].id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  projectIcon(projects[i].name),
                  size: 16,
                  color: AppColors.projectColors[
                      projects[i].colorIndex % AppColors.projectColors.length],
                ),
                const SizedBox(width: 8),
                Text(projects[i].name, style: AppTypography.bodySmall),
              ],
            ),
          ),
    ],
  );
}

Future<DateTime?> pickDate(BuildContext context, DateTime? current) async {
  final date = await showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime.now().subtract(const Duration(days: 7)),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          datePickerTheme: DatePickerThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            todayBorder: const BorderSide(color: AppColors.accent, width: 1),
            todayForegroundColor: WidgetStateProperty.all(AppColors.accent),
            dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return AppColors.accent;
              return null;
            }),
            dayForegroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Colors.white;
              return null;
            }),
            dayShape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            headerHelpStyle: const TextStyle(fontSize: 11),
            headerHeadlineStyle: const TextStyle(fontSize: 22),
          ),
        ),
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.82)),
          child: child!,
        ),
      );
    },
  );
  if (date == null) return null;

  if (!context.mounted) return date;
  final initialTime = current != null
      ? TimeOfDay(hour: current.hour, minute: current.minute)
      : TimeOfDay.now();
  final time = await showTimePicker(
    context: context,
    initialTime: initialTime,
    initialEntryMode: TimePickerEntryMode.dial,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.0),
      ),
      child: child!,
    ),
  );
  if (time == null) {
    return DateTime(date.year, date.month, date.day, 9, 0);
  }
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

String formatDueDateTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(dt.year, dt.month, dt.day);
  final diff = due.difference(today).inDays;

  final datePart = switch (diff) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => '${dt.month}/${dt.day}',
  };

  final hasTime = dt.hour != 0 || dt.minute != 0;
  if (!hasTime) return datePart;

  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '$datePart $hour:$minute $period';
}

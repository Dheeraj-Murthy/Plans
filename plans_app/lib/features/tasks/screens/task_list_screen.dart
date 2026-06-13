import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../widgets/task_tile.dart';
import '../../projects/providers/project_provider.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_animations.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import '../../../shared/widgets/sidebar/sticky_composer.dart';

class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(sidebarSelectionProvider);
    final title = switch (selection) {
      ViewSelection(:final view) => switch (view) {
          ViewType.inbox => 'Inbox',
          ViewType.timeline => 'Timeline',
          ViewType.today => 'Today',
          ViewType.completed => 'Completed',
        },
      ProjectSelection(:final projectId) =>
        ref.watch(projectsProvider).where((p) => p.id == projectId).firstOrNull?.name ?? 'Tasks',
    };

    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    final isTimeline = selection is ViewSelection && selection.view == ViewType.timeline;

    return Column(
      children: [
        if (isDesktop)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.sm,
            ),
            child: Text(title, style: AppTypography.headingLarge),
          ),
        Expanded(child: isTimeline ? const _TimelineBody() : const _TaskListBody()),
        if (isDesktop) const StickyComposer(),
      ],
    );
  }
}

Map<String, ({String name, Color color})> _projectMap(WidgetRef ref) {
  final projects = ref.watch(projectsProvider);
  return {for (final p in projects) p.id: (
    name: p.name,
    color: AppColors.projectColors[p.colorIndex % AppColors.projectColors.length],
  )};
}

bool _hasTime(DateTime dt) => dt.hour != 0 || dt.minute != 0;

class _TaskListBody extends ConsumerWidget {
  const _TaskListBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredTasksProvider);
    final completingIds = ref.watch(completingTaskIdsProvider);
    final uncompletingIds = ref.watch(uncompletingTaskIdsProvider);
    final projMap = _projectMap(ref);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No tasks yet',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    final incomplete = <Task>[];
    final completed = <Task>[];
    for (final t in filtered) {
      if (completingIds.contains(t.id)) {
        incomplete.add(t);
      } else if (uncompletingIds.contains(t.id)) {
        completed.add(t);
      } else if (t.isCompleted) {
        completed.add(t);
      } else {
        incomplete.add(t);
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSpacing.maxContentWidth,
        ),
        child: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            if (incomplete.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: incomplete.length,
                onReorder: (oldIndex, newIndex) {
                  ref
                      .read(tasksProvider.notifier)
                      .reorderTask(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final task = incomplete[index];
                  final isCompleting = completingIds.contains(task.id);
                  return _ExitAnimation(
                    key: ValueKey(task.id),
                    isCompleting: isCompleting,
                    child: TaskTile(
                      task: task,
                      index: index,
                      showTime: task.dueDate != null && _hasTime(task.dueDate!),
                      projectName: projMap[task.projectId]?.name,
                      projectColor: projMap[task.projectId]?.color,
                    ),
                  );
                },
              ),
            if (completed.isNotEmpty && incomplete.isNotEmpty)
              _SectionDivider(count: completed.length),
            ...completed.asMap().entries.map(
              (e) => TaskTile(
                key: ValueKey('completed-${e.value.id}'),
                task: e.value,
                index: incomplete.length + e.key,
                projectName: projMap[e.value.projectId]?.name,
                projectColor: projMap[e.value.projectId]?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineBody extends ConsumerWidget {
  const _TimelineBody();

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _dayLabel(DateTime day, DateTime today) {
    if (day == today) return 'Today';
    final diff = day.difference(today).inDays;
    if (diff == 1) return 'Tomorrow';
    if (diff < 7) return _weekdays[day.weekday - 1];
    return '${_months[day.month - 1]} ${day.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredTasksProvider);
    final projMap = _projectMap(ref);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No upcoming tasks',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final overdue = <Task>[];
    final todayTasks = <Task>[];
    final futureMap = <DateTime, List<Task>>{};

    for (final t in filtered) {
      final due = t.dueDate!;
      final dueDay = DateTime(due.year, due.month, due.day);
      if (dueDay.isBefore(today)) {
        overdue.add(t);
      } else if (dueDay == today) {
        todayTasks.add(t);
      } else {
        futureMap.putIfAbsent(dueDay, () => []).add(t);
      }
    }

    final sortedFuture = futureMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            if (overdue.isNotEmpty)
              _OverdueSection(tasks: overdue, today: today, projMap: projMap),
            if (todayTasks.isNotEmpty) ...[
              _DayHeader(label: 'Today', count: todayTasks.length),
              ...todayTasks.map((t) => TaskTile(
                key: ValueKey(t.id),
                task: t,
                index: 0,
                showTime: _hasTime(t.dueDate!),
                projectName: projMap[t.projectId]?.name,
                projectColor: projMap[t.projectId]?.color,
              )),
            ],
            ...sortedFuture.map((entry) => Column(
              children: [
                _DayHeader(
                  label: _dayLabel(entry.key, today),
                  count: entry.value.length,
                ),
                ...entry.value.map((t) => TaskTile(
                  key: ValueKey(t.id),
                  task: t,
                  index: 0,
                  showTime: _hasTime(t.dueDate!),
                  projectName: projMap[t.projectId]?.name,
                  projectColor: projMap[t.projectId]?.color,
                )),
              ],
            )),
          ],
        ),
      ),
    );
  }
}

class _OverdueSection extends StatefulWidget {
  final List<Task> tasks;
  final DateTime today;
  final Map<String, ({String name, Color color})> projMap;
  const _OverdueSection({
    required this.tasks,
    required this.today,
    required this.projMap,
  });

  @override
  State<_OverdueSection> createState() => _OverdueSectionState();
}

class _OverdueSectionState extends State<_OverdueSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 6),
                Text(
                  'Overdue — ${widget.tasks.length}',
                  style: AppTypography.caption.copyWith(color: AppColors.danger),
                ),
                const Spacer(),
                Container(
                  width: 1,
                  height: 12,
                  color: AppColors.border,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...widget.tasks.map((t) => TaskTile(
            key: ValueKey('overdue-${t.id}'),
            task: t,
            index: 0,
            showTime: _hasTime(t.dueDate!),
            showFullDate: true,
            projectName: widget.projMap[t.projectId]?.name,
            projectColor: widget.projMap[t.projectId]?.color,
          )),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  final int count;
  const _DayHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '$label ($count)',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Divider(color: AppColors.border, thickness: 0.5, height: 1),
          ),
        ],
      ),
    );
  }
}

class _ExitAnimation extends StatefulWidget {
  final bool isCompleting;
  final Widget child;

  const _ExitAnimation({
    required this.isCompleting,
    required this.child,
    super.key,
  });

  @override
  State<_ExitAnimation> createState() => _ExitAnimationState();
}

class _ExitAnimationState extends State<_ExitAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.medium,
    );
    if (widget.isCompleting) _scheduleExit();
  }

  @override
  void didUpdateWidget(_ExitAnimation old) {
    super.didUpdateWidget(old);
    if (!old.isCompleting && widget.isCompleting) _scheduleExit();
  }

  void _scheduleExit() {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _controller.value;
        if (v == 0) return child!;
        return Opacity(
          opacity: 1 - v,
          child: Transform.scale(
            scale: 1 - 0.15 * v,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final int count;

  const _SectionDivider({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            'Completed — $count',
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Divider(
              color: AppColors.border,
              thickness: 0.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

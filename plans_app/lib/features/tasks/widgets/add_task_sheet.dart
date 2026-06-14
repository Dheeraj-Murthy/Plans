import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../../../shared/widgets/app_chip.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import '../../../shared/helpers/recurrence.dart';
import '../../../shared/helpers/task_helpers.dart';
import '../../../shared/helpers/task_parser.dart';
import '../../../shared/widgets/highlighted_task_controller.dart';
import '../../projects/providers/project_provider.dart';
import '../../../theme/app_animations.dart';

class AddTaskSheet extends ConsumerStatefulWidget {
  final Task? existingTask;

  const AddTaskSheet({super.key, this.existingTask});

  @override
  ConsumerState<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<AddTaskSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late DateTime? _dueDate;
  late TaskPriority _priority;
  late int _localProjectIndex;
  late int? _reminderMinutes;
  String? _recurrence;
  final _priorityKey = GlobalKey();
  final _projectKey = GlobalKey();
  final _reminderKey = GlobalKey();
  final _titleFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    _titleController = HighlightedTaskController(text: task?.title ?? '');
    _descriptionController =
        TextEditingController(text: task?.description ?? '');
    _dueDate = task?.dueDate;
    _priority = task?.priority ?? TaskPriority.none;
    _reminderMinutes = task?.reminderMinutes;
    _recurrence = task?.recurrence;

    if (task != null) {
      final projects = ref.read(projectsProvider);
      _localProjectIndex =
          projects.indexWhere((p) => p.id == task.projectId);
      if (_localProjectIndex < 0) _localProjectIndex = 0;
    } else {
      _localProjectIndex = 0;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNode.requestFocus();
      _titleController.selection = TextSelection.fromPosition(
        TextPosition(offset: _titleController.text.length),
      );
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingTask != null;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final currentProjectId = projects.isNotEmpty
        ? projects[_localProjectIndex % projects.length].id
        : 'default';

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl + bottomInset,
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.radio_button_unchecked_rounded,
                size: 20,
                color: switch (_priority) {
                  TaskPriority.critical => AppColors.priorityCritical,
                  TaskPriority.high => AppColors.priorityHigh,
                  TaskPriority.medium => AppColors.priorityMedium,
                  TaskPriority.low => AppColors.priorityLow,
                  TaskPriority.none => AppColors.textMuted,
                }.withValues(alpha: 0.4),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  autofocus: true,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'What needs to be done?',
                    hintStyle: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textMuted,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: AppSpacing.sm,
                    children: [
                      AppChip(
                        key: _priorityKey,
                        icon: Icons.flag_outlined,
                        label: _priority == TaskPriority.none
                            ? 'Priority'
                            : _priority.name,
                        color: _priority == TaskPriority.critical
                            ? AppColors.priorityCritical
                            : _priority == TaskPriority.high
                                ? AppColors.priorityHigh
                                : _priority == TaskPriority.medium
                                    ? AppColors.priorityMedium
                                    : null,
                        onTap: _showPriorityMenu,
                      ),
                      AppChip(
                        icon: Icons.calendar_today_outlined,
                        label: _dueDate != null
                            ? formatDueDateTime(_dueDate!)
                            : 'Due date',
                        onTap: _pickDate,
                      ),
                      AppChip(
                        key: _reminderKey,
                        icon: Icons.notifications_outlined,
                        label: _reminderLabel,
                        color: _reminderMinutes != null ? AppColors.accent : null,
                        onTap: _showReminderMenu,
                      ),
                      AppChip(
                        icon: Icons.repeat_outlined,
                        label: _recurrence != null
                            ? Recurrence.fromStorage(_recurrence!).label
                            : 'Repeat',
                        color: _recurrence != null ? AppColors.accent : null,
                        onTap: _showRecurrenceMenu,
                      ),
                      AppChip(
                        key: _projectKey,
                        icon: Icons.folder_outlined,
                        label: projects
                            .where((p) => p.id == currentProjectId)
                            .firstOrNull
                            ?.name ?? 'Project',
                        onTap: _showProjectMenu,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: () {
                    ref
                        .read(tasksProvider.notifier)
                        .deleteTask(widget.existingTask!.id);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: _submit,
                child: AnimatedContainer(
                  duration: AppAnimations.fast,
                  curve: AppAnimations.easeOut,
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(
            color: AppColors.border,
            height: 1,
            thickness: 1,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.short_text_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _descriptionController,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add description...',
                    hintStyle: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  maxLines: null,
                  minLines: 3,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  }

  String get _reminderLabel {
    return switch (_reminderMinutes) {
      null => 'Remind',
      0 => 'At due time',
      5 => '5 min before',
      15 => '15 min before',
      30 => '30 min before',
      60 => '1 hr before',
      _ => '$_reminderMinutes min before',
    };
  }

  static const _reminderNone = -1;

  Future<void> _showReminderMenu() async {
    final options = [_reminderNone, 0, 5, 15, 30, 60];
    final labels = ['None', 'At due time', '5 min before', '15 min before', '30 min before', '1 hr before'];
    final renderBox = _reminderKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final current = _reminderMinutes ?? _reminderNone;
    final result = await showMenu<int>(
      context: context,
      color: AppColors.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + renderBox.size.height + 4,
        offset.dx + renderBox.size.width,
        0,
      ),
      items: [
        for (var i = 0; i < options.length; i++)
          PopupMenuItem<int>(
            value: options[i],
            child: Text(
              labels[i],
              style: TextStyle(
                color: current == options[i]
                    ? AppColors.accent
                    : AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
    if (result != null) {
      setState(() => _reminderMinutes = result == _reminderNone ? null : result);
    }
  }

  Future<void> _showPriorityMenu() async {
    final picked = await showPriorityMenu(context, _priorityKey);
    if (picked != null) setState(() => _priority = picked);
  }

  Future<void> _showProjectMenu() async {
    final projects = ref.read(projectsProvider);
    if (projects.isEmpty) return;
    final picked = await showProjectMenu(context, _projectKey, ref);
    if (picked != null) {
      final idx = projects.indexWhere((p) => p.id == picked);
      if (idx >= 0) setState(() => _localProjectIndex = idx);
    }
  }

  Future<void> _pickDate() async {
    final date = await pickDate(context, _dueDate);
    if (date != null) setState(() => _dueDate = date);
  }

  Future<void> _showRecurrenceMenu() async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(300, 300, 300, 300),
      initialValue: _recurrence,
      items: [
        const PopupMenuItem(value: '', child: Text('Never')),
        const PopupMenuItem(value: 'daily|1', child: Text('Daily')),
        const PopupMenuItem(value: 'weekly|1', child: Text('Weekly')),
        const PopupMenuItem(value: 'weekly|1|weekdays', child: Text('Weekdays')),
        const PopupMenuItem(value: 'monthly|1', child: Text('Monthly')),
        const PopupMenuItem(value: 'yearly|1', child: Text('Yearly')),
      ],
    );
    if (result != null) {
      setState(() => _recurrence = result.isEmpty ? null : result);
    }
  }

  Future<void> _submit() async {
    final raw = _titleController.text.trim();
    if (raw.isEmpty) return;
    final desc = _descriptionController.text.trim();
    final projects = ref.read(projectsProvider);

    final parsed = TaskParser.parse(raw, projects);
    final effectiveTitle = parsed.title.isNotEmpty ? parsed.title : raw;
    final effectiveProjectId = parsed.projectId ??
        (projects.isNotEmpty
            ? projects[_localProjectIndex % projects.length].id
            : 'default');
    final effectiveDueDate = parsed.dueDate ?? _dueDate;
    final effectivePriority = parsed.priority ?? _priority;
    final effectiveReminder = parsed.hasDueDate && _reminderMinutes == null
        ? parsed.defaultReminderMinutes
        : _reminderMinutes;

    final notifier = ref.read(tasksProvider.notifier);

    if (_isEditing) {
      notifier.updateTask(
        widget.existingTask!.id,
        widget.existingTask!.copyWith(
          title: effectiveTitle,
          description: desc.isNotEmpty ? desc : null,
          dueDate: effectiveDueDate,
          priority: effectivePriority,
          projectId: effectiveProjectId,
          reminderMinutes: effectiveReminder,
          recurrence: parsed.recurrence ?? _recurrence,
        ),
      );
    } else {
      await notifier.addTask(
        title: effectiveTitle,
        description: desc.isNotEmpty ? desc : null,
        dueDate: effectiveDueDate,
        priority: effectivePriority,
        projectId: effectiveProjectId,
        reminderMinutes: effectiveReminder,
        recurrence: parsed.recurrence ?? _recurrence,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }
}

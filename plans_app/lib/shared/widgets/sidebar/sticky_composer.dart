import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_animations.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../../features/tasks/models/task.dart';
import '../../../features/tasks/providers/task_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../app_chip.dart';
import '../../helpers/recurrence.dart';
import '../../helpers/task_helpers.dart';
import '../../helpers/task_parser.dart';
import '../highlighted_task_controller.dart';

class StickyComposer extends ConsumerStatefulWidget {
  const StickyComposer({super.key});

  @override
  ConsumerState<StickyComposer> createState() => _StickyComposerState();
}

class _StickyComposerState extends ConsumerState<StickyComposer> {
  final _titleController = HighlightedTaskController();
  final _descriptionController = TextEditingController();
  late final FocusNode _focusNode;
  final _priorityKey = GlobalKey();
  final _projectKey = GlobalKey();
  final _reminderKey = GlobalKey();

  bool _isHovered = false;
  bool _hasText = false;
  bool _isExpanded = false;

  TaskPriority _priority = TaskPriority.none;
  DateTime? _dueDate;
  int _localProjectIndex = 0;
  int? _reminderMinutes;
  String? _recurrence;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTextChanged);
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _collapse();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _focusNode.addListener(_onFocusChanged);
  }

  void _onTextChanged() {
    final hasText = _titleController.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _syncProjectToSelection();
      setState(() => _isExpanded = true);
    }
  }

  void _requestFocus() {
    _focusNode.requestFocus();
  }

  void _syncProjectToSelection() {
    final selection = ref.read(sidebarSelectionProvider);
    final projects = ref.read(projectsProvider);
    if (projects.isEmpty) return;
    if (selection is ProjectSelection) {
      final idx = projects.indexWhere((p) => p.id == selection.projectId);
      if (idx >= 0) _localProjectIndex = idx;
    } else if (selection is ViewSelection &&
        selection.view == ViewType.inbox) {
      final idx = projects.indexWhere((p) => p.id == 'default');
      if (idx >= 0) _localProjectIndex = idx;
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTextChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _titleController.text.trim();
    if (raw.isEmpty) return;
    final desc = _descriptionController.text.trim();
    final projects = ref.read(projectsProvider);

    final parsed = TaskParser.parse(raw, projects);
    final effectiveTitle = parsed.title.isNotEmpty ? parsed.title : raw;
    final effectivePriority = parsed.priority ?? _priority;
    final effectiveProjectId = parsed.projectId ??
        (projects.isNotEmpty
            ? projects[_localProjectIndex % projects.length].id
            : 'default');
    final effectiveDueDate = parsed.dueDate ?? _dueDate;
    final effectiveReminder = parsed.hasDueDate && _reminderMinutes == null
        ? parsed.defaultReminderMinutes
        : _reminderMinutes;

    ref.read(tasksProvider.notifier).addTask(
          title: effectiveTitle,
          description: desc.isNotEmpty ? desc : null,
          dueDate: effectiveDueDate,
          priority: effectivePriority,
          projectId: effectiveProjectId,
          reminderMinutes: effectiveReminder,
          recurrence: parsed.recurrence ?? _recurrence,
        );
    _titleController.clear();
    _descriptionController.clear();
    setState(() {
      _priority = TaskPriority.none;
      _dueDate = null;
      _reminderMinutes = null;
      _recurrence = null;
      _isExpanded = false;
    });
    _focusNode.unfocus();
  }

  void _collapse() {
    _titleController.clear();
    _descriptionController.clear();
    setState(() {
      _priority = TaskPriority.none;
      _dueDate = null;
      _reminderMinutes = null;
      _isExpanded = false;
    });
    _focusNode.unfocus();
  }

  static const _reminderNone = -1;

  String get _reminderLabel => switch (_reminderMinutes) {
        null => 'Remind',
        0 => 'At due time',
        5 => '5 min before',
        15 => '15 min before',
        30 => '30 min before',
        60 => '1 hr before',
        _ => '$_reminderMinutes min before',
      };

  void _showReminderMenu() async {
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
                color: current == options[i] ? AppColors.accent : AppColors.textPrimary,
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

  void _showPriorityMenu() async {
    final picked = await showPriorityMenu(context, _priorityKey);
    if (picked != null) setState(() => _priority = picked);
  }

  void _showProjectMenu() async {
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

  void _showRecurrenceMenu() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final result = await showMenu<String>(
      context: context,
      color: AppColors.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
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

  @override
  Widget build(BuildContext context) {
    ref.listen(composerFocusRequestProvider, (prev, _) => _requestFocus());

    final isExpanded = _isExpanded;
    final projects = ref.watch(projectsProvider);
    final currentProjectName = projects.isNotEmpty
        ? projects[_localProjectIndex % projects.length].name
        : 'Inbox';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: AppAnimations.normal,
          curve: AppAnimations.easeOut,
          decoration: BoxDecoration(
            color: isExpanded || _isHovered
                ? AppColors.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isExpanded || _isHovered
                  ? AppColors.border
                  : AppColors.border.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Input row
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: AppSpacing.md),
                    Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: _priority != TaskPriority.none
                            ? switch (_priority) {
                                TaskPriority.critical => AppColors.priorityCritical,
                                TaskPriority.high => AppColors.priorityHigh,
                                TaskPriority.medium => AppColors.priorityMedium,
                                TaskPriority.low => AppColors.priorityLow,
                                TaskPriority.none => AppColors.textMuted,
                              }
                          : isExpanded || _isHovered
                              ? AppColors.accent
                              : AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        focusNode: _focusNode,
                        onSubmitted: (_) => _submit(),
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add a task...',
                          hintStyle: AppTypography.bodyMedium.copyWith(
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
                    if (_hasText)
                      IconButton(
                        onPressed: _submit,
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          size: 16,
                          color: AppColors.accent,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ),
              ),

              // Expandable description + options
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chips row
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
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
                            label: currentProjectName,
                            onTap: _showProjectMenu,
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
                      // Description field
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
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
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            isDense: true,
                          ),
                          maxLines: 20,
                          minLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: AppAnimations.normal,
                reverseDuration: AppAnimations.fast,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

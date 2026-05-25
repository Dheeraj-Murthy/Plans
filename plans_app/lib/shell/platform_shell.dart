import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/tasks/screens/task_list_screen.dart';
import '../features/tasks/widgets/add_task_sheet.dart';
import '../features/projects/widgets/slim_sidebar.dart';
import '../features/projects/providers/project_provider.dart';
import '../features/tasks/providers/task_provider.dart';
import '../shared/widgets/sidebar/sidebar_item.dart';
import '../shared/widgets/sidebar/sidebar_section_header.dart';
import '../shared/widgets/sidebar/add_project_button.dart';
import '../shared/helpers/task_helpers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'package:go_router/go_router.dart';
import '../main.dart' show widgetIntentProvider;
import '../shared/sync/sync_service.dart';
import '../shared/sync/sync_indicator.dart';
import '../shared/widgets/app_toast.dart';

class PlatformAdaptiveShell extends ConsumerStatefulWidget {
  const PlatformAdaptiveShell({super.key});

  @override
  ConsumerState<PlatformAdaptiveShell> createState() =>
      _PlatformAdaptiveShellState();
}

class _PlatformAdaptiveShellState
    extends ConsumerState<PlatformAdaptiveShell> with WidgetsBindingObserver {
  static const _deeplinkChannel = MethodChannel('plans/widget/deeplink');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(syncServiceProvider); // trigger lazy init (silent auth + check)
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
    if (!kIsWeb && Platform.isAndroid) {
      _deeplinkChannel.setMethodCallHandler(_handleNativeCall);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingWidgetSync();
      final intent = ref.read(widgetIntentProvider);
      if (intent?['action'] == 'add_task') {
        _openAddTask();
      } else if (intent?['action'] == 'open_task') {
        final taskId = intent?['task_id'];
        if (taskId != null && taskId.isNotEmpty) {
          _openTask(taskId);
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider.notifier).checkForUpdates();
      _checkPendingWidgetSync();
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'openAddTask') {
      _openAddTask();
    } else if (call.method == 'openTask') {
      final taskId = call.arguments as String?;
      if (taskId != null && taskId.isNotEmpty) {
        _openTask(taskId);
      }
    }
  }

  Future<void> _checkPendingWidgetSync() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      const channel = MethodChannel('plans/widget/deeplink');
      final pendingIds = (await channel.invokeMethod<List<dynamic>>('checkPendingWidgetSync')) ?? [];
      if (pendingIds.isNotEmpty) {
        ref.invalidate(tasksProvider);
        ref.read(syncServiceProvider.notifier).markDirty();
        ref.invalidate(projectsProvider);
      }
    } catch (e, st) {
      debugPrint('_checkPendingWidgetSync failed: $e\n$st');
    }
  }

  void _openAddTask() {
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    if (isDesktop) {
      ref.read(composerFocusRequestProvider.notifier).request();
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const AddTaskSheet(),
    );
  }

  void _openTask(String taskId) {
    final tasks = ref.read(tasksProvider);
    final task = tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;
    if (task.isCompleted) {
      ref
          .read(sidebarSelectionProvider.notifier)
          .select(const ViewSelection(ViewType.completed));
    } else {
      ref
          .read(sidebarSelectionProvider.notifier)
          .select(ProjectSelection(task.projectId));
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isModifier = Platform.isMacOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (!isModifier) return false;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyN:
        ref.read(composerFocusRequestProvider.notifier).request();
        return true;
      case LogicalKeyboardKey.keyK:
        ref.read(searchFocusRequestProvider.notifier).request();
        return true;
      case LogicalKeyboardKey.digit1:
        ref
            .read(sidebarSelectionProvider.notifier)
            .select(const ViewSelection(ViewType.inbox));
        return true;
      case LogicalKeyboardKey.digit2:
        ref
            .read(sidebarSelectionProvider.notifier)
            .select(const ViewSelection(ViewType.timeline));
        return true;
      case LogicalKeyboardKey.digit3:
        ref
            .read(sidebarSelectionProvider.notifier)
            .select(const ViewSelection(ViewType.completed));
        return true;
      case LogicalKeyboardKey.keyZ:
        final action = ref.read(undoStackProvider.notifier).pop();
        if (action != null) {
          switch (action) {
            case TaskDeleted(:final task):
              ref.read(tasksProvider.notifier).restoreTask(task);
            case TaskToggled(:final id):
              ref.read(tasksProvider.notifier).toggleTask(id);
          }
        }
        return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UndoAction?>(lastUndoActionProvider, (_, action) {
      if (action == null) return;
      final label = switch (action) {
        TaskDeleted() => 'Task deleted',
        TaskToggled() => 'Task completed',
      };
      showAppToast(
        context: context,
        message: label,
        actionLabel: 'Undo',
        onAction: () async {
          final undo = ref.read(undoStackProvider.notifier).pop();
          if (undo == null) return;
          switch (undo) {
            case TaskDeleted(:final task):
              await ref.read(tasksProvider.notifier).restoreTask(task);
            case TaskToggled(:final id):
              ref.read(tasksProvider.notifier).toggleTask(id);
          }
        },
      );
    });

    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    if (isDesktop) {
      return _DesktopShell();
    }
    return _MobileShell();
  }
}

class _DesktopShell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: const Row(
        children: [
          SlimSidebar(),
          Expanded(child: TaskListScreen()),
        ],
      ),
    );
  }
}

class _MobileShell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SidebarSelection selection = ref.watch(sidebarSelectionProvider);
    final projects = ref.watch(projectsProvider);
    // final completed =
    //     ref.watch(filteredTasksProvider).where((t) => t.isCompleted).toList();

    final title = switch (selection) {
      ViewSelection(:final view) => switch (view) {
          ViewType.inbox => 'Inbox',
          ViewType.timeline => 'Timeline',
          ViewType.today => 'Today',
          ViewType.completed => 'Completed',
        },
      ProjectSelection(:final projectId) =>
        projects.where((p) => p.id == projectId).firstOrNull?.name ?? 'Tasks',
    };

    final navIndex = switch (selection) {
      ViewSelection(view: ViewType.inbox) => 0,
      ViewSelection(view: ViewType.timeline) => 1,
      ViewSelection(view: ViewType.completed) => 2,
      _ => 0,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(title, style: AppTypography.headingMedium),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(
              Icons.menu_rounded,
              color: AppColors.textSecondary,
            ),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => context.push('/sync'),
              child: const SyncIndicator(),
            ),
          ),
        ],
      ),
      drawer: _MobileDrawer(),
      body: const TaskListScreen(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.surface,
          builder: (_) => const AddTaskSheet(),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navIndex,
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: AppTypography.caption,
        unselectedLabelStyle: AppTypography.caption,
        onTap: (index) {
          switch (index) {
            case 0:
              ref
                  .read(sidebarSelectionProvider.notifier)
                  .select(const ViewSelection(ViewType.inbox));
            case 1:
              ref
                  .read(sidebarSelectionProvider.notifier)
                  .select(const ViewSelection(ViewType.timeline));
            case 2:
              ref
                  .read(sidebarSelectionProvider.notifier)
                  .select(const ViewSelection(ViewType.completed));
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.inbox_rounded),
            label: 'Inbox',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Timeline',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline_rounded),
            label: 'Done',
          ),
        ],
      ),
    );
  }
}

class _MobileDrawer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final SidebarSelection selection = ref.watch(sidebarSelectionProvider);
    final totalTasks =
        ref.watch(tasksProvider).where((t) => !t.isCompleted).length;
    final timelineCount = ref.watch(timelineCountProvider);
    final completedCount = ref.watch(completedCountProvider);

    void close() => Navigator.of(context).pop();

    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                'Plans',
                style: AppTypography.headingLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            SidebarItem(
              icon: Icons.inbox_rounded,
              label: 'Inbox',
              count: totalTasks,
              isActive: selection is ViewSelection &&
                  selection.view == ViewType.inbox,
              onTap: () {
                ref
                    .read(sidebarSelectionProvider.notifier)
                    .select(const ViewSelection(ViewType.inbox));
                close();
              },
            ),
            SidebarItem(
              icon: Icons.calendar_month_rounded,
              label: 'Timeline',
              count: timelineCount,
              isActive: selection is ViewSelection &&
                  selection.view == ViewType.timeline,
              onTap: () {
                ref
                    .read(sidebarSelectionProvider.notifier)
                    .select(const ViewSelection(ViewType.timeline));
                close();
              },
            ),
            SidebarItem(
              icon: Icons.check_circle_outline_rounded,
              label: 'Completed',
              count: completedCount,
              isActive: selection is ViewSelection &&
                  selection.view == ViewType.completed,
              onTap: () {
                ref
                    .read(sidebarSelectionProvider.notifier)
                    .select(const ViewSelection(ViewType.completed));
                close();
              },
            ),
            const SidebarSectionHeader(label: 'Projects'),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  final count =
                      ref.watch(projectTaskCountProvider(project.id));
                  return SidebarItem(
                    icon: projectIcon(project.name),
                    label: project.name,
                    projectId: project.id,
                    colorIndex: project.colorIndex,
                    count: count > 0 ? count : null,
                    isActive: selection is ProjectSelection &&
                        selection.projectId == project.id,
                    onTap: () {
                      ref
                          .read(sidebarSelectionProvider.notifier)
                          .select(ProjectSelection(project.id));
                      close();
                    },
                  );
                },
              ),
            ),
            const AddProjectButton(),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

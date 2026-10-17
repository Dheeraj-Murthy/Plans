import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/task_provider.dart';
import '../../../shared/widgets/widget_bridge.dart';
import 'add_task_sheet.dart';

/// Root widget for the homescreen widget's "Add task" entrypoint
/// (QuickAddActivity on Android). Shows only the composer as a bottom
/// sheet over the live homescreen — the full shell/task list never gets
/// built, so this never looks like "opening the app".
class QuickAddApp extends StatelessWidget {
  const QuickAddApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: const _QuickAddHost(),
    );
  }
}

class _QuickAddHost extends ConsumerStatefulWidget {
  const _QuickAddHost();

  @override
  ConsumerState<_QuickAddHost> createState() => _QuickAddHostState();
}

class _QuickAddHostState extends ConsumerState<_QuickAddHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const AddTaskSheet(),
    );
    // Sheet closed — either the task was saved or the user dismissed it.
    // The normal widget-refresh path is 2s-debounced (TasksNotifier's
    // _debouncedWidgetUpdate), which never gets a chance to fire before
    // this activity finishes below — flush it directly so the homescreen
    // widget actually shows the new task, not stale data until the next
    // unrelated refresh.
    await WidgetBridge.notifyUpdate(
      allTasks: ref.read(tasksProvider),
      allProjects: ref.read(projectsProvider),
    );
    // There's nothing else to show in this activity, so hand control
    // straight back to the homescreen instead of leaving an empty window.
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Colors.transparent);
  }
}

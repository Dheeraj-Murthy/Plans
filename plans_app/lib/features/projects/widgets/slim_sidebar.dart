import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/project_provider.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';
import '../../../shared/widgets/sidebar/sidebar_item.dart';
import '../../../shared/widgets/sidebar/sidebar_section_header.dart';
import '../../../shared/widgets/sidebar/sidebar_search.dart';
import '../../../shared/widgets/sidebar/add_project_button.dart';
import '../../../shared/sync/sync_indicator.dart';
import '../../tasks/providers/task_provider.dart';
import '../../../shared/helpers/task_helpers.dart';

class SlimSidebar extends ConsumerWidget {
  const SlimSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final selection = ref.watch(sidebarSelectionProvider);

    final inboxCount = ref.watch(inboxCountProvider);
    final timelineCount = ref.watch(timelineCountProvider);
    final completedCount = ref.watch(completedCountProvider);

    return Container(
      width: AppSpacing.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          const _SidebarHeader(),

          // Search
          const SidebarSearch(),

          const SizedBox(height: AppSpacing.sm),

          // Smart lists
          SidebarItem(
            icon: Icons.inbox_rounded,
            label: 'Inbox',
            count: inboxCount,
            isActive: selection is ViewSelection &&
                selection.view == ViewType.inbox,
            onTap: () => ref
                .read(sidebarSelectionProvider.notifier)
                .select(const ViewSelection(ViewType.inbox)),
          ),
          SidebarItem(
            icon: Icons.calendar_month_rounded,
            label: 'Timeline',
            count: timelineCount,
            isActive: selection is ViewSelection &&
                selection.view == ViewType.timeline,
            onTap: () => ref
                .read(sidebarSelectionProvider.notifier)
                .select(const ViewSelection(ViewType.timeline)),
          ),
          SidebarItem(
            icon: Icons.check_circle_outline_rounded,
            label: 'Completed',
            count: completedCount,
            isActive: selection is ViewSelection &&
                selection.view == ViewType.completed,
            onTap: () => ref
                .read(sidebarSelectionProvider.notifier)
                .select(const ViewSelection(ViewType.completed)),
          ),

          // Projects section
          const SidebarSectionHeader(label: 'Projects'),

          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                final count = ref.watch(projectTaskCountProvider(project.id));
                return SidebarItem(
                  icon: projectIcon(project.name),
                  label: project.name,
                  projectId: project.id,
                  colorIndex: project.colorIndex,
                  count: count > 0 ? count : null,
                  isActive: selection is ProjectSelection &&
                      selection.projectId == project.id,
                  onTap: () => ref
                      .read(sidebarSelectionProvider.notifier)
                      .select(ProjectSelection(project.id)),
                );
              },
            ),
          ),

          // Add project button
          const AddProjectButton(),

          // Sync
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sidebarPadding,
              vertical: AppSpacing.sm,
            ),
            child: GestureDetector(
              onTap: () => context.push('/sync'),
              child: const Row(
                children: [
                  SyncIndicator(),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    'Sync',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sidebarPadding,
        AppSpacing.xl,
        AppSpacing.sidebarPadding,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            'Plans',
            style: AppTypography.headingLarge.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

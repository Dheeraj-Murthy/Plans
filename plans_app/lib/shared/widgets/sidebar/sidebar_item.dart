import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../../../theme/app_animations.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

class SidebarItem extends ConsumerStatefulWidget {
  final IconData icon;
  final String label;
  final String? projectId;
  final int? colorIndex;
  final int? count;
  final bool isActive;
  final VoidCallback? onTap;

  const SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    this.projectId,
    this.colorIndex,
    this.count,
    this.isActive = false,
    this.onTap,
  });

  @override
  ConsumerState<SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends ConsumerState<SidebarItem> {
  bool _isHovered = false;

  void _showColorPicker(Offset position) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        return Stack(
          children: [
            GestureDetector(
              onTap: () => entry.remove(),
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
            Positioned(
              left: position.dx,
              top: position.dy,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.elevated,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Color', style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (i) {
                          final isSelected = widget.colorIndex == i;
                          return GestureDetector(
                            onTap: () {
                              if (widget.projectId != null) {
                                ref.read(projectsProvider.notifier).updateProject(
                                  widget.projectId!,
                                  name: widget.label,
                                  colorIndex: i,
                                );
                              }
                              entry.remove();
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: AppColors.projectColors[i],
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: Colors.white, width: 2)
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final resolvedColor = widget.colorIndex != null
        ? AppColors.projectColors[widget.colorIndex! % AppColors.projectColors.length]
        : AppColors.accent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (details) {
          if (widget.projectId != null && widget.colorIndex != null) {
            _showColorPicker(details.globalPosition);
          }
        },
        child: AnimatedContainer(
          duration: AppAnimations.normal,
          curve: AppAnimations.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sidebarPadding),
          height: AppSpacing.sidebarItemHeight,
          decoration: BoxDecoration(
            color: widget.isActive
                ? resolvedColor.withValues(alpha: 0.12)
                : _isHovered
                    ? AppColors.surface
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: resolvedColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.label,
                  style: widget.isActive
                      ? AppTypography.sidebarActive
                      : AppTypography.sidebarItem,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.count != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: AppTypography.sidebarCount,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

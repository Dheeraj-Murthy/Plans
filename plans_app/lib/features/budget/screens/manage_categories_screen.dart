import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense_category.dart';
import '../providers/expense_category_provider.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

/// Full-screen category CRUD list — mirrors AddProjectButton's name+swatch
/// dialog for create/edit, but as a dedicated list (not a sidebar popover)
/// since there's no desktop-style right-click equivalent on mobile.
class ManageCategoriesScreen extends ConsumerWidget {
  const ManageCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(expenseCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Manage categories', style: AppTypography.headingMedium),
      ),
      body: ListView(
        children: [
          for (final category in categories)
            _CategoryRow(category: category),
          _AddCategoryRow(onTap: () => _showCategoryDialog(context, ref)),
        ],
      ),
    );
  }

  static Future<void> _showCategoryDialog(
    BuildContext context,
    WidgetRef ref, {
    ExpenseCategory? existing,
  }) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    var selectedColor = existing?.colorIndex ??
        ref.read(expenseCategoriesProvider).length % AppColors.projectColors.length;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            controller.addListener(() => setDialogState(() {}));
            final name = controller.text.trim();
            final canSave = name.isNotEmpty;

            void submit() {
              if (!canSave) return;
              if (existing != null) {
                ref.read(expenseCategoriesProvider.notifier).updateCategory(
                      existing.id,
                      name: name,
                      colorIndex: selectedColor,
                    );
              } else {
                ref.read(expenseCategoriesProvider.notifier).addCategory(
                      name,
                      colorIndex: selectedColor,
                    );
              }
              Navigator.of(ctx).pop();
            }

            return AlertDialog(
              backgroundColor: AppColors.elevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              title: Text(
                existing != null ? 'Edit category' : 'New category',
                style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onSubmitted: (_) => submit(),
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Category name',
                      hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.accent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(AppColors.projectColors.length, (i) {
                      final isSelected = selectedColor == i;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = i),
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: AppColors.projectColors[i],
                            shape: BoxShape.circle,
                            border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : null,
                        ),
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
                ),
                TextButton(
                  onPressed: canSave ? submit : null,
                  child: Text(
                    existing != null ? 'Save' : 'Create',
                    style: AppTypography.bodySmall.copyWith(
                      color: canSave ? AppColors.accent : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CategoryRow extends ConsumerWidget {
  final ExpenseCategory category;
  const _CategoryRow({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = AppColors.projectColors[category.colorIndex % AppColors.projectColors.length];

    return ListTile(
      onTap: () => ManageCategoriesScreen._showCategoryDialog(context, ref, existing: category),
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(category.name, style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary)),
      trailing: category.isOther
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
              onPressed: () => _confirmDelete(context, ref),
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Delete "${category.name}"?',
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Expenses in this category will move to "Other".',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: AppTypography.bodySmall.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(expenseCategoriesProvider.notifier).deleteCategory(category.id);
    }
  }
}

class _AddCategoryRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCategoryRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.add_rounded, size: 18, color: AppColors.textMuted),
      title: Text('Add category', style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted)),
    );
  }
}

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/budget_settings_provider.dart';
import '../providers/budget_transaction_provider.dart';
import '../providers/expense_category_provider.dart';
import '../widgets/budget_hero.dart';
import '../widgets/spending_donut_chart.dart';
import '../widgets/spending_trend_chart.dart';
import '../widgets/transaction_tile.dart';
import 'manage_categories_screen.dart';
import '../../../shared/helpers/currency.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

/// Budget tab content. No Scaffold/AppBar of its own — it's embedded inside
/// the shell's own Scaffold on mobile (same pattern TaskListScreen uses) and
/// inside the desktop Row next to SlimSidebar, with its own inline heading
/// only on desktop (SlimSidebar has no top app bar to supply one).
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(budgetSettingsProvider);
    final balance = ref.watch(currentBalanceProvider);
    final totalAdded = ref.watch(totalAddedProvider);
    final totalSpent = ref.watch(totalSpentProvider);
    final spendByCategory = ref.watch(spendByCategoryProvider);
    final spendByDay = ref.watch(spendByDayProvider);
    final categories = ref.watch(expenseCategoriesProvider);
    final transactions = ref.watch(currentCycleTransactionsProvider);
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

    return Column(
      children: [
        if (isDesktop)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Budget', style: AppTypography.headingLarge),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => showBudgetSettingsSheet(context, ref),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              BudgetHero(
                balance: balance,
                currencySymbol: settings.currencySymbol,
                resetAt: settings.resetAt,
              ),
              _StatRow(
                addedLabel: formatCurrency(totalAdded, settings.currencySymbol),
                spentLabel: formatCurrency(totalSpent, settings.currencySymbol),
              ),
              if (spendByCategory.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: SpendingDonutChart(
                    spendByCategory: spendByCategory,
                    categories: categories,
                    currencySymbol: settings.currencySymbol,
                  ),
                ),
              ],
              if (spendByDay.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: SpendingTrendChart(spendByDay: spendByDay),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(
                    child: Text(
                      'No transactions yet',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text(
                    'Recent',
                    style: AppTypography.overline.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final transaction in transactions)
                  TransactionTile(
                    transaction: transaction,
                    category: transaction.categoryId == null
                        ? null
                        : categories
                              .where((c) => c.id == transaction.categoryId)
                              .firstOrNull,
                    currencySymbol: settings.currencySymbol,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

void showBudgetSettingsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => _BudgetSettingsSheet(parentContext: context),
  );
}

class _StatRow extends StatelessWidget {
  final String addedLabel;
  final String spentLabel;

  const _StatRow({required this.addedLabel, required this.spentLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              label: 'Added',
              value: addedLabel,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatChip(
              label: 'Spent',
              value: spentLabel,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetSettingsSheet extends ConsumerStatefulWidget {
  final BuildContext parentContext;
  const _BudgetSettingsSheet({required this.parentContext});

  @override
  ConsumerState<_BudgetSettingsSheet> createState() =>
      _BudgetSettingsSheetState();
}

class _BudgetSettingsSheetState extends ConsumerState<_BudgetSettingsSheet> {
  late final TextEditingController _symbolController;

  @override
  void initState() {
    super.initState();
    _symbolController = TextEditingController(
      text: ref.read(budgetSettingsProvider).currencySymbol,
    );
  }

  @override
  void dispose() {
    _symbolController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _symbolController,
                    maxLength: 3,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Currency symbol',
                      labelStyle: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onSubmitted: (value) {
                      final symbol = value.trim();
                      if (symbol.isNotEmpty) {
                        ref
                            .read(budgetSettingsProvider.notifier)
                            .setCurrencySymbol(symbol);
                      }
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: () {
                    final symbol = _symbolController.text.trim();
                    if (symbol.isNotEmpty) {
                      ref
                          .read(budgetSettingsProvider.notifier)
                          .setCurrencySymbol(symbol);
                    }
                  },
                  child: Text(
                    'Save',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.category_outlined,
                color: AppColors.textSecondary,
              ),
              title: Text(
                'Manage categories',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(widget.parentContext).push(
                  MaterialPageRoute(
                    builder: (_) => const ManageCategoriesScreen(),
                  ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.restart_alt_rounded,
                color: AppColors.danger,
              ),
              title: Text(
                'Reset budget',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.danger,
                ),
              ),
              subtitle: Text(
                'Starts a fresh balance. History isn\'t deleted.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              onTap: () => _confirmReset(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext sheetContext) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Reset budget?',
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'This starts a fresh balance from zero. Past transactions and charts stay in history.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Reset',
              style: AppTypography.bodySmall.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(budgetSettingsProvider.notifier).reset();
      if (mounted) Navigator.of(context).pop();
    }
  }
}

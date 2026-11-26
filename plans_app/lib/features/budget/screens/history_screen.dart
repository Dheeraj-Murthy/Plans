import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../helpers/transaction_history.dart';
import '../providers/budget_settings_provider.dart';
import '../providers/budget_transaction_provider.dart';
import '../providers/expense_category_provider.dart';
import '../widgets/transaction_tile.dart';
import '../../../shared/helpers/currency.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _monthLabel(DateTime month) => '${_monthNames[month.month - 1]} ${month.year}';

/// Full transaction history, grouped by month (newest first). Watches the
/// raw transactions provider, not the current-cycle one, so a soft reset
/// never hides anything here.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(budgetTransactionsProvider);
    final categories = ref.watch(expenseCategoriesProvider);
    final currencySymbol = ref.watch(budgetSettingsProvider).currencySymbol;
    final groups = filterByMonth(transactions);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('History', style: AppTypography.headingMedium),
        // TODO: search action (filter by note / category / amount).
      ),
      body: groups.isEmpty
          ? Center(
              child: Text(
                'No transactions yet',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                for (final entry in groups.entries) ...[
                  _MonthHeader(
                    label: _monthLabel(entry.key),
                    totalSpent: formatCurrency(entry.value.total, currencySymbol),
                    // TODO: open the per-month analytics screen.
                    onTap: () {},
                  ),
                  for (final transaction in entry.value.transactionList)
                    TransactionTile(
                      transaction: transaction,
                      category: transaction.categoryId == null
                          ? null
                          : categories
                              .where((c) => c.id == transaction.categoryId)
                              .firstOrNull,
                      currencySymbol: currencySymbol,
                    ),
                ],
              ],
            ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final String label;
  final String totalSpent;
  final VoidCallback onTap;

  const _MonthHeader({
    required this.label,
    required this.totalSpent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.elevated,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Total Spent',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  totalSpent,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.accentHover,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

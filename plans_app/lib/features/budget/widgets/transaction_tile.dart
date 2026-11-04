import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/budget_transaction.dart';
import '../models/expense_category.dart';
import '../providers/budget_transaction_provider.dart';
import '../widgets/add_transaction_sheet.dart';
import '../../../shared/helpers/currency.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

class TransactionTile extends ConsumerWidget {
  final BudgetTransaction transaction;
  final ExpenseCategory? category;
  final String currencySymbol;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.category,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTopup = transaction.isTopup;
    final dotColor = isTopup
        ? AppColors.success
        : AppColors.projectColors[(category?.colorIndex ?? 0) % AppColors.projectColors.length];
    final title = transaction.note?.isNotEmpty == true
        ? transaction.note!
        : isTopup
            ? 'Added'
            : category?.name ?? 'Other';
    final amountText = '${isTopup ? '+' : '−'}${formatCurrency(transaction.amount, currencySymbol)}';

    return Dismissible(
      key: ValueKey(transaction.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) =>
          ref.read(budgetTransactionsProvider.notifier).deleteTransaction(transaction.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        color: AppColors.danger.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
      ),
      child: GestureDetector(
        onTap: () => _openEdit(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                amountText,
                style: AppTypography.bodyMedium.copyWith(
                  color: isTopup ? AppColors.success : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => AddTransactionSheet(initialType: transaction.type),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          transaction.isTopup ? 'Delete this top-up?' : 'Delete this expense?',
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
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
    return result ?? false;
  }
}

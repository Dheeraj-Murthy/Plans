import 'package:flutter/material.dart';
import '../../../shared/helpers/currency.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

/// The big "what's left" number — the focal point of the Budget tab.
class BudgetHero extends StatelessWidget {
  final double balance;
  final String currencySymbol;
  final DateTime resetAt;

  const BudgetHero({
    super.key,
    required this.balance,
    required this.currencySymbol,
    required this.resetAt,
  });

  @override
  Widget build(BuildContext context) {
    final isOver = balance < 0;
    final color = isOver ? AppColors.danger : AppColors.success;
    final sinceLabel = resetAt.millisecondsSinceEpoch == 0
        ? 'Since the beginning'
        : 'Since ${_formatDate(resetAt)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Text(
            formatCurrency(balance.abs(), currencySymbol),
            style: AppTypography.displayLarge.copyWith(color: color),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isOver ? 'over' : 'left',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            sinceLabel,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

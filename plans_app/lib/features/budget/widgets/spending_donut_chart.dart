import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/expense_category.dart';
import '../../../shared/helpers/currency.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

/// Spending-by-category donut with a color-dot legend underneath. Each
/// category's own colorIndex is used directly against AppColors.projectColors
/// — no second palette, same pattern the sidebar uses for projects.
class SpendingDonutChart extends StatelessWidget {
  final Map<String, double> spendByCategory;
  final List<ExpenseCategory> categories;
  final String currencySymbol;

  const SpendingDonutChart({
    super.key,
    required this.spendByCategory,
    required this.categories,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    if (spendByCategory.isEmpty) {
      return const SizedBox.shrink();
    }
    final total = spendByCategory.values.fold(0.0, (a, b) => a + b);
    final entries = spendByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Color colorFor(String categoryId) {
      final category = categories.where((c) => c.id == categoryId).firstOrNull;
      final index = category?.colorIndex ?? 0;
      return AppColors.projectColors[index % AppColors.projectColors.length];
    }

    String nameFor(String categoryId) {
      return categories.where((c) => c.id == categoryId).firstOrNull?.name ?? 'Other';
    }

    return Column(
      children: [
        SizedBox(
          height: 160,
          child: PieChart(
            PieChartData(
              sections: [
                for (final e in entries)
                  PieChartSectionData(
                    value: e.value,
                    color: colorFor(e.key),
                    radius: 28,
                    showTitle: false,
                  ),
              ],
              centerSpaceRadius: 48,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            for (final e in entries)
              _LegendEntry(
                color: colorFor(e.key),
                label: nameFor(e.key),
                amount: formatCurrency(e.value, currencySymbol),
                percent: total > 0 ? (e.value / total * 100).round() : 0,
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  final Color color;
  final String label;
  final String amount;
  final int percent;

  const _LegendEntry({
    required this.color,
    required this.label,
    required this.amount,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '$label · $amount ($percent%)',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

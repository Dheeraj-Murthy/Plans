import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// Daily spending bar trend for the current cycle. Shows at most the last 14
/// days with any spend so the chart stays legible for long-running cycles.
class SpendingTrendChart extends StatelessWidget {
  final Map<DateTime, double> spendByDay;

  const SpendingTrendChart({super.key, required this.spendByDay});

  @override
  Widget build(BuildContext context) {
    if (spendByDay.isEmpty) return const SizedBox.shrink();

    final days = spendByDay.keys.toList()..sort();
    final visibleDays = days.length > 14 ? days.sublist(days.length - 14) : days;
    final maxY = spendByDay.values.fold(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= visibleDays.length) return const SizedBox.shrink();
                  final day = visibleDays[idx];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${day.day}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < visibleDays.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: spendByDay[visibleDays[i]] ?? 0,
                    color: AppColors.accent,
                    width: 10,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

import '../models/budget_transaction.dart';

class MonthGroup {
  late List<BudgetTransaction> transactionList;
  double total = 0;
  MonthGroup(this.transactionList, this.total);
}

Map<DateTime, MonthGroup> filterByMonth(List<BudgetTransaction> list) {
  var copy = [...list]..sort((b, a) => a.occurredAt.compareTo(b.occurredAt));
  final grouped = <DateTime, List<BudgetTransaction>>{};
  for (final tx in copy) {
    final monthKey = DateTime(tx.occurredAt.year, tx.occurredAt.month);
    grouped.putIfAbsent(monthKey, () => []).add(tx);
  }
  final mpp = <DateTime, MonthGroup>{};
  for (final entry in grouped.entries) {
    final sum = entry.value.fold<double>(
      0,
      (acc, tx) => acc + (tx.isTopup ? 0 : tx.amount),
    );
    mpp[entry.key] = MonthGroup(entry.value, sum);
  }
  return mpp;
}

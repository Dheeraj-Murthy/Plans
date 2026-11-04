import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/budget_transaction.dart';
import 'budget_settings_provider.dart';
import '../../../shared/database/database_service.dart';
import '../../../shared/sync/sync_service.dart';
import '../../../shared/widgets/widget_bridge.dart';

final budgetTransactionsProvider =
    NotifierProvider<BudgetTransactionsNotifier, List<BudgetTransaction>>(
  BudgetTransactionsNotifier.new,
);

class BudgetTransactionsNotifier extends Notifier<List<BudgetTransaction>> {
  late DatabaseService _db;
  final Completer<void> _firstLoadCompleter = Completer<void>();

  // Callers that need `state` to actually reflect the DB before they mutate
  // it (e.g. the home-screen widget's quick-add, which cold-starts a fresh
  // engine) must await this first — same race TasksNotifier.addTask guards
  // against: build()'s _load() populates state asynchronously, so a mutation
  // racing ahead of it can get clobbered when _load() finally resolves and
  // overwrites state (and the widget cache) with pre-mutation data.
  Future<void> get firstLoad => _firstLoadCompleter.future;

  @override
  List<BudgetTransaction> build() {
    _db = ref.read(databaseServiceProvider);
    _load();
    return [];
  }

  void _load() {
    unawaited(
      _db.getBudgetTransactions().then((transactions) async {
        state = transactions;
        await _pushWidget();
      }).catchError((e) {
        debugPrint('BudgetTransactionsNotifier._load failed: $e');
      }).whenComplete(() {
        if (!_firstLoadCompleter.isCompleted) _firstLoadCompleter.complete();
      }),
    );
  }

  // Computes the balance locally from `state` + the settings notifier's raw
  // state, rather than going through currentBalanceProvider/
  // currentCycleTransactionsProvider — reading a derived provider that
  // transitively watches this same notifier, from inside this notifier's
  // own mutating method, trips Riverpod's circular-dependency guard even
  // though `state` is already up to date by the time this runs.
  Future<void> _pushWidget() {
    final settings = ref.read(budgetSettingsProvider);
    var balance = 0.0;
    for (final t in state) {
      if (t.occurredAt.isBefore(settings.resetAt)) continue;
      balance += t.isTopup ? t.amount : -t.amount;
    }
    return WidgetBridge.notifyBudgetUpdate(
      balance: balance,
      currencySymbol: settings.currencySymbol,
    );
  }

  Future<BudgetTransaction> addTransaction({
    required TransactionType type,
    required double amount,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
  }) async {
    await firstLoad;
    final transaction = await _db.insertBudgetTransaction(
      type: type,
      amount: amount,
      categoryId: categoryId,
      note: note,
      occurredAt: occurredAt,
    );
    ref.read(syncServiceProvider.notifier).markDirty();
    // Rust returns transactions newest-first; a freshly-inserted one belongs
    // at the front without waiting for a full reload.
    state = [transaction, ...state];
    await _pushWidget();
    return transaction;
  }

  // Full-replace, not a partial patch — categoryId/note are taken literally
  // (including null, to actually clear a note) rather than merged against
  // the existing row, since the one caller (the edit sheet) always has the
  // complete, up-to-date value for every field.
  Future<void> updateTransaction(
    String id, {
    required double amount,
    String? categoryId,
    String? note,
    required DateTime occurredAt,
  }) async {
    final idx = state.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = state[idx].copyWith(
      amount: amount,
      categoryId: categoryId,
      note: note,
      occurredAt: occurredAt,
      updatedAt: DateTime.now(),
    );
    await _db.updateBudgetTransaction(updated);
    ref.read(syncServiceProvider.notifier).markDirty();
    final list = [...state];
    list[idx] = updated;
    state = list;
    await _pushWidget();
  }

  Future<void> deleteTransaction(String id) async {
    await _db.deleteBudgetTransaction(id);
    ref.read(syncServiceProvider.notifier).markDirty();
    state = state.where((t) => t.id != id).toList();
    await _pushWidget();
  }

  // Called by ExpenseCategoriesNotifier.deleteCategory right after the DB
  // delete succeeds, mirroring reassignTasksFromDeletedProject — the Rust
  // side already reassigned these rows to 'other', this just mirrors that
  // in memory instead of waiting for a reload.
  void reassignTransactionsFromDeletedCategory(String categoryId) {
    state = state
        .map((t) => t.categoryId == categoryId ? t.copyWith(categoryId: 'other') : t)
        .toList();
  }
}

// Used by BudgetSettingsNotifier (BudgetTransactionsNotifier has its own
// private _pushWidget using `state` directly). Takes the raw transaction
// list and computes the balance locally rather than reading
// currentBalanceProvider — doing that from inside either notifier's own
// mutating method trips Riverpod's circular-dependency guard, since that
// derived provider transitively watches both of these notifiers.
Future<void> pushBudgetWidgetUpdate({
  required List<BudgetTransaction> transactions,
  required DateTime resetAt,
  required String currencySymbol,
}) {
  var balance = 0.0;
  for (final t in transactions) {
    if (t.occurredAt.isBefore(resetAt)) continue;
    balance += t.isTopup ? t.amount : -t.amount;
  }
  return WidgetBridge.notifyBudgetUpdate(
    balance: balance,
    currencySymbol: currencySymbol,
  );
}

// ── Derived providers ────────────────────────────────────────────────────

/// Transactions that count toward the current cycle (on/after the last reset).
final currentCycleTransactionsProvider =
    Provider<List<BudgetTransaction>>((ref) {
  final resetAt = ref.watch(budgetSettingsProvider).resetAt;
  final transactions = ref.watch(budgetTransactionsProvider);
  return transactions.where((t) => !t.occurredAt.isBefore(resetAt)).toList();
});

/// Running balance for the current cycle: top-ups minus expenses.
final currentBalanceProvider = Provider<double>((ref) {
  var balance = 0.0;
  for (final t in ref.watch(currentCycleTransactionsProvider)) {
    balance += t.isTopup ? t.amount : -t.amount;
  }
  return balance;
});

final totalAddedProvider = Provider<double>((ref) {
  return ref
      .watch(currentCycleTransactionsProvider)
      .where((t) => t.isTopup)
      .fold(0.0, (sum, t) => sum + t.amount);
});

final totalSpentProvider = Provider<double>((ref) {
  return ref
      .watch(currentCycleTransactionsProvider)
      .where((t) => t.isExpense)
      .fold(0.0, (sum, t) => sum + t.amount);
});

/// Spend grouped by category id, current cycle only — feeds the donut chart.
final spendByCategoryProvider = Provider<Map<String, double>>((ref) {
  final result = <String, double>{};
  for (final t in ref.watch(currentCycleTransactionsProvider)) {
    if (!t.isExpense) continue;
    final categoryId = t.categoryId ?? 'other';
    result[categoryId] = (result[categoryId] ?? 0) + t.amount;
  }
  return result;
});

/// Spend grouped by calendar day, current cycle only — feeds the trend chart.
final spendByDayProvider = Provider<Map<DateTime, double>>((ref) {
  final result = <DateTime, double>{};
  for (final t in ref.watch(currentCycleTransactionsProvider)) {
    if (!t.isExpense) continue;
    final day = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
    result[day] = (result[day] ?? 0) + t.amount;
  }
  return result;
});

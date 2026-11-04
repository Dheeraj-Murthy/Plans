import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/budget_settings.dart';
import 'budget_transaction_provider.dart';
import '../../../shared/database/database_service.dart';
import '../../../shared/sync/sync_service.dart';

final budgetSettingsProvider =
    NotifierProvider<BudgetSettingsNotifier, BudgetSettings>(
  BudgetSettingsNotifier.new,
);

class BudgetSettingsNotifier extends Notifier<BudgetSettings> {
  late DatabaseService _db;

  @override
  BudgetSettings build() {
    _db = ref.read(databaseServiceProvider);
    _load();
    return BudgetSettings();
  }

  void _load() {
    unawaited(
      _db.getBudgetSettings().then((settings) async {
        state = settings;
        await _pushWidget();
      }).catchError((e) {
        debugPrint('BudgetSettingsNotifier._load failed: $e');
      }),
    );
  }

  // Reads the raw budgetTransactionsProvider (not the derived
  // currentBalanceProvider, which also watches this notifier) and computes
  // locally — see pushBudgetWidgetUpdate's doc comment.
  Future<void> _pushWidget() {
    return pushBudgetWidgetUpdate(
      transactions: ref.read(budgetTransactionsProvider),
      resetAt: state.resetAt,
      currencySymbol: state.currencySymbol,
    );
  }

  Future<void> setCurrencySymbol(String symbol) async {
    final updated = await _db.updateBudgetSettings(currencySymbol: symbol);
    ref.read(syncServiceProvider.notifier).markDirty();
    state = updated;
    await _pushWidget();
  }

  // Moves the running-balance start point to now — history isn't deleted,
  // it just stops counting toward the balance/charts going forward.
  Future<void> reset() async {
    final resetAt = await _db.resetBudget();
    ref.read(syncServiceProvider.notifier).markDirty();
    state = state.copyWith(resetAt: resetAt, updatedAt: DateTime.now());
    await _pushWidget();
  }
}

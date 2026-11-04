import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense_category.dart';
import 'budget_transaction_provider.dart';
import '../../../shared/database/database_service.dart';
import '../../../shared/sync/sync_service.dart';

final expenseCategoriesProvider =
    NotifierProvider<ExpenseCategoriesNotifier, List<ExpenseCategory>>(
  ExpenseCategoriesNotifier.new,
);

class ExpenseCategoriesNotifier extends Notifier<List<ExpenseCategory>> {
  late DatabaseService _db;

  @override
  List<ExpenseCategory> build() {
    _db = ref.read(databaseServiceProvider);
    _load();
    return [];
  }

  void _load() {
    _db.getExpenseCategories().then((categories) {
      state = categories;
    }).catchError((e) {
      debugPrint('ExpenseCategoriesNotifier._load failed: $e');
    });
  }

  Future<void> addCategory(String name, {required int colorIndex}) async {
    final category = await _db.insertExpenseCategory(
      name: name,
      colorIndex: colorIndex,
    );
    ref.read(syncServiceProvider.notifier).markDirty();
    state = [...state, category];
  }

  Future<void> updateCategory(
    String id, {
    required String name,
    required int colorIndex,
  }) async {
    final idx = state.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final updated = state[idx].copyWith(
      name: name,
      colorIndex: colorIndex,
      updatedAt: DateTime.now(),
    );
    await _db.updateExpenseCategory(updated);
    ref.read(syncServiceProvider.notifier).markDirty();
    final list = [...state];
    list[idx] = updated;
    state = list;
  }

  // The "Other" category is the fallback every deleted category's expenses
  // get reassigned to (mirrors the 'default' Inbox project) — deleting it
  // would leave future deletes with nowhere to land, so it's blocked both
  // here and at the Rust layer.
  Future<void> deleteCategory(String id) async {
    if (id == 'other') return;
    await _db.deleteExpenseCategory(id);
    ref.read(syncServiceProvider.notifier).markDirty();
    ref
        .read(budgetTransactionsProvider.notifier)
        .reassignTransactionsFromDeletedCategory(id);
    state = state.where((c) => c.id != id).toList();
  }
}

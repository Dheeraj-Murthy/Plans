import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plans_app/features/budget/models/budget_transaction.dart';
import 'package:plans_app/features/budget/providers/budget_transaction_provider.dart';
import 'package:plans_app/features/budget/providers/budget_settings_provider.dart';
import 'package:plans_app/shared/database/database_service.dart';
import '../shared/fake_database_service.dart';

ProviderContainer createContainer(DatabaseService db) {
  return ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWithValue(db),
    ],
  );
}

Future<void> settle(ProviderContainer c) async {
  await Future(() {});
  await Future(() {});
}

void main() {
  group('BudgetTransactionsNotifier', () {
    test('starts empty', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      container.read(budgetTransactionsProvider);
      await settle(container);
      expect(container.read(budgetTransactionsProvider), isEmpty);
      container.dispose();
    });

    test('addTransaction adds a top-up with no category', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);

      await container.read(budgetTransactionsProvider.notifier).addTransaction(
            type: TransactionType.topup,
            amount: 1000,
            note: 'Salary',
          );

      final t = container.read(budgetTransactionsProvider).single;
      expect(t.isTopup, isTrue);
      expect(t.categoryId, isNull);
      expect(t.amount, 1000);
      container.dispose();
    });

    test('addTransaction defaults an expense to the other category', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);

      await container.read(budgetTransactionsProvider.notifier).addTransaction(
            type: TransactionType.expense,
            amount: 200,
          );

      final t = container.read(budgetTransactionsProvider).single;
      expect(t.categoryId, 'other');
      container.dispose();
    });

    test('updateTransaction can clear the note', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);

      await container.read(budgetTransactionsProvider.notifier).addTransaction(
            type: TransactionType.expense,
            amount: 200,
            note: 'Coffee',
          );
      final t = container.read(budgetTransactionsProvider).single;

      await container.read(budgetTransactionsProvider.notifier).updateTransaction(
            t.id,
            amount: t.amount,
            categoryId: t.categoryId,
            note: null,
            occurredAt: t.occurredAt,
          );

      expect(container.read(budgetTransactionsProvider).single.note, isNull);
      container.dispose();
    });

    test('deleteTransaction removes it', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);

      final t = await container.read(budgetTransactionsProvider.notifier).addTransaction(
            type: TransactionType.topup,
            amount: 500,
          );
      await container.read(budgetTransactionsProvider.notifier).deleteTransaction(t.id);

      expect(container.read(budgetTransactionsProvider), isEmpty);
      container.dispose();
    });

    test('currentBalance is top-ups minus expenses', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);
      final notifier = container.read(budgetTransactionsProvider.notifier);

      await notifier.addTransaction(type: TransactionType.topup, amount: 1000);
      await notifier.addTransaction(type: TransactionType.expense, amount: 300);
      await notifier.addTransaction(type: TransactionType.expense, amount: 150);

      expect(container.read(currentBalanceProvider), 550);
      expect(container.read(totalAddedProvider), 1000);
      expect(container.read(totalSpentProvider), 450);
      container.dispose();
    });

    test('resetting the budget excludes transactions before the reset point', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);
      final notifier = container.read(budgetTransactionsProvider.notifier);

      // Explicit past timestamp so this can't collide with reset_at's
      // DateTime.now() under coarse clock resolution in a fast test run.
      await notifier.addTransaction(
        type: TransactionType.topup,
        amount: 1000,
        occurredAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(container.read(currentBalanceProvider), 1000);

      await container.read(budgetSettingsProvider.notifier).reset();
      await settle(container);

      expect(container.read(currentBalanceProvider), 0);
      expect(container.read(budgetTransactionsProvider).length, 1,
          reason: 'reset must not delete history');

      await notifier.addTransaction(type: TransactionType.topup, amount: 200);
      expect(container.read(currentBalanceProvider), 200);
      container.dispose();
    });

    test('spendByCategory groups expenses, current cycle only', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);
      final notifier = container.read(budgetTransactionsProvider.notifier);

      await notifier.addTransaction(
        type: TransactionType.expense,
        amount: 100,
        categoryId: 'food',
      );
      await notifier.addTransaction(
        type: TransactionType.expense,
        amount: 50,
        categoryId: 'food',
      );
      await notifier.addTransaction(
        type: TransactionType.expense,
        amount: 75,
        categoryId: 'transport',
      );

      final byCategory = container.read(spendByCategoryProvider);
      expect(byCategory['food'], 150);
      expect(byCategory['transport'], 75);
      container.dispose();
    });
  });
}

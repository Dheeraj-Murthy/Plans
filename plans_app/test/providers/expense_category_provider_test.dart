import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plans_app/features/budget/models/expense_category.dart';
import 'package:plans_app/features/budget/models/budget_transaction.dart';
import 'package:plans_app/features/budget/providers/expense_category_provider.dart';
import 'package:plans_app/features/budget/providers/budget_transaction_provider.dart';
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
  group('ExpenseCategoriesNotifier', () {
    test('starts empty and loads from DB', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      container.read(expenseCategoriesProvider);
      await settle(container);
      expect(container.read(expenseCategoriesProvider), isEmpty);
      container.dispose();
    });

    test('addCategory adds a category', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);
      await container
          .read(expenseCategoriesProvider.notifier)
          .addCategory('Pets', colorIndex: 2);
      final categories = container.read(expenseCategoriesProvider);
      expect(categories.length, 1);
      expect(categories.first.name, 'Pets');
      expect(categories.first.colorIndex, 2);
      container.dispose();
    });

    test('updateCategory renames and recolors', () async {
      final db = FakeDatabaseService();
      final container = createContainer(db);
      await settle(container);
      await container
          .read(expenseCategoriesProvider.notifier)
          .addCategory('Pets', colorIndex: 2);
      final category = container.read(expenseCategoriesProvider).first;

      await container.read(expenseCategoriesProvider.notifier).updateCategory(
            category.id,
            name: 'Animals',
            colorIndex: 4,
          );

      final updated = container.read(expenseCategoriesProvider).first;
      expect(updated.name, 'Animals');
      expect(updated.colorIndex, 4);
      container.dispose();
    });

    test('other category cannot be deleted', () async {
      final db = FakeDatabaseService();
      db.seedExpenseCategory(ExpenseCategory(id: 'other', name: 'Other', colorIndex: 0));
      final container = createContainer(db);
      await settle(container);

      await container.read(expenseCategoriesProvider.notifier).deleteCategory('other');

      expect(container.read(expenseCategoriesProvider).any((c) => c.id == 'other'), isTrue);
      container.dispose();
    });

    test('deleting a category reassigns its transactions to other', () async {
      final db = FakeDatabaseService();
      db.seedExpenseCategory(ExpenseCategory(id: 'other', name: 'Other', colorIndex: 0));
      final container = createContainer(db);
      await settle(container);

      await container
          .read(expenseCategoriesProvider.notifier)
          .addCategory('Pets', colorIndex: 2);
      final pets = container
          .read(expenseCategoriesProvider)
          .firstWhere((c) => c.name == 'Pets');

      await container.read(budgetTransactionsProvider.notifier).addTransaction(
            type: TransactionType.expense,
            amount: 50,
            categoryId: pets.id,
          );

      await container.read(expenseCategoriesProvider.notifier).deleteCategory(pets.id);

      final transactions = container.read(budgetTransactionsProvider);
      expect(transactions.single.categoryId, 'other');
      expect(container.read(expenseCategoriesProvider).any((c) => c.id == pets.id), isFalse);
      container.dispose();
    });
  });
}

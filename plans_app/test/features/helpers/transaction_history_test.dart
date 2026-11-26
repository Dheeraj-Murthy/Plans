import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plans_app/features/budget/helpers/transaction_history.dart';
import 'package:plans_app/features/budget/models/budget_transaction.dart';
import 'package:plans_app/features/budget/providers/budget_transaction_provider.dart';
import 'package:plans_app/shared/database/database_service.dart';

import '../../providers/expense_category_provider_test.dart';
import '../../shared/fake_database_service.dart';


ProviderContainer createContainer(DatabaseService db) {
  return ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWithValue(db),
    ],
  );
}

void main() {
    test('testing transaction history', () async {
            final db = FakeDatabaseService();
            final container = createContainer(db);
            container.read(budgetTransactionsProvider);
            await settle(container);
            await container.read(budgetTransactionsProvider.notifier).addTransaction(type: TransactionType.topup, amount: 1000, note: 'salary', occurredAt: DateTime(2026, 10, 11));
            await container.read(budgetTransactionsProvider.notifier).addTransaction(type: TransactionType.expense, amount: 100, note: 'food', occurredAt: DateTime(2026, 10, 11));
            await container.read(budgetTransactionsProvider.notifier).addTransaction(type: TransactionType.expense, amount: 100, note: 'later', occurredAt: DateTime(2027, 10, 12));
            await container.read(budgetTransactionsProvider.notifier).addTransaction(type: TransactionType.expense, amount: 400, note: 'rent', occurredAt: DateTime(2026, 11, 11));

            
            List<BudgetTransaction>list = await db.getBudgetTransactions();
            var ans = filterByMonth(list);
            expect(ans.keys.toList(), [DateTime(2027, 10), DateTime(2026, 11), DateTime(2026, 10)]);
            expect(ans.length, 3);
            expect(ans[DateTime(2026, 10)]?.total, 100);
            expect(ans[DateTime(2026, 11)]?.total, 400);
        });
    }

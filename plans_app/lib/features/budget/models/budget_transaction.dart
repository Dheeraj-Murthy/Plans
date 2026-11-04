enum TransactionType { topup, expense }

const _absent = Object();

TransactionType transactionTypeFromString(String value) =>
    value == 'topup' ? TransactionType.topup : TransactionType.expense;

String transactionTypeToString(TransactionType type) =>
    type == TransactionType.topup ? 'topup' : 'expense';

class BudgetTransaction {
  final String id;
  final TransactionType type;
  final double amount;
  final String? categoryId;
  final String? note;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  BudgetTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.categoryId,
    this.note,
    DateTime? occurredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : occurredAt = occurredAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isTopup => type == TransactionType.topup;
  bool get isExpense => type == TransactionType.expense;

  BudgetTransaction copyWith({
    String? id,
    TransactionType? type,
    double? amount,
    Object? categoryId = _absent,
    Object? note = _absent,
    DateTime? occurredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BudgetTransaction(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId == _absent ? this.categoryId : categoryId as String?,
      note: note == _absent ? this.note : note as String?,
      occurredAt: occurredAt ?? this.occurredAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ExpenseCategory {
  final String id;
  final String name;
  final int colorIndex;
  final DateTime updatedAt;

  ExpenseCategory({
    required this.id,
    required this.name,
    this.colorIndex = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  bool get isOther => id == 'other';

  ExpenseCategory copyWith({
    String? id,
    String? name,
    int? colorIndex,
    DateTime? updatedAt,
  }) {
    return ExpenseCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      colorIndex: colorIndex ?? this.colorIndex,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

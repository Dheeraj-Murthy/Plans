class BudgetSettings {
  final DateTime resetAt;
  final String currencySymbol;
  final DateTime updatedAt;

  BudgetSettings({
    DateTime? resetAt,
    this.currencySymbol = '₹',
    DateTime? updatedAt,
  })  : resetAt = resetAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  BudgetSettings copyWith({
    DateTime? resetAt,
    String? currencySymbol,
    DateTime? updatedAt,
  }) {
    return BudgetSettings(
      resetAt: resetAt ?? this.resetAt,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

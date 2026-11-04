import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/budget_transaction.dart';
import '../models/expense_category.dart';
import '../providers/budget_transaction_provider.dart';
import '../providers/budget_settings_provider.dart';
import '../providers/expense_category_provider.dart';
import '../../../shared/helpers/task_helpers.dart' show pickDate, formatDueDateTime;
import '../../../theme/app_animations.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_typography.dart';

/// Add-expense / add-money sheet. Mirrors AddTaskSheet's bottom-sheet shape
/// (big input up top, chips below, single submit action) so the "few clicks
/// as possible" goal holds: type the amount, tap a category chip (expenses
/// only), tap submit.
class AddTransactionSheet extends ConsumerStatefulWidget {
  final TransactionType initialType;
  final BudgetTransaction? existingTransaction;

  const AddTransactionSheet({
    super.key,
    this.initialType = TransactionType.expense,
    this.existingTransaction,
  });

  @override
  ConsumerState<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  late TransactionType _type;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  final _amountFocusNode = FocusNode();
  String? _categoryId;
  late DateTime _occurredAt;

  bool get _isEditing => widget.existingTransaction != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTransaction;
    _type = existing?.type ?? widget.initialType;
    _amountController = TextEditingController(
      text: existing != null ? _trimTrailingZeros(existing.amount) : '',
    );
    _noteController = TextEditingController(text: existing?.note ?? '');
    _categoryId = existing?.categoryId;
    _occurredAt = existing?.occurredAt ?? DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _amountFocusNode.requestFocus();
    });
  }

  String _trimTrailingZeros(double amount) {
    var text = amount.toStringAsFixed(2);
    if (text.endsWith('.00')) text = text.substring(0, text.length - 3);
    return text;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  bool get _isExpense => _type == TransactionType.expense;

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(budgetSettingsProvider).currencySymbol;
    final categories = ref.watch(expenseCategoriesProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTypeToggle(),
            const SizedBox(height: AppSpacing.lg),
            _buildAmountField(currencySymbol),
            const SizedBox(height: AppSpacing.md),
            _buildNoteField(),
            const SizedBox(height: AppSpacing.md),
            if (_isExpense) ...[
              _buildCategoryChips(categories),
              const SizedBox(height: AppSpacing.md),
            ],
            _buildDateAndSubmitRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    return Row(
      children: [
        Expanded(
          child: _TypeToggleButton(
            label: 'Expense',
            icon: Icons.remove_circle_outline_rounded,
            isSelected: _isExpense,
            onTap: () => setState(() => _type = TransactionType.expense),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _TypeToggleButton(
            label: 'Add money',
            icon: Icons.add_circle_outline_rounded,
            isSelected: !_isExpense,
            onTap: () => setState(() => _type = TransactionType.topup),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountField(String currencySymbol) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          currencySymbol,
          style: AppTypography.displayLarge.copyWith(
            fontSize: 32,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: TextField(
            controller: _amountController,
            focusNode: _amountFocusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTypography.displayLarge.copyWith(
              fontSize: 32,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: AppTypography.displayLarge.copyWith(
                fontSize: 32,
                color: AppColors.textMuted,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.short_text_rounded, size: 20, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            controller: _noteController,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: _isExpense ? 'Where / what for' : 'Note (optional)',
              hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChips(List<ExpenseCategory> categories) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: AppSpacing.sm,
        children: [
          for (final category in categories)
            _CategoryChip(
              name: category.name,
              color: AppColors.projectColors[category.colorIndex % AppColors.projectColors.length],
              isSelected: (_categoryId ?? _defaultCategoryId(categories)) == category.id,
              onTap: () => setState(() => _categoryId = category.id),
            ),
        ],
      ),
    );
  }

  String? _defaultCategoryId(List<ExpenseCategory> categories) {
    if (categories.isEmpty) return null;
    return categories.first.id;
  }

  Widget _buildDateAndSubmitRow() {
    return Row(
      children: [
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  formatDueDateTime(_occurredAt),
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _submit,
          child: AnimatedContainer(
            duration: AppAnimations.fast,
            curve: AppAnimations.easeOut,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final date = await pickDate(context, _occurredAt);
    if (date != null) setState(() => _occurredAt = date);
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;
    final note = _noteController.text.trim();
    final categories = ref.read(expenseCategoriesProvider);
    final categoryId = _isExpense ? (_categoryId ?? _defaultCategoryId(categories)) : null;

    final notifier = ref.read(budgetTransactionsProvider.notifier);
    if (_isEditing) {
      await notifier.updateTransaction(
        widget.existingTransaction!.id,
        amount: amount,
        categoryId: categoryId,
        note: note.isNotEmpty ? note : null,
        occurredAt: _occurredAt,
      );
    } else {
      await notifier.addTransaction(
        type: _type,
        amount: amount,
        categoryId: categoryId,
        note: note.isNotEmpty ? note : null,
        occurredAt: _occurredAt,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }
}

class _TypeToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        curve: AppAnimations.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withValues(alpha: 0.12) : AppColors.surface,
          border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: isSelected ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String name;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.name,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : null,
          border: Border.all(color: isSelected ? color : AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: AppTypography.bodySmall.copyWith(
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

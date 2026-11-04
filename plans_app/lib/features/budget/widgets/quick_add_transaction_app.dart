import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../models/budget_transaction.dart';
import '../providers/budget_settings_provider.dart';
import '../providers/budget_transaction_provider.dart';
import '../../../shared/widgets/widget_bridge.dart';
import 'add_transaction_sheet.dart';

/// Root widget for the Budget home-screen widget's "+ Expense"/"+ Money"
/// buttons (QuickAddTransactionActivity on Android) — mirrors QuickAddApp's
/// shape exactly: show only the composer over the live homescreen, never
/// the full shell.
class QuickAddTransactionApp extends StatelessWidget {
  final TransactionType initialType;

  const QuickAddTransactionApp({super.key, required this.initialType});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: _QuickAddTransactionHost(initialType: initialType),
    );
  }
}

class _QuickAddTransactionHost extends ConsumerStatefulWidget {
  final TransactionType initialType;

  const _QuickAddTransactionHost({required this.initialType});

  @override
  ConsumerState<_QuickAddTransactionHost> createState() => _QuickAddTransactionHostState();
}

class _QuickAddTransactionHostState extends ConsumerState<_QuickAddTransactionHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => AddTransactionSheet(initialType: widget.initialType),
    );
    // Sheet closed — addTransaction() already flushed the widget cache on
    // save, but this covers the dismiss-without-save case too (harmless
    // no-op push) before handing control back to the homescreen, same
    // defensive-flush pattern QuickAddApp uses for tasks. WidgetRef doesn't
    // share a type with the Ref pushBudgetWidgetUpdate takes, so this reads
    // the same two values directly rather than forcing a shared signature.
    await WidgetBridge.notifyBudgetUpdate(
      balance: ref.read(currentBalanceProvider),
      currencySymbol: ref.read(budgetSettingsProvider).currencySymbol,
    );
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Colors.transparent);
  }
}

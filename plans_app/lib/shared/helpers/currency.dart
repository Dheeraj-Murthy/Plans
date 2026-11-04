/// Manual grouped-currency formatter — the app otherwise carries no `intl`
/// dependency, and this is the only formatting need (symbol-prefixed,
/// thousands-separated, 2dp), so a tiny helper keeps the dependency
/// footprint lean instead of pulling in locale-aware formatting machinery.
String formatCurrency(double amount, String symbol) {
  final isNegative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final decimals = parts[1];

  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }

  return '${isNegative ? '-' : ''}$symbol${buffer.toString()}.$decimals';
}

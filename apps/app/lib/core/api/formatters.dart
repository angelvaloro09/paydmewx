import 'package:intl/intl.dart';

final NumberFormat _mxnNumberFormat = NumberFormat('#,##0.00', 'en_US');

/// Formats integer centavos into MXN display currency, e.g. 123450 -> "$1,234.50".
String formatMxn(int cents) {
  final isNegative = cents < 0;
  final absPesos = cents.abs() / 100.0;
  final formatted = _mxnNumberFormat.format(absPesos);
  return isNegative ? '-\$$formatted' : '\$$formatted';
}

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _decimal = NumberFormat.decimalPattern('es_CL');

/// Live-formats a monetary text field: digits only, grouped by thousands
/// with dots, no decimals. The cursor always lands at the end — computing
/// its exact position under regrouping isn't worth the complexity for a
/// field typed left to right.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = _decimal.format(int.parse(digitsOnly));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String formatMoneyForDisplay(num value) => _decimal.format(value.round());

double parseMoneyInput(String text) {
  final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
  return digitsOnly.isEmpty ? 0 : double.parse(digitsOnly);
}

import 'package:billetera/core/money_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _tev(String text) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));

void main() {
  group('MoneyInputFormatter', () {
    final formatter = MoneyInputFormatter();

    test('formats thousands with dots as digits are typed', () {
      final result = formatter.formatEditUpdate(_tev(''), _tev('4'));
      expect(result.text, '4');
    });

    test('groups into thousands once past three digits', () {
      final result = formatter.formatEditUpdate(_tev('461'), _tev('4610'));
      expect(result.text, '4.610');
    });

    test('groups millions with a second dot', () {
      final result = formatter.formatEditUpdate(_tev(''), _tev('1500000'));
      expect(result.text, '1.500.000');
    });

    test('strips non-digit characters (e.g. a pasted decimal point)', () {
      final result = formatter.formatEditUpdate(_tev(''), _tev('12.5'));
      expect(result.text, '125');
    });

    test('clearing the field leaves it empty, not "0"', () {
      final result = formatter.formatEditUpdate(_tev('4'), _tev(''));
      expect(result.text, '');
    });

    test('cursor lands at the end of the formatted text', () {
      final result = formatter.formatEditUpdate(_tev('461'), _tev('4610'));
      expect(result.selection.baseOffset, result.text.length);
    });
  });

  group('formatMoneyForDisplay', () {
    test('formats a whole number with thousands dots', () {
      expect(formatMoneyForDisplay(461000), '461.000');
    });

    test('rounds a value with decimals to the nearest integer', () {
      expect(formatMoneyForDisplay(1500.7), '1.501');
    });

    test('formats zero as "0"', () {
      expect(formatMoneyForDisplay(0), '0');
    });
  });

  group('parseMoneyInput', () {
    test('parses a dotted-thousands string back to a double', () {
      expect(parseMoneyInput('461.000'), 461000.0);
    });

    test('parses a plain digit string', () {
      expect(parseMoneyInput('50'), 50.0);
    });

    test('empty string parses to 0', () {
      expect(parseMoneyInput(''), 0.0);
    });
  });
}

import 'package:billetera/logic/debt_calculator.dart';
import 'package:billetera/models/debt.dart';
import 'package:flutter_test/flutter_test.dart';

Debt _debt({
  required String personId,
  required double monto,
  required String estado,
}) => Debt(
  id: 'd',
  userId: 'u',
  personId: personId,
  motivo: 'motivo',
  monto: monto,
  fecha: DateTime(2026, 1, 1),
  estado: estado,
);

void main() {
  group('calculatePersonDebtTotal', () {
    test('sums only pendiente debts for the given person', () {
      final debts = [
        _debt(personId: 'p1', monto: 10000, estado: 'pendiente'),
        _debt(personId: 'p1', monto: 5000, estado: 'pendiente'),
      ];
      expect(calculatePersonDebtTotal(personId: 'p1', debts: debts), 15000);
    });

    test('ignores pagada debts', () {
      final debts = [
        _debt(personId: 'p1', monto: 10000, estado: 'pendiente'),
        _debt(personId: 'p1', monto: 5000, estado: 'pagada'),
      ];
      expect(calculatePersonDebtTotal(personId: 'p1', debts: debts), 10000);
    });

    test('ignores debts belonging to other people', () {
      final debts = [
        _debt(personId: 'p1', monto: 10000, estado: 'pendiente'),
        _debt(personId: 'p2', monto: 99999, estado: 'pendiente'),
      ];
      expect(calculatePersonDebtTotal(personId: 'p1', debts: debts), 10000);
    });

    test('returns 0 when the person has no debts', () {
      expect(calculatePersonDebtTotal(personId: 'p1', debts: []), 0);
    });
  });
}

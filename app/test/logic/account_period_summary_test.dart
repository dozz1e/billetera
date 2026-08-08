// app/test/logic/account_period_summary_test.dart
import 'package:billetera/logic/account_period_summary.dart';
import 'package:billetera/models/account.dart';
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = Account(
  id: 'a1',
  userId: 'u',
  nombre: 'Cuenta',
  tipo: 'banco',
  saldoInicial: 1000,
  activo: true,
);

Transaction _t({
  String accountId = 'a1',
  String? accountDestinoId,
  required TransactionType tipo,
  required double monto,
  required DateTime fecha,
}) => Transaction(
  id: 't',
  userId: 'u',
  accountId: accountId,
  accountDestinoId: accountDestinoId,
  categoryId: accountDestinoId == null ? 'c1' : null,
  tipo: tipo,
  monto: monto,
  fecha: fecha,
);

void main() {
  group('accountBalanceForPeriod', () {
    test('saldoInicio accumulates only transactions strictly before "from"', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 500, fecha: DateTime(2026, 1, 1)),
          _t(tipo: TransactionType.gasto, monto: 200, fecha: DateTime(2026, 1, 15)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoInicio, 1300); // 1000 + 500 - 200
      expect(result.points.first.saldo, 1300);
      expect(result.points.length, 1); // only the anchor point, nothing in-window
      expect(result.saldoFinal, 1300);
    });

    test('an incoming transfer to this account adds, regardless of accountId', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(
            accountId: 'other',
            accountDestinoId: 'a1',
            tipo: TransactionType.transferencia,
            monto: 300,
            fecha: DateTime(2026, 2, 10),
          ),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoFinal, 1300); // 1000 + 300
      expect(result.points.length, 2); // anchor + the transfer
    });

    test('an outgoing transfer from this account subtracts', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(
            accountId: 'a1',
            accountDestinoId: 'other',
            tipo: TransactionType.transferencia,
            monto: 300,
            fecha: DateTime(2026, 2, 10),
          ),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoFinal, 700); // 1000 - 300
    });

    test('variacionPorcentual is null when saldoInicio is 0', () {
      const zeroAccount = Account(
        id: 'a2',
        userId: 'u',
        nombre: 'Cuenta cero',
        tipo: 'efectivo',
        saldoInicial: 0,
        activo: true,
      );

      final result = accountBalanceForPeriod(
        account: zeroAccount,
        transactions: [
          _t(
            accountId: 'a2',
            tipo: TransactionType.ingreso,
            monto: 500,
            fecha: DateTime(2026, 2, 10),
          ),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoInicio, 0);
      expect(result.variacionPorcentual, isNull);
    });

    test('variacionPorcentual is computed correctly when saldoInicio is non-zero', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 500, fecha: DateTime(2026, 2, 10)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      // saldoInicio 1000, saldoFinal 1500 -> +50%
      expect(result.variacionPorcentual, 50.0);
    });

    test('boundaries are inclusive: a transaction exactly on "from" or "hasta" counts', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 100, fecha: DateTime(2026, 2, 1)),
          _t(tipo: TransactionType.gasto, monto: 50, fecha: DateTime(2026, 2, 28)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoInicio, 1000); // neither counted yet at the anchor
      expect(result.saldoFinal, 1050); // 1000 + 100 - 50
      expect(result.points.length, 3); // anchor + both transactions
    });

    test('a transaction after "hasta" is ignored entirely', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 999, fecha: DateTime(2026, 3, 5)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoFinal, 1000);
      expect(result.points.length, 1);
    });

    test('transactions belonging to another account are ignored', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(
            accountId: 'other',
            tipo: TransactionType.ingreso,
            monto: 999,
            fecha: DateTime(2026, 2, 10),
          ),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.saldoFinal, 1000);
      expect(result.points.length, 1);
    });

    test('points are in chronological order regardless of input order', () {
      final result = accountBalanceForPeriod(
        account: _account,
        transactions: [
          _t(tipo: TransactionType.ingreso, monto: 10, fecha: DateTime(2026, 2, 20)),
          _t(tipo: TransactionType.ingreso, monto: 10, fecha: DateTime(2026, 2, 5)),
        ],
        from: DateTime(2026, 2, 1),
        hasta: DateTime(2026, 2, 28),
      );

      expect(result.points[1].fecha, DateTime(2026, 2, 5));
      expect(result.points[2].fecha, DateTime(2026, 2, 20));
    });
  });
}

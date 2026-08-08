import 'package:billetera/logic/balance_calculator.dart';
import 'package:billetera/models/account.dart';
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateAccountBalance', () {
    test('adds ingresos and subtracts gastos for the account', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'c1', tipo: TransactionType.ingreso, monto: 1000, fecha: DateTime(2026, 1, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c2', tipo: TransactionType.gasto, monto: 300, fecha: DateTime(2026, 1, 2)),
      ];

      final balance = calculateAccountBalance(saldoInicial: 500, accountId: 'a1', transactions: transactions);

      expect(balance, 1200); // 500 + 1000 - 300
    });

    test('a transferencia subtracts from origin and adds to destination', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', accountDestinoId: 'a2', tipo: TransactionType.transferencia, monto: 400, fecha: DateTime(2026, 1, 1)),
      ];

      final origen = calculateAccountBalance(saldoInicial: 1000, accountId: 'a1', transactions: transactions);
      final destino = calculateAccountBalance(saldoInicial: 0, accountId: 'a2', transactions: transactions);

      expect(origen, 600);
      expect(destino, 400);
    });

    test('ignores transactions on other accounts', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'other', categoryId: 'c1', tipo: TransactionType.ingreso, monto: 999, fecha: DateTime(2026, 1, 1)),
      ];

      final balance = calculateAccountBalance(saldoInicial: 100, accountId: 'a1', transactions: transactions);

      expect(balance, 100);
    });

    test('excludes transactions dated after asOf (future transactions do not affect balance yet)', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'c1', tipo: TransactionType.ingreso, monto: 1000, fecha: DateTime(2026, 1, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c2', tipo: TransactionType.gasto, monto: 300, fecha: DateTime(2026, 6, 1)),
      ];

      final balance = calculateAccountBalance(
        saldoInicial: 500,
        accountId: 'a1',
        transactions: transactions,
        asOf: DateTime(2026, 1, 15),
      );

      expect(balance, 1500); // 500 + 1000, the June gasto is still in the future
    });

    test('includes a transaction dated exactly on asOf', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'c1', tipo: TransactionType.ingreso, monto: 1000, fecha: DateTime(2026, 1, 15)),
      ];

      final balance = calculateAccountBalance(
        saldoInicial: 0,
        accountId: 'a1',
        transactions: transactions,
        asOf: DateTime(2026, 1, 15),
      );

      expect(balance, 1000);
    });
  });

  group('calculateTotalBalance', () {
    test('sums the balance of every account, transferencias net to zero across accounts', () {
      final accounts = [
        const Account(id: 'a1', userId: 'u', nombre: 'Banco', tipo: 'banco', saldoInicial: 1000, activo: true),
        const Account(id: 'a2', userId: 'u', nombre: 'Efectivo', tipo: 'efectivo', saldoInicial: 0, activo: true),
      ];
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', accountDestinoId: 'a2', tipo: TransactionType.transferencia, monto: 400, fecha: DateTime(2026, 1, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c1', tipo: TransactionType.ingreso, monto: 200, fecha: DateTime(2026, 1, 2)),
      ];

      final total = calculateTotalBalance(accounts: accounts, allTransactions: transactions);

      expect(total, 1200); // 1000 + 0 - 400 + 400 + 200
    });
  });
}

import 'package:billetera/logic/chart_aggregator.dart';
import 'package:billetera/models/account.dart';
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expensesByCategory', () {
    test('sums gasto amounts by category name for the given month, ignores other months and ingresos', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 100, fecha: DateTime(2026, 8, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 50, fecha: DateTime(2026, 8, 15)),
        Transaction(id: '3', userId: 'u', accountId: 'a1', categoryId: 'transporte', tipo: TransactionType.gasto, monto: 20, fecha: DateTime(2026, 8, 2)),
        Transaction(id: '4', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 999, fecha: DateTime(2026, 7, 1)),
        Transaction(id: '5', userId: 'u', accountId: 'a1', categoryId: 'sueldo', tipo: TransactionType.ingreso, monto: 5000, fecha: DateTime(2026, 8, 1)),
      ];

      final result = expensesByCategory(
        transactions: transactions,
        categoryNamesById: {'comida': 'Comida', 'transporte': 'Transporte', 'sueldo': 'Sueldo'},
        year: 2026,
        month: 8,
      );

      expect(result, {'Comida': 150, 'Transporte': 20});
    });
  });

  group('monthlyIncomeVsExpense', () {
    test('buckets ingresos and gastos per month for the requested range, filling months with no data as zero', () {
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'c', tipo: TransactionType.ingreso, monto: 1000, fecha: DateTime(2026, 8, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c', tipo: TransactionType.gasto, monto: 300, fecha: DateTime(2026, 8, 5)),
      ];

      final result = monthlyIncomeVsExpense(transactions: transactions, monthsBack: 3, referenceDate: DateTime(2026, 8, 10));

      expect(result.length, 3);
      expect(result.last.year, 2026);
      expect(result.last.month, 8);
      expect(result.last.ingresos, 1000);
      expect(result.last.gastos, 300);
      expect(result.first.month, 6);
      expect(result.first.ingresos, 0);
      expect(result.first.gastos, 0);
    });
  });

  group('balanceOverTime', () {
    test('produces a running total balance point per transaction, ignoring transferencias', () {
      final accounts = [
        const Account(id: 'a1', userId: 'u', nombre: 'Banco', tipo: 'banco', saldoInicial: 100, activo: true),
      ];
      final transactions = [
        Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'c', tipo: TransactionType.ingreso, monto: 50, fecha: DateTime(2026, 8, 1)),
        Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'c', tipo: TransactionType.gasto, monto: 20, fecha: DateTime(2026, 8, 2)),
        Transaction(id: '3', userId: 'u', accountId: 'a1', accountDestinoId: 'a2', tipo: TransactionType.transferencia, monto: 30, fecha: DateTime(2026, 8, 3)),
      ];

      final points = balanceOverTime(accounts: accounts, transactions: transactions);

      expect(points.length, 3);
      expect(points[0].saldo, 150);
      expect(points[1].saldo, 130);
      expect(points[2].saldo, 130); // transferencia does not change balance
    });
  });
}

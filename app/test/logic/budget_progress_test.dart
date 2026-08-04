import 'package:billetera/logic/budget_progress.dart';
import 'package:billetera/models/budget.dart';
import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gastado sums only gasto transactions in the budget category and month; excedido flips over the limit', () {
    final budget = Budget(id: 'b1', userId: 'u', categoryId: 'comida', mes: DateTime(2026, 8, 1), montoLimite: 100);
    final transactions = [
      Transaction(id: '1', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 60, fecha: DateTime(2026, 8, 5)),
      Transaction(id: '2', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 50, fecha: DateTime(2026, 8, 10)),
      Transaction(id: '3', userId: 'u', accountId: 'a1', categoryId: 'transporte', tipo: TransactionType.gasto, monto: 999, fecha: DateTime(2026, 8, 10)),
      Transaction(id: '4', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.gasto, monto: 999, fecha: DateTime(2026, 7, 10)),
      Transaction(id: '5', userId: 'u', accountId: 'a1', categoryId: 'comida', tipo: TransactionType.ingreso, monto: 999, fecha: DateTime(2026, 8, 15)),
      Transaction(id: '6', userId: 'u', accountId: 'a1', accountDestinoId: 'a2', categoryId: 'comida', tipo: TransactionType.transferencia, monto: 999, fecha: DateTime(2026, 8, 15)),
    ];

    final result = calculateBudgetProgress(budgets: [budget], transactions: transactions);

    expect(result.single.gastado, 110);
    expect(result.single.excedido, isTrue);
  });
}

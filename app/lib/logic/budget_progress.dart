import '../models/budget.dart';
import '../models/transaction.dart';

class BudgetProgress {
  const BudgetProgress({required this.budget, required this.gastado});

  final Budget budget;
  final double gastado;

  double get porcentaje => budget.montoLimite <= 0 ? 0 : gastado / budget.montoLimite;
  bool get excedido => gastado > budget.montoLimite;
}

List<BudgetProgress> calculateBudgetProgress({
  required List<Budget> budgets,
  required List<Transaction> transactions,
}) {
  return budgets.map((b) {
    final gastado = transactions
        .where((t) =>
            t.tipo == TransactionType.gasto &&
            t.categoryId == b.categoryId &&
            t.fecha.year == b.mes.year &&
            t.fecha.month == b.mes.month)
        .fold(0.0, (sum, t) => sum + t.monto);
    return BudgetProgress(budget: b, gastado: gastado);
  }).toList();
}

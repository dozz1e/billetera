import '../models/account.dart';
import '../models/transaction.dart';

Map<String, double> expensesByCategory({
  required List<Transaction> transactions,
  required Map<String, String> categoryNamesById,
  required int year,
  required int month,
}) {
  final result = <String, double>{};
  for (final t in transactions) {
    if (t.tipo != TransactionType.gasto) continue;
    if (t.fecha.year != year || t.fecha.month != month) continue;
    final name = categoryNamesById[t.categoryId] ?? 'Sin categoria';
    result[name] = (result[name] ?? 0) + t.monto;
  }
  return result;
}

class MonthlyTotals {
  const MonthlyTotals({
    required this.year,
    required this.month,
    required this.ingresos,
    required this.gastos,
  });

  final int year;
  final int month;
  final double ingresos;
  final double gastos;

  MonthlyTotals copyWith({double? ingresos, double? gastos}) => MonthlyTotals(
        year: year,
        month: month,
        ingresos: ingresos ?? this.ingresos,
        gastos: gastos ?? this.gastos,
      );
}

List<MonthlyTotals> monthlyIncomeVsExpense({
  required List<Transaction> transactions,
  required int monthsBack,
  required DateTime referenceDate,
}) {
  final buckets = <String, MonthlyTotals>{};
  final order = <String>[];
  for (var i = monthsBack - 1; i >= 0; i--) {
    final d = DateTime(referenceDate.year, referenceDate.month - i, 1);
    final key = '${d.year}-${d.month}';
    buckets[key] = MonthlyTotals(year: d.year, month: d.month, ingresos: 0, gastos: 0);
    order.add(key);
  }

  for (final t in transactions) {
    final key = '${t.fecha.year}-${t.fecha.month}';
    final existing = buckets[key];
    if (existing == null) continue;
    if (t.tipo == TransactionType.ingreso) {
      buckets[key] = existing.copyWith(ingresos: existing.ingresos + t.monto);
    } else if (t.tipo == TransactionType.gasto) {
      buckets[key] = existing.copyWith(gastos: existing.gastos + t.monto);
    }
  }

  return order.map((k) => buckets[k]!).toList();
}

class BalancePoint {
  const BalancePoint({required this.fecha, required this.saldo});

  final DateTime fecha;
  final double saldo;
}

List<BalancePoint> balanceOverTime({
  required List<Account> accounts,
  required List<Transaction> transactions,
}) {
  final sorted = [...transactions]..sort((a, b) => a.fecha.compareTo(b.fecha));
  final points = <BalancePoint>[];
  var running = accounts.fold(0.0, (sum, a) => sum + a.saldoInicial);

  for (final t in sorted) {
    if (t.tipo == TransactionType.ingreso) {
      running += t.monto;
    } else if (t.tipo == TransactionType.gasto) {
      running -= t.monto;
    }
    points.add(BalancePoint(fecha: t.fecha, saldo: running));
  }

  return points;
}

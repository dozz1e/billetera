import '../models/account.dart';
import '../models/transaction.dart';

class AccountBalancePoint {
  const AccountBalancePoint({required this.fecha, required this.saldo});

  final DateTime fecha;
  final double saldo;
}

class AccountPeriodSummary {
  const AccountPeriodSummary({
    required this.points,
    required this.saldoInicio,
    required this.saldoFinal,
    required this.variacionPorcentual,
  });

  final List<AccountBalancePoint> points;
  final double saldoInicio;
  final double saldoFinal;
  final double? variacionPorcentual;
}

/// Computes the balance-over-time chart data for one account within
/// [from, hasta] (inclusive both ends), plus the % change across that
/// window. Mirrors the sign convention of `calculateAccountBalance` in
/// balance_calculator.dart: this account's own ingreso/gasto/transferencia
/// rows apply directly, and an incoming transferencia from another account
/// (accountDestinoId == account.id) adds instead.
AccountPeriodSummary accountBalanceForPeriod({
  required Account account,
  required List<Transaction> transactions,
  required DateTime from,
  required DateTime hasta,
}) {
  final relevant =
      transactions
          .where(
            (t) =>
                t.accountId == account.id || t.accountDestinoId == account.id,
          )
          .toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));

  var running = account.saldoInicial;

  void apply(Transaction t) {
    switch (t.tipo) {
      case TransactionType.ingreso:
        if (t.accountId == account.id) running += t.monto;
      case TransactionType.gasto:
        if (t.accountId == account.id) running -= t.monto;
      case TransactionType.transferencia:
        if (t.accountId == account.id) running -= t.monto;
        if (t.accountDestinoId == account.id) running += t.monto;
    }
  }

  var i = 0;
  while (i < relevant.length && relevant[i].fecha.isBefore(from)) {
    apply(relevant[i]);
    i++;
  }
  final saldoInicio = running;

  final points = <AccountBalancePoint>[
    AccountBalancePoint(fecha: from, saldo: saldoInicio),
  ];

  while (i < relevant.length && !relevant[i].fecha.isAfter(hasta)) {
    apply(relevant[i]);
    points.add(AccountBalancePoint(fecha: relevant[i].fecha, saldo: running));
    i++;
  }

  final saldoFinal = running;
  final variacionPorcentual = saldoInicio == 0
      ? null
      : (saldoFinal - saldoInicio) / saldoInicio * 100;

  return AccountPeriodSummary(
    points: points,
    saldoInicio: saldoInicio,
    saldoFinal: saldoFinal,
    variacionPorcentual: variacionPorcentual,
  );
}

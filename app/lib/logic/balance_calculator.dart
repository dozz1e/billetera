import '../models/account.dart';
import '../models/transaction.dart';

double calculateAccountBalance({
  required double saldoInicial,
  required String accountId,
  required List<Transaction> transactions,
  DateTime? asOf,
}) {
  final cutoff = asOf ?? DateTime.now();
  var balance = saldoInicial;
  for (final t in transactions) {
    if (t.fecha.isAfter(cutoff)) continue;
    switch (t.tipo) {
      case TransactionType.ingreso:
        if (t.accountId == accountId) balance += t.monto;
      case TransactionType.gasto:
        if (t.accountId == accountId) balance -= t.monto;
      case TransactionType.transferencia:
        if (t.accountId == accountId) balance -= t.monto;
        if (t.accountDestinoId == accountId) balance += t.monto;
    }
  }
  return balance;
}

double calculateTotalBalance({
  required List<Account> accounts,
  required List<Transaction> allTransactions,
  DateTime? asOf,
}) {
  var total = 0.0;
  for (final account in accounts) {
    total += calculateAccountBalance(
      saldoInicial: account.saldoInicial,
      accountId: account.id,
      transactions: allTransactions,
      asOf: asOf,
    );
  }
  return total;
}

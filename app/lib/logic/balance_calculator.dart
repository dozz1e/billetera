import '../models/account.dart';
import '../models/transaction.dart';

double calculateAccountBalance({
  required double saldoInicial,
  required String accountId,
  required List<Transaction> transactions,
}) {
  var balance = saldoInicial;
  for (final t in transactions) {
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
}) {
  var total = 0.0;
  for (final account in accounts) {
    total += calculateAccountBalance(
      saldoInicial: account.saldoInicial,
      accountId: account.id,
      transactions: allTransactions,
    );
  }
  return total;
}

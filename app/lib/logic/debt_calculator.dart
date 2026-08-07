import '../models/debt.dart';

double calculatePersonDebtTotal({
  required String personId,
  required List<Debt> debts,
}) {
  return debts
      .where((d) => d.personId == personId && d.estado == 'pendiente')
      .fold(0.0, (sum, d) => sum + d.monto);
}

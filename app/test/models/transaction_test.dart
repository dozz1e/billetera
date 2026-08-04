import 'package:billetera/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Transaction.fromJson parses a gasto row correctly', () {
    final json = {
      'id': 't1',
      'user_id': 'u1',
      'account_id': 'a1',
      'category_id': 'c1',
      'account_destino_id': null,
      'tipo': 'gasto',
      'monto': 1500.0,
      'fecha': '2026-08-01',
      'nota': 'Almuerzo',
    };

    final t = Transaction.fromJson(json);

    expect(t.id, 't1');
    expect(t.tipo, TransactionType.gasto);
    expect(t.monto, 1500.0);
    expect(t.fecha, DateTime(2026, 8, 1));
    expect(t.accountDestinoId, isNull);
  });

  test('toInsertJson round-trips tipo as a string', () {
    final t = Transaction(
      id: 't1',
      userId: 'u1',
      accountId: 'a1',
      categoryId: 'c1',
      tipo: TransactionType.ingreso,
      monto: 2000.0,
      fecha: DateTime(2026, 8, 1),
    );

    expect(t.toInsertJson()['tipo'], 'ingreso');
  });
}

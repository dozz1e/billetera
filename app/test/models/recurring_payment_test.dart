// app/test/models/recurring_payment_test.dart
import 'package:billetera/models/recurring_payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RecurringPayment.fromJson parses a full row correctly', () {
    final json = {
      'id': 'r1',
      'user_id': 'u1',
      'account_id': 'a1',
      'category_id': 'c1',
      'monto': 15000.0,
      'dia_mes': 5,
      'nota': 'Arriendo',
      'fecha_inicio': '2026-01-05',
      'ultima_generada': '2026-03-05',
      'activo': true,
    };

    final r = RecurringPayment.fromJson(json);

    expect(r.id, 'r1');
    expect(r.accountId, 'a1');
    expect(r.categoryId, 'c1');
    expect(r.monto, 15000.0);
    expect(r.diaMes, 5);
    expect(r.nota, 'Arriendo');
    expect(r.fechaInicio, DateTime(2026, 1, 5));
    expect(r.ultimaGenerada, DateTime(2026, 3, 5));
    expect(r.activo, isTrue);
  });

  test('RecurringPayment.fromJson parses a null ultima_generada and nota', () {
    final json = {
      'id': 'r2',
      'user_id': 'u1',
      'account_id': 'a1',
      'category_id': 'c1',
      'monto': 5000.0,
      'dia_mes': 20,
      'nota': null,
      'fecha_inicio': '2026-06-20',
      'ultima_generada': null,
      'activo': false,
    };

    final r = RecurringPayment.fromJson(json);

    expect(r.nota, isNull);
    expect(r.ultimaGenerada, isNull);
    expect(r.activo, isFalse);
  });

  test('toInsertJson formats dates as yyyy-MM-dd and omits ultima_generada', () {
    final r = RecurringPayment(
      id: '',
      userId: '',
      accountId: 'a1',
      categoryId: 'c1',
      monto: 15000,
      diaMes: 5,
      fechaInicio: DateTime(2026, 1, 5),
      activo: true,
    );

    final json = r.toInsertJson();

    expect(json['fecha_inicio'], '2026-01-05');
    expect(json['account_id'], 'a1');
    expect(json['dia_mes'], 5);
    expect(json.containsKey('ultima_generada'), isFalse);
    expect(json.containsKey('id'), isFalse);
  });
}

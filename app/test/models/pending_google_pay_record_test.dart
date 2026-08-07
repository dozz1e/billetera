import 'package:billetera/models/pending_google_pay_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toMap/fromMap round-trips all fields', () {
    final record = PendingGooglePayRecord(
      id: 'notif-1',
      monto: 8574.0,
      comercioTexto: 'MERCADOPAGO *ARIZMEND',
      categoriaSugeridaId: 'cat-1',
      fecha: DateTime(2026, 8, 7),
      estado: 'pendiente',
      createdAt: DateTime(2026, 8, 7, 10, 30),
    );

    final restored = PendingGooglePayRecord.fromMap(record.toMap());

    expect(restored.id, 'notif-1');
    expect(restored.monto, 8574.0);
    expect(restored.comercioTexto, 'MERCADOPAGO *ARIZMEND');
    expect(restored.categoriaSugeridaId, 'cat-1');
    expect(restored.fecha, DateTime(2026, 8, 7));
    expect(restored.estado, 'pendiente');
    expect(restored.createdAt, DateTime(2026, 8, 7, 10, 30));
  });

  test('fromMap handles a null categoriaSugeridaId', () {
    final record = PendingGooglePayRecord(
      id: 'notif-2',
      monto: 1800.0,
      comercioTexto: 'STA ISABEL VINA DEL MA',
      categoriaSugeridaId: null,
      fecha: DateTime(2026, 8, 6),
      estado: 'pendiente',
      createdAt: DateTime(2026, 8, 6, 9, 0),
    );

    final restored = PendingGooglePayRecord.fromMap(record.toMap());

    expect(restored.categoriaSugeridaId, isNull);
  });

  test('copyWith replaces estado and keeps every other field', () {
    final record = PendingGooglePayRecord(
      id: 'notif-3',
      monto: 4230.0,
      comercioTexto: 'LUCY VENEGAS',
      categoriaSugeridaId: 'cat-2',
      fecha: DateTime(2026, 8, 5),
      estado: 'pendiente',
      createdAt: DateTime(2026, 8, 5, 8, 0),
    );

    final discarded = record.copyWith(estado: 'descartado');

    expect(discarded.estado, 'descartado');
    expect(discarded.id, record.id);
    expect(discarded.monto, record.monto);
    expect(discarded.comercioTexto, record.comercioTexto);
  });
}

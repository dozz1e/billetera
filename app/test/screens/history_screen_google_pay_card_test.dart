import 'dart:io';

import 'package:billetera/models/pending_google_pay_record.dart';
import 'package:billetera/services/google_pay_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<Map> pendingBox;
  late Box settingsBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('history_google_pay_test');
    Hive.init(tempDir.path);
    pendingBox = await Hive.openBox<Map>(googlePayPendingBoxName);
    settingsBox = await Hive.openBox(googlePaySettingsBoxName);
  });

  tearDown(() async {
    await pendingBox.close();
    await settingsBox.close();
    await tempDir.delete(recursive: true);
  });

  test('a pendiente record is visible through the box and an estado change persists', () async {
    final record = PendingGooglePayRecord(
      id: 'notif-1',
      monto: 8574.0,
      comercioTexto: 'MERCADOPAGO *ARIZMEND',
      categoriaSugeridaId: 'c-comida',
      fecha: DateTime(2026, 8, 7),
      estado: 'pendiente',
      createdAt: DateTime(2026, 8, 7),
    );
    await pendingBox.put(record.id, record.toMap());

    final pendientes = pendingBox.values
        .map((m) => PendingGooglePayRecord.fromMap(m))
        .where((r) => r.estado == 'pendiente')
        .toList();
    expect(pendientes, hasLength(1));

    final discarded = pendientes.first.copyWith(estado: 'descartado');
    await pendingBox.put(discarded.id, discarded.toMap());

    final stillPending = pendingBox.values
        .map((m) => PendingGooglePayRecord.fromMap(m))
        .where((r) => r.estado == 'pendiente')
        .toList();
    expect(stillPending, isEmpty);
  });

  test('GooglePaySettings default account id round-trips through the settings box', () async {
    final settings = GooglePaySettings(settingsBox);
    expect(settings.defaultAccountId, isNull);

    await settings.setDefaultAccountId('acc-1');
    expect(settings.defaultAccountId, 'acc-1');
  });
}

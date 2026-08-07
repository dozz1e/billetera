import 'dart:async';
import 'dart:io';

import 'package:billetera/models/category.dart';
import 'package:billetera/services/google_pay_listener_service.dart';
import 'package:billetera/services/google_pay_notification_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeSource implements GooglePayNotificationSource {
  final _controller = StreamController<RawNotification>();

  /// Canned "already active" notifications returned by
  /// [getActiveNotifications], simulating notifications still visible in the
  /// shade when `start()` is called (e.g. app was closed when they arrived).
  List<RawNotification> activeNotifications = const [];

  /// When set, [getActiveNotifications] throws this instead of returning
  /// [activeNotifications] — simulates the drain's real-device failure mode
  /// (e.g. the plugin's `fromMap` `TypeError`, or any other platform-boundary
  /// exception) so callers can assert `start()` survives it.
  Object? activeNotificationsError;

  @override
  Stream<RawNotification> get events => _controller.stream;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<List<RawNotification>> getActiveNotifications() async {
    final error = activeNotificationsError;
    if (error != null) throw error;
    return activeNotifications;
  }

  void emit(RawNotification notification) => _controller.add(notification);

  Future<void> close() => _controller.close();
}

const _categories = [
  Category(id: 'c-comida', userId: 'u', nombre: 'Comida', tipo: 'gasto', icono: 'restaurant', predefinida: true),
  Category(id: 'c-otros', userId: 'u', nombre: 'Otros gastos', tipo: 'gasto', icono: 'category', predefinida: true),
];

void main() {
  late Directory tempDir;
  late Box<Map> box;
  late _FakeSource source;
  late GooglePayListenerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('google_pay_listener_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<Map>('google_pay_pending_test');
    source = _FakeSource();
    service = GooglePayListenerService(source, box, _categories);
    await service.start();
  });

  tearDown(() async {
    service.dispose();
    await source.close();
    await box.close();
    await tempDir.delete(recursive: true);
  });

  test('stores a parseable Google Wallet notification as a pending record', () async {
    source.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-1',
      title: 'Google Wallet',
      text: 'Pagaste \$8.574,00 en MERCADOPAGO *ARIZMEND',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.length, 1);
    final stored = box.get('notif-1')!;
    expect(stored['monto'], 8574.0);
    expect(stored['comercio_texto'], 'MERCADOPAGO *ARIZMEND');
    expect(stored['categoria_sugerida_id'], 'c-comida');
    expect(stored['estado'], 'pendiente');
  });

  test('ignores notifications from other packages', () async {
    source.emit(const RawNotification(
      packageName: 'com.some.bank.app',
      notificationKey: 'notif-2',
      title: 'Banco',
      text: 'Pagaste \$1.000,00 en ALGUN COMERCIO',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.length, 0);
  });

  test('ignores a notification body it cannot parse', () async {
    source.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-3',
      title: 'Google Wallet',
      text: 'Tu tarjeta fue agregada correctamente',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.length, 0);
  });

  test('does not duplicate a notification key already stored, even if discarded', () async {
    source.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-4',
      title: 'Google Wallet',
      text: 'Pagaste \$500,00 en HIPER VINA CENTRO',
    ));
    await Future<void>.delayed(Duration.zero);
    await box.put('notif-4', {...box.get('notif-4')!, 'estado': 'descartado'});

    source.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-4',
      title: 'Google Wallet',
      text: 'Pagaste \$500,00 en HIPER VINA CENTRO',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.length, 1);
    expect(box.get('notif-4')!['estado'], 'descartado');
  });

  test('drains notifications already active in the shade on start()', () async {
    // Independent source/service pair: the shared `source`/`service` from
    // setUp already had start() called against an empty active list, so
    // this exercises the drain in isolation, reusing the same Hive box.
    final activeSource = _FakeSource()
      ..activeNotifications = [
        const RawNotification(
          packageName: googleWalletPackageName,
          notificationKey: 'notif-active-1',
          title: 'Google Wallet',
          text: 'Pagaste \$3.200,00 en FARMACIA CRUZ VERDE',
        ),
      ];
    final activeService = GooglePayListenerService(activeSource, box, _categories);

    await activeService.start();

    expect(box.containsKey('notif-active-1'), isTrue);
    final stored = box.get('notif-active-1')!;
    expect(stored['monto'], 3200.0);
    expect(stored['comercio_texto'], 'FARMACIA CRUZ VERDE');
    expect(stored['estado'], 'pendiente');

    activeService.dispose();
    await activeSource.close();
  });

  test('start() swallows a drain failure and the live subscription keeps working', () async {
    // Independent source/service pair, same reasoning as the drain test
    // above: isolates this from the shared `setUp` service/box state.
    final throwingSource = _FakeSource()..activeNotificationsError = Exception('boom: getActiveNotifications failed');
    final throwingService = GooglePayListenerService(throwingSource, box, _categories);

    // start() must complete without throwing even though the drain fails.
    await throwingService.start();

    // The live stream, subscribed to before the drain ran, must still work.
    throwingSource.emit(const RawNotification(
      packageName: googleWalletPackageName,
      notificationKey: 'notif-after-drain-failure',
      title: 'Google Wallet',
      text: 'Pagaste \$700,00 en LIVE STREAM STILL WORKS',
    ));
    await Future<void>.delayed(Duration.zero);

    expect(box.containsKey('notif-after-drain-failure'), isTrue);
    final stored = box.get('notif-after-drain-failure')!;
    expect(stored['monto'], 700.0);
    expect(stored['comercio_texto'], 'LIVE STREAM STILL WORKS');
    expect(stored['estado'], 'pendiente');

    throwingService.dispose();
    await throwingSource.close();
  });
}

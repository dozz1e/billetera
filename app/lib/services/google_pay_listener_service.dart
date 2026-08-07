import 'dart:async';

import 'package:hive/hive.dart';

import '../logic/google_pay_category_matcher.dart';
import '../logic/google_pay_notification_parser.dart';
import '../models/category.dart';
import '../models/pending_google_pay_record.dart';
import 'google_pay_notification_source.dart';

class GooglePayListenerService {
  GooglePayListenerService(this._source, this._box, this._categories);

  final GooglePayNotificationSource _source;
  final Box<Map> _box;
  final List<Category> _categories;
  StreamSubscription<RawNotification>? _subscription;

  void start() {
    _subscription = _source.events.listen(_handle);
  }

  void _handle(RawNotification notification) {
    if (notification.packageName != googleWalletPackageName) return;
    if (_box.containsKey(notification.notificationKey)) return;

    final parsed = parseGooglePayNotification(
      title: notification.title,
      text: notification.text,
    );
    if (parsed == null) return;

    final categoriaId = matchCategoryId(
      comercioTexto: parsed.comercioTexto,
      categories: _categories,
    );

    final now = DateTime.now();
    final record = PendingGooglePayRecord(
      id: notification.notificationKey,
      monto: parsed.monto,
      comercioTexto: parsed.comercioTexto,
      categoriaSugeridaId: categoriaId,
      fecha: now,
      estado: 'pendiente',
      createdAt: now,
    );
    _box.put(record.id, record.toMap());
  }

  void dispose() {
    _subscription?.cancel();
  }
}

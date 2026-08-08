import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
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

  // Subscribes to live notifications first, then drains anything already
  // posted and visible in the shade (e.g. a payment made while the app was
  // fully closed). Draining after subscribing avoids a gap where a
  // notification posted between the two steps could be missed entirely;
  // `_handle`'s dedupe check (via `_box.containsKey`) makes it safe either
  // way if the same notification shows up in both the drain and the live
  // stream.
  //
  // The drain crosses a native platform boundary (`getActiveNotifications()`)
  // that can fail in ways beyond our control (platform exceptions, plugin
  // bugs on some OS/device combos, etc.) — any failure there is caught and
  // logged rather than allowed to propagate, so a broken drain never takes
  // down the live subscription that was just established above.
  Future<void> start() async {
    _subscription = _source.events.listen(_handle);
    try {
      final active = await _source.getActiveNotifications();
      for (final notification in active) {
        _handle(notification);
      }
    } catch (e) {
      debugPrint('GooglePayListenerService: failed to drain active notifications: $e');
    }
  }

  void _handle(RawNotification notification) {
    if (notification.packageName != googleWalletPackageName) return;
    if (_box.containsKey(notification.notificationKey)) return;

    final parsed = parseGooglePayNotification(
      title: notification.title,
      text: notification.text,
    );
    if (parsed == null) {
      debugPrint(
        'GooglePayListenerService: could not parse notification '
        'title="${notification.title}" text="${notification.text}"',
      );
      return;
    }

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

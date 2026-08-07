import 'package:notification_listener_service/notification_listener_service.dart';

import 'google_pay_notification_source.dart';

/// Real, plugin-backed `GooglePayNotificationSource`. Wraps the
/// `notification_listener_service` package's static API (verified against
/// the installed 1.0.0 source in
/// `notification_listener_service-1.0.0/lib/` — see task-7-report.md).
class PluginGooglePayNotificationSource implements GooglePayNotificationSource {
  @override
  Stream<RawNotification> get events => NotificationListenerService.notificationsStream
      // Filtered here, at the earliest point in Dart, rather than only in
      // GooglePayListenerService — keeps the orchestration layer from
      // processing noise from every other app's notifications (see the
      // design spec's native-filter rationale). GooglePayListenerService
      // still re-checks the package name defensively (and that's what its
      // unit test covers), so this filter isn't load-bearing for either
      // correctness or test coverage — only for reducing unnecessary work.
      .where((event) => event.packageName == googleWalletPackageName)
      // The plugin's notificationsStream fires for both posted and removed
      // events (Android's hasRemoved flag distinguishes them). We only ever
      // want to record from a posted notification, so drop removals here.
      .where((event) => !event.hasRemoved)
      .map(
        (event) => _toRawNotification(
          packageName: event.packageName,
          id: event.id,
          title: event.title,
          content: event.content,
        ),
      );

  @override
  Future<bool> hasPermission() => NotificationListenerService.isPermissionGranted();

  @override
  Future<void> requestPermission() => NotificationListenerService.requestPermission();

  // Drains notifications that are currently posted and still visible in the
  // notification shade — covers the case where a Google Wallet payment
  // happened while the app wasn't running (and thus wasn't subscribed to
  // `events` yet). Verified against the real, installed plugin API
  // (`notification_listener_service-1.0.0`): backed on the native side by
  // `NotificationListener.getActiveNotificationData()`. Does not surface
  // notifications the user already dismissed before opening the app.
  //
  // Deliberately bypasses `NotificationListenerService.getActiveNotifications()`
  // and its `ServiceNotificationEvent.fromMap`: `fromMap` assigns every field
  // a `??` fallback EXCEPT the non-nullable `haveExtraPicture`
  // (`map['haveExtraPicture'],` with no fallback — see
  // `notification_listener_service-1.0.0/lib/notification_event.dart`). The
  // native active-notifications payload
  // (`NotificationListener.getActiveNotificationData()`) never includes
  // `haveExtraPicture` (only `id`, `packageName`, `title`, `content`,
  // `onGoing`, `postTime`), so `fromMap` throws an uncaught `TypeError` for
  // every currently-active notification on the device — a `TypeError`, not a
  // `PlatformException`, so it isn't caught by
  // `getActiveNotifications()`'s own `try`/`on PlatformException`. Invoking
  // the plugin's own `methodeChannel` directly (same channel + method name
  // `getActiveNotifications()` itself uses internally) and mapping the raw
  // fields ourselves avoids `fromMap` entirely.
  @override
  Future<List<RawNotification>> getActiveNotifications() async {
    final rawResult = await methodeChannel.invokeMethod('getActiveNotifications');
    final raw = (rawResult as List<dynamic>?) ?? const [];
    return raw
        .cast<Map<dynamic, dynamic>>()
        .where((item) => item['packageName'] == googleWalletPackageName)
        .map(
          (item) => _toRawNotification(
            packageName: item['packageName'] as String? ?? '',
            id: (item['id'] as num?)?.toInt() ?? 0,
            title: item['title'] as String? ?? '',
            content: item['content'] as String? ?? '',
          ),
        )
        // Active/currently-posted notifications are inherently not removed —
        // there's no `hasRemoved` field on this data shape (Android's active
        // notification list, unlike the live event stream, never includes
        // already-dismissed notifications), so no filter is applied here.
        .toList();
  }

  RawNotification _toRawNotification({
    required String packageName,
    required int id,
    required String title,
    required String content,
  }) => RawNotification(
    packageName: packageName,
    // The plugin's ServiceNotificationEvent has no `uniqueId` field —
    // its unique identifier is the int `id` (Android's notification
    // id, defaulted to 0 if the platform side omits it). `id` alone is
    // app-assigned (not OS-assigned) and can be reused across genuinely
    // different notifications, so it's combined with a signature of the
    // title/content to shrink the collision window.
    notificationKey: '$id-${title.hashCode}-${content.hashCode}',
    title: title,
    text: content,
  );
}

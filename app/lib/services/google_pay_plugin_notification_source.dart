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
        (event) => RawNotification(
          packageName: event.packageName,
          // The plugin's ServiceNotificationEvent has no `uniqueId` field —
          // its unique identifier is the int `id` (Android's notification
          // id, defaulted to 0 by the plugin if the platform side omits it).
          // `id` alone is app-assigned (not OS-assigned) and can be reused
          // across genuinely different notifications, so it's combined with
          // a signature of the title/content to shrink the collision window.
          notificationKey: '${event.id}-${event.title.hashCode}-${event.content.hashCode}',
          title: event.title,
          text: event.content,
        ),
      );

  @override
  Future<bool> hasPermission() => NotificationListenerService.isPermissionGranted();

  @override
  Future<void> requestPermission() => NotificationListenerService.requestPermission();
}

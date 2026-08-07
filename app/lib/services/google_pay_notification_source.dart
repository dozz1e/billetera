/// Package name Android assigns to the Google Wallet app — the only source
/// GooglePayListenerService acts on (see Global Constraints in the design spec).
const googleWalletPackageName = 'com.google.android.apps.walletnfcrel';

class RawNotification {
  const RawNotification({
    required this.packageName,
    required this.notificationKey,
    required this.title,
    required this.text,
  });

  final String packageName;

  /// Native notification key, unique per posted notification. Used for
  /// dedupe when Android re-posts the same notification.
  final String notificationKey;
  final String? title;
  final String? text;
}

/// Isolates GooglePayListenerService from the concrete notification-listener
/// plugin so the orchestration logic can be unit tested with a fake. The
/// real, plugin-backed implementation is `PluginGooglePayNotificationSource`
/// (see google_pay_plugin_notification_source.dart, Task 7) — untested by
/// nature, since it wraps a native Android service not practicable in CI.
abstract class GooglePayNotificationSource {
  Stream<RawNotification> get events;
  Future<bool> hasPermission();
  Future<void> requestPermission();
}

// app/lib/services/google_pay_settings.dart
import 'package:hive/hive.dart';

const googlePayPendingBoxName = 'google_pay_pending';
const googlePaySettingsBoxName = 'google_pay_settings';

class GooglePaySettings {
  GooglePaySettings(this._box);

  final Box _box;
  static const _keyDefaultAccountId = 'default_account_id';

  String? get defaultAccountId => _box.get(_keyDefaultAccountId) as String?;

  Future<void> setDefaultAccountId(String? accountId) => _box.put(_keyDefaultAccountId, accountId);
}

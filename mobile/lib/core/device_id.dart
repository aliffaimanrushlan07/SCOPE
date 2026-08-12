import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// The anonymous device identifier.
///
/// Generated on first launch and held in platform secure storage (Keychain on
/// iOS, EncryptedSharedPreferences on Android). It is the ONLY identifier
/// attached to a report.
///
/// It is deliberately NOT derived from any hardware value — not the IMEI, not
/// the advertising ID, not the Android ID. A random UUID cannot be correlated
/// with the handset, its owner, or any other dataset, which is what makes
/// anonymity a property of the design rather than a promise in a privacy
/// policy.
///
/// The consequence, which the app states plainly rather than hiding: because
/// nothing links this value to a person, it cannot be recovered. Reinstalling
/// the app or changing handset produces a new identifier and Report History
/// starts empty. See S14.
class DeviceIdentity {
  static const _key = 'scope_device_id';

  /// Default options are used deliberately. flutter_secure_storage 11 encrypts
  /// with AES-GCM under an RSA-wrapped key on Android, and uses the Keychain on
  /// iOS, without configuration — the `encryptedSharedPreferences` flag that
  /// earlier versions required was removed because that behaviour is now the
  /// default rather than an opt-in.
  static const _storage = FlutterSecureStorage();

  static String? _cached;

  /// Returns the identifier, creating it on first call.
  static Future<String> get() async {
    if (_cached != null) return _cached!;

    var id = await _storage.read(key: _key);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4().replaceAll('-', '');
      await _storage.write(key: _key, value: id);
    }

    _cached = id;
    return id;
  }
}

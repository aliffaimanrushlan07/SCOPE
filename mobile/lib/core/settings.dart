import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// Runtime-adjustable settings, persisted across launches.
///
/// WHY THIS EXISTS
/// ---------------
/// [AppConfig.defaultApiBaseUrl] is a compile-time constant, which is correct
/// for `flutter run` — the emulator always wants 10.0.2.2 — but wrong for an
/// installed APK. The demonstration runs the backend on a laptop joined to a
/// phone hotspot, and DHCP does not guarantee the same address twice. With a
/// compile-time-only value, every address change would mean rebuilding and
/// re-sideloading the APK minutes before a presentation.
///
/// So the base URL is read from here at request time instead. The compiled-in
/// value remains the default, so nothing changes for the emulator.
///
/// Storage uses [FlutterSecureStorage] to follow the pattern already
/// established by DeviceIdentity, not because a LAN address is a secret.
/// Reusing the dependency avoids adding shared_preferences for a single
/// string.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  /// The single instance. Held statically as well as provided through the
  /// widget tree because [ScopeApi.mediaUrl] is static and is called from
  /// image loaders that have no BuildContext to hand.
  static final AppSettings instance = AppSettings._();

  static const _baseUrlKey = 'scope_api_base_url';
  static const _storage = FlutterSecureStorage();

  String _baseUrl = AppConfig.defaultApiBaseUrl;

  /// The address the app talks to, without a trailing slash and without the
  /// `/api/v1` prefix — that is appended by ApiClient.
  String get baseUrl => _baseUrl;

  /// True when the app is running against the compiled-in default rather than
  /// an address entered on the device.
  bool get isDefault => _baseUrl == AppConfig.defaultApiBaseUrl;

  /// Reads the stored value. Call once, before runApp.
  ///
  /// A failure to read is deliberately not fatal: a corrupt or inaccessible
  /// keystore entry should leave the app running on the default address rather
  /// than refusing to start.
  static Future<void> load() async {
    try {
      final stored = await _storage.read(key: _baseUrlKey);
      if (stored != null && stored.isNotEmpty) {
        instance._baseUrl = stored;
      }
    } on Object catch (error) {
      debugPrint('AppSettings: could not read stored base URL ($error).');
    }
  }

  /// Stores [input] as the base URL, normalising it first.
  ///
  /// Returns the value actually stored, so a caller can show the reader what
  /// their input became.
  Future<String> setBaseUrl(String input) async {
    final normalised = normaliseBaseUrl(input);
    if (normalised == _baseUrl) return normalised;

    _baseUrl = normalised;
    notifyListeners();

    try {
      await _storage.write(key: _baseUrlKey, value: normalised);
    } on Object catch (error) {
      // The in-memory value still applies for this session.
      debugPrint('AppSettings: could not persist base URL ($error).');
    }
    return normalised;
  }

  /// Restores the compiled-in default.
  Future<void> reset() async {
    _baseUrl = AppConfig.defaultApiBaseUrl;
    notifyListeners();
    try {
      await _storage.delete(key: _baseUrlKey);
    } on Object catch (error) {
      debugPrint('AppSettings: could not clear stored base URL ($error).');
    }
  }

  /// Turns what someone actually types into a usable origin.
  ///
  /// Typing a full URL under time pressure on a phone keyboard is exactly the
  /// kind of thing that goes wrong in front of an examiner, so a bare address
  /// is accepted and completed:
  ///
  ///   172.20.10.2            -> http://172.20.10.2:8000
  ///   172.20.10.2:8000       -> http://172.20.10.2:8000
  ///   http://172.20.10.2/    -> http://172.20.10.2
  ///
  /// The default port is only added when no port was given AND no scheme was
  /// given — an explicit `http://host` is left alone, since spelling out the
  /// scheme signals the address was meant literally.
  static String normaliseBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return AppConfig.defaultApiBaseUrl;

    final hasScheme = value.startsWith('http://') || value.startsWith('https://');
    if (!hasScheme) {
      final hasPort = RegExp(r':\d+$').hasMatch(value);
      value = 'http://$value${hasPort ? '' : ':${AppConfig.defaultPort}'}';
    }

    // Trailing slashes would produce '//api/v1' once the prefix is appended.
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

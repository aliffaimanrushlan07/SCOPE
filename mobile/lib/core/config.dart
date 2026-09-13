/// Build-time configuration.
///
/// The API base URL differs by target and is supplied with --dart-define
/// rather than hard-coded, so the same source runs against the emulator, a
/// physical Android handset and an iPhone without edits:
///
///   Emulator (default)
///     flutter run
///
///   Physical device on the same Wi-Fi as the development Mac
///     flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
///
/// Find the Mac's address with: ipconfig getifaddr en0
///
/// Note that this is only the DEFAULT. An installed APK cannot be rebuilt
/// between demonstration sessions, and a hotspot does not hand out the same
/// address twice, so the value in force at runtime comes from [AppSettings]
/// and is editable on the device. See core/settings.dart.
library;

class AppConfig {
  /// The address used until someone overrides it on the device.
  ///
  /// 10.0.2.2 is the Android emulator's alias for the host machine's
  /// loopback. It is NOT reachable from a physical device.
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Assumed when an address is typed on the device without one.
  static const int defaultPort = 8000;

  static const String apiPrefix = '/api/v1';

  /// Section S08: maximum three photographs per report. Enforced here, in the
  /// API, and by a database CHECK constraint.
  static const int maxPhotos = 3;

  /// Section S01: a minimum so the splash does not flicker on a fast device,
  /// a maximum after which Home is shown regardless and handles any failure.
  static const Duration splashMinimum = Duration(milliseconds: 1500);
  static const Duration splashMaximum = Duration(seconds: 5);

  static const Duration requestTimeout = Duration(seconds: 30);

  /// Reachability checks must fail fast. A wrong address should report itself
  /// in seconds — on the splash screen, and on the connection settings screen
  /// where somebody is waiting to find out whether they typed the IP correctly.
  static const Duration pingTimeout = Duration(seconds: 3);

  /// Classification can be slow: up to three images, uploaded and evaluated.
  static const Duration classifyTimeout = Duration(seconds: 60);
}

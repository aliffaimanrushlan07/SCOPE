import 'package:flutter/foundation.dart';

import '../core/config.dart';
import 'scope_api.dart';

/// Whether the backend answered its health check, shared app-wide.
///
/// S01 runs the first check at launch and Home reads the result to decide
/// whether to show its offline banner. Held above the router rather than
/// passed as a route argument, because Home is re-entered with a plain
/// `context.go(Routes.home)` from several screens and would lose it.
class BackendStatus extends ChangeNotifier {
  BackendStatus(this._api);

  final ScopeApi _api;

  bool? _reachable;
  bool _checking = false;

  /// True only after a check has actually failed. Before the first check
  /// there is nothing to warn about.
  bool get isUnreachable => _reachable == false;

  bool get isChecking => _checking;

  /// Pings the configured address and records the outcome.
  ///
  /// Capped at [AppConfig.splashMaximum]: [ScopeApi.ping] times out connect
  /// and receive separately, so an address that accepts the connection but
  /// never answers could otherwise hold the splash past its maximum.
  Future<bool> check() async {
    if (_checking) return _reachable ?? false;

    _checking = true;
    notifyListeners();

    final ok = await _api
        .ping()
        .timeout(AppConfig.splashMaximum, onTimeout: () => false);

    _reachable = ok;
    _checking = false;
    notifyListeners();
    return ok;
  }
}

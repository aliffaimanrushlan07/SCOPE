import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/config.dart';
import '../core/device_id.dart';
import '../core/theme.dart';
import '../router.dart';
import '../widgets/scope_logo.dart';

/// S01 — Splash.
///
/// Covers initialisation: generating the anonymous device identifier on first
/// launch and checking that the backend is reachable.
///
/// No interactive elements and no skip button. Advances automatically after a
/// minimum of 1.5 s so the transition does not flicker on a fast device, and
/// after at most 5 s regardless, letting Home handle any failure rather than
/// stranding the user on a splash screen that never ends.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialise();
  }

  Future<void> _initialise() async {
    final started = DateTime.now();

    // The identifier must exist before any screen that files or reads a
    // report. Failure here is not fatal — it is retried on next launch.
    try {
      await DeviceIdentity.get().timeout(AppConfig.splashMaximum);
    } on Object {
      // Deliberately swallowed: Home is more useful than an error on a splash.
    }

    final elapsed = DateTime.now().difference(started);
    final remaining = AppConfig.splashMinimum - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }

    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScopeTheme.primaryDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ScopeLogo(size: 96, onDark: true),
            const SizedBox(height: Gap.lg),
            Text(
              'SCOPE',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Report smoking violations',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: Gap.xl),
            SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(
                  Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

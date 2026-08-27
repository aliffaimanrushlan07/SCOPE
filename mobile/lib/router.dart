import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/s01_splash.dart';
import 'screens/s02_home.dart';
import 'screens/s04_awareness_hub.dart';
import 'screens/s06_hotspot_map.dart';
import 'screens/s07_guidelines.dart';
import 'screens/s08_capture.dart';
import 'screens/s10_validation.dart';
import 'screens/s11_location.dart';
import 'screens/s13_success.dart';
import 'screens/s14_history.dart';
import 'screens/s15_about.dart';
import 'screens/s16_settings.dart';

/// Route names for all fifteen screens and states.
///
/// Only eleven appear as routes. The other four are surfaces layered over the
/// screen beneath them rather than separate pages, which is what keeps the
/// reporting task in one continuous context:
///
///   S03 Navigation Menu   — popup anchored to the Home logo
///   S05 Infographic Viewer — floating overlay
///   S09 Photo Review       — modal sheet over S08
///   S12 Report Review      — modal sheet over S11
///
/// S13 is the exception: it is presented as a sheet but is also a route, so
/// the reporting stack can be torn down beneath it. Once submission is
/// confirmed the draft is gone, and no back gesture may return into the flow.
class Routes {
  Routes._();

  static const splash = '/';
  static const home = '/home';
  static const awarenessHub = '/awareness';
  static const hotspotMap = '/hotspots';
  static const guidelines = '/guidelines';
  static const capture = '/report/capture';
  static const validation = '/report/validation';
  static const location = '/report/location';
  static const success = '/report/success';
  static const history = '/history';
  static const about = '/about';

  /// Not one of the fifteen. A demonstration affordance reached only from
  /// About — see screens/s16_settings.dart.
  static const settings = '/settings';
}

final GoRouter appRouter = GoRouter(
  initialLocation: Routes.splash,
  routes: [
    GoRoute(
      path: Routes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: Routes.awarenessHub,
      builder: (context, state) => const AwarenessHubScreen(),
    ),
    GoRoute(
      path: Routes.hotspotMap,
      builder: (context, state) => const HotspotMapScreen(),
    ),
    GoRoute(
      path: Routes.guidelines,
      builder: (context, state) => const GuidelinesScreen(),
    ),
    GoRoute(
      path: Routes.capture,
      builder: (context, state) => const CaptureScreen(),
    ),
    GoRoute(
      path: Routes.validation,
      builder: (context, state) => const ValidationScreen(),
    ),
    GoRoute(
      path: Routes.location,
      builder: (context, state) => const LocationTaggingScreen(),
    ),
    GoRoute(
      path: Routes.success,
      builder: (context, state) => SubmissionSuccessScreen(
        referenceNo: state.uri.queryParameters['ref'] ?? '',
      ),
    ),
    GoRoute(
      path: Routes.history,
      builder: (context, state) => const ReportHistoryScreen(),
    ),
    GoRoute(
      path: Routes.about,
      builder: (context, state) => const AboutScreen(),
    ),
    GoRoute(
      path: Routes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Page not found')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('That screen does not exist.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(Routes.home),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    ),
  ),
);

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/settings.dart';
import 'core/theme.dart';
import 'models/report_draft.dart';
import 'router.dart';
import 'services/backend_status.dart';
import 'services/scope_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before runApp, not after: S01 pings the backend almost immediately, and
  // pinging the compiled-in default before the stored address had loaded would
  // show the app as offline on every launch.
  await AppSettings.load();

  // Reporting is a one-handed task performed discreetly, often while standing.
  // Locking to portrait removes a whole class of layout states nobody needs.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ScopeApp());
}

class ScopeApp extends StatelessWidget {
  const ScopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ScopeApi>(create: (_) => ScopeApi()),
        // Written by S01's launch check, read by Home's offline banner.
        ChangeNotifierProvider<BackendStatus>(
          create: (context) => BackendStatus(context.read<ScopeApi>()),
        ),
        // Already loaded in main, and also reachable statically for callers
        // without a BuildContext. Provided here so the settings screen and the
        // About entry rebuild when the address changes.
        ChangeNotifierProvider<AppSettings>.value(value: AppSettings.instance),
        // One draft for the whole app. Held above the router so it survives
        // navigation between S08 and S12.
        ChangeNotifierProvider<ReportDraft>(create: (_) => ReportDraft()),
      ],
      child: MaterialApp.router(
        title: 'SCOPE',
        debugShowCheckedModeBanner: false,
        theme: ScopeTheme.light(),
        routerConfig: appRouter,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'models/report_draft.dart';
import 'router.dart';
import 'services/scope_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

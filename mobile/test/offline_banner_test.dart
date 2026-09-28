import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scope/screens/s02_home.dart';
import 'package:scope/services/backend_status.dart';
import 'package:scope/services/scope_api.dart';

/// A ping whose answer the test controls.
class _FakeApi extends ScopeApi {
  bool reachable = false;

  @override
  Future<bool> ping({String? baseUrl}) async => reachable;
}

/// Widget tests for Home's offline banner, driven by the S01 launch check.
void main() {
  late _FakeApi api;
  late BackendStatus status;

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: status,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
  }

  final banner = find.textContaining("Can't reach the SCOPE server");

  setUp(() {
    api = _FakeApi();
    status = BackendStatus(api);
  });

  testWidgets('is hidden before any check has run', (tester) async {
    await pumpHome(tester);

    expect(banner, findsNothing);
  });

  testWidgets('is hidden when the backend answered', (tester) async {
    api.reachable = true;
    await status.check();
    await pumpHome(tester);

    expect(banner, findsNothing);
  });

  testWidgets('shows when the launch check failed', (tester) async {
    await status.check();
    await pumpHome(tester);

    expect(banner, findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('clears on a successful retry', (tester) async {
    await status.check();
    await pumpHome(tester);

    api.reachable = true;
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(banner, findsNothing);
  });
}

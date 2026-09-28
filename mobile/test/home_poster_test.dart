import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scope/screens/s02_home.dart';
import 'package:scope/services/backend_status.dart';
import 'package:scope/services/scope_api.dart';

/// Widget tests for the S02 poster.
///
/// The poster is artwork drawn at a fixed 1200 × 630 and scaled with
/// BoxFit.cover, so the box it lands in decides how much of it survives. These
/// pin that box: 190 tall on every device and the full width less the screen's
/// 16 px gutters. docs/home-poster-prompt.md derives the canvas from exactly
/// these numbers, and if they drift the artwork is cropped somewhere the prompt
/// says is safe.
void main() {
  // Matched on the directory, not the filename: the header logo is an asset
  // image too, and the poster's own format is allowed to change.
  final poster = find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage)
            .assetName
            .startsWith('assets/poster/'),
    description: 'the Home poster',
  );

  String assetOf(WidgetTester tester) =>
      (tester.widget<Image>(poster).image as AssetImage).assetName;

  Future<Size> pumpHome(
    WidgetTester tester,
    Size screen, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        // Never checked, so the offline banner stays out of the layout.
        child: ChangeNotifierProvider(
          create: (_) => BackendStatus(ScopeApi()),
          child: const MaterialApp(home: HomeScreen()),
        ),
      ),
    );

    return tester.getSize(
      find.ancestor(of: poster, matching: find.byType(ClipRRect)).first,
    );
  }

  testWidgets('is 190 tall and gutter-to-gutter on a narrow phone',
      (tester) async {
    expect(await pumpHome(tester, const Size(360, 780)),
        const Size(360 - 32, 190));
  });

  testWidgets('keeps the same height on a wide phone', (tester) async {
    expect(await pumpHome(tester, const Size(430, 932)),
        const Size(430 - 32, 190));
  });

  testWidgets('crops rather than letterboxes', (tester) async {
    await pumpHome(tester, const Size(390, 844));

    expect(tester.widget<Image>(poster).fit, BoxFit.cover);
  });

  testWidgets('animates by default', (tester) async {
    await pumpHome(tester, const Size(390, 844));

    expect(assetOf(tester), 'assets/poster/home-poster.webp');
  });

  testWidgets('falls back to the still frame under reduced motion',
      (tester) async {
    await pumpHome(tester, const Size(390, 844), reduceMotion: true);

    // The looping reticle and smoke plume have no pause control, so the
    // platform's own motion setting is the opt-out (WCAG 2.2.2).
    expect(assetOf(tester), 'assets/poster/home-poster-still.png');
  });

  testWidgets('no longer pages through the awareness slots', (tester) async {
    await pumpHome(tester, const Size(390, 844));

    // No carousel and none of the pagination dots it drew. Home reaches the
    // infographics through the Hub button now.
    expect(poster, findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.text('Awareness Hub'), findsOneWidget);
  });
}

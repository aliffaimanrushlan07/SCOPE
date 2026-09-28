import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/theme.dart';
import 'package:scope/screens/s07_guidelines.dart';

/// Widget tests for the S07 swipe deck.
///
/// Pinned: safety is the first card, the deck can be walked end to end with
/// the buttons, Skip lands on "what happens next" rather than leaving, and the
/// pixel officer stops animating under reduce-motion.
void main() {
  Future<void> pumpDeck(
    WidgetTester tester, {
    Size screen = const Size(390, 844),
    bool reduceMotion = true,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: screen, disableAnimations: reduceMotion),
        child: MaterialApp(
          theme: ScopeTheme.light(),
          home: const GuidelinesScreen(),
        ),
      ),
    );
  }

  // The deck's own page and colour transitions are finite; only the officer
  // loops, and reduce-motion (the default here) holds it still.
  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the safety card', (tester) async {
    await pumpDeck(tester);
    expect(find.text('Your safety comes first'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets('Next walks all five cards and ends on Got it', (tester) async {
    await pumpDeck(tester);
    const headings = [
      'Show the ember',
      'You stay anonymous',
      'What happens next',
    ];

    await tapAndSettle(tester, find.text('Next'));
    expect(
      find.textContaining('cigarette in a no‑smoking place'),
      findsOneWidget,
    );
    for (final heading in headings) {
      await tapAndSettle(tester, find.text('Next'));
      expect(find.text(heading), findsOneWidget);
    }

    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);

    await tapAndSettle(tester, find.byIcon(Icons.chevron_left));
    expect(find.text('You stay anonymous'), findsOneWidget);
  });

  testWidgets('Skip jumps to what happens next', (tester) async {
    await pumpDeck(tester);
    await tapAndSettle(tester, find.text('Skip'));
    expect(find.text('What happens next'), findsOneWidget);
    expect(find.text('You get a reference no.'), findsOneWidget);
  });

  testWidgets('every card lays out on a small phone', (tester) async {
    await pumpDeck(tester, screen: const Size(320, 568));
    for (var i = 0; i < 4; i++) {
      await tapAndSettle(tester, find.text('Next'));
    }
    expect(find.text('Got it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('officer animates, but holds still under reduce-motion', (
    tester,
  ) async {
    await pumpDeck(tester, reduceMotion: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await pumpDeck(tester);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

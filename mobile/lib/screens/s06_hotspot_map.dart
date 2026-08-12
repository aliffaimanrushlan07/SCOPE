import 'package:flutter/material.dart';

import '../widgets/not_yet_built.dart';

/// S06 — Smoking Violation Hotspot Map (view-only).
///
/// Renders a density heatmap of previously reported violations across Kuala
/// Lumpur, never individual pins: showing pins would publicly attribute a
/// report to a named premise, which matters for both reporter safety and
/// defamation exposure.
///
/// There is deliberately no reporting entry point from this screen.
class HotspotMapScreen extends StatelessWidget {
  const HotspotMapScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotYetBuilt(
        screenId: 'S06',
        title: 'Hotspot Map',
        sprint: 'Sprint 4',
        description:
            'A density heatmap of reported violations across Kuala Lumpur.\n\n'
            'Needs the Google Maps Android API key, which requires a Google '
            'Cloud billing account.',
      );
}

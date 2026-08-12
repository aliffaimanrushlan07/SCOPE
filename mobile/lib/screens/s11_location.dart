import 'package:flutter/material.dart';

import '../widgets/not_yet_built.dart';

/// S11 — Location Tagging.
///
/// Interactive map with a current-location button, a draggable pin, premise
/// search, and a reverse-geocoded address readout so the reporter confirms
/// what was actually tagged. Defaults the pin to the coordinates recorded at
/// capture (S08).
///
/// If location permission is denied, search-only mode still works — a denial
/// must never block the report.
class LocationTaggingScreen extends StatelessWidget {
  const LocationTaggingScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotYetBuilt(
        screenId: 'S11',
        title: 'Tag the location',
        sprint: 'Sprint 4',
        description:
            'Map with draggable pin, premise search and address readout.\n\n'
            'Needs the Google Maps Android API key.',
      );
}

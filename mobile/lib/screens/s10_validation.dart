import 'package:flutter/material.dart';

import '../widgets/not_yet_built.dart';

/// S10 — AI Photo Evidence Validation.
///
/// Two states on one route: verifying, then the result. A report proceeds when
/// at least one photograph clears the threshold; photographs that fail are
/// dropped automatically and the reporter is told which and why. Only a total
/// failure returns to S08.
///
/// No back action while a request is in flight, so the model is never called
/// twice for the same photograph.
class ValidationScreen extends StatelessWidget {
  const ValidationScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotYetBuilt(
        screenId: 'S10',
        title: 'Verifying evidence',
        sprint: 'Sprint 4',
        description:
            'Submits photos to the classification endpoint and shows the '
            'per-photo confidence result.\n\n'
            'The backend endpoint is already built and passing its tests.',
      );
}

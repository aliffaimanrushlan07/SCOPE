import 'package:flutter/material.dart';

import '../widgets/not_yet_built.dart';

/// S13 — Submission Success.
///
/// Presented as a floating sheet carrying the report reference number with a
/// copy button. Because reporting is anonymous and history is device-bound,
/// that number is the reporter's only durable handle on the submission.
///
/// The wording matters: the report becomes visible to enforcement officers on
/// the monitoring dashboard. It is NOT "under review" — nothing reviews it.
///
/// Neither action may return into the reporting flow; the draft is cleared
/// once submission is confirmed.
class SubmissionSuccessScreen extends StatelessWidget {
  const SubmissionSuccessScreen({super.key, required this.referenceNo});

  final String referenceNo;

  @override
  Widget build(BuildContext context) => const NotYetBuilt(
        screenId: 'S13',
        title: 'Report submitted',
        sprint: 'Sprint 4',
        description:
            'Success sheet with the copyable reference number and routes to '
            'Home or Report History.',
      );
}

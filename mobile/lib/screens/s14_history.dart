import 'package:flutter/material.dart';

import '../widgets/not_yet_built.dart';

/// S14 — Report History.
///
/// A receipt log keyed to the anonymous device identifier, newest first. There
/// is deliberately NO status badge: evidence is validated before submission
/// and administrators are read-only, so nothing can change a report's state
/// after filing. A badge would advertise a workflow that does not exist.
///
/// The empty state says plainly that history does not survive a reinstall — a
/// user who loses it without warning would read that as a bug.
class ReportHistoryScreen extends StatelessWidget {
  const ReportHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotYetBuilt(
        screenId: 'S14',
        title: 'Report History',
        sprint: 'Sprint 4',
        description:
            'Reports filed from this device, newest first, with reference '
            'number and thumbnail.\n\n'
            'The backend endpoint is already built and passing its tests.',
      );
}

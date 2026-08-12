import 'package:flutter/material.dart';

import '../core/theme.dart';

/// S07 — Reporting Guidelines.
///
/// Static content: what counts as a reportable violation, what makes valid
/// photographic evidence, safety advice, the privacy position, and what
/// happens after submission.
///
/// The safety section is first on purpose. The reporter may be standing next
/// to the person they are reporting, and "do not confront" is the single most
/// important thing this screen says.
class GuidelinesScreen extends StatelessWidget {
  const GuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reporting Guidelines')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: const [
          _SafetyCallout(),
          SizedBox(height: Gap.lg),
          _Section(
            icon: Icons.smoking_rooms_outlined,
            title: 'What you can report',
            points: [
              'Someone smoking inside a gazetted non-smoking premise.',
              'Common examples: restaurants and cafés, air-conditioned premises, '
                  'shopping malls, hospitals and clinics, schools and colleges, '
                  'public transport hubs and stations.',
              'The cigarette must be lit. A person merely holding an unlit '
                  'cigarette or a vape is not a smoking violation under Act 852.',
            ],
          ),
          _Section(
            icon: Icons.photo_camera_outlined,
            title: 'What makes valid photo evidence',
            points: [
              'The lit cigarette must be visible in the frame.',
              'Get close enough that the cigarette is not just a distant speck, '
                  'but never so close that you put yourself at risk.',
              'Hold steady — a blurred photo will be rejected by the evidence '
                  'check before you can submit it.',
              'You may attach up to three photos. Only the photos that pass the '
                  'evidence check are kept.',
            ],
          ),
          _Section(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy',
            points: [
              'Your report is anonymous. SCOPE does not ask for your name, phone '
                  'number, email or any account, and does not record who you are.',
              'Avoid photographing bystanders, children, or anything showing '
                  'someone\'s identity documents or vehicle plate where it is not '
                  'needed as evidence.',
              'Your photos and the location you tag are stored securely and are '
                  'visible only to authorised enforcement officers.',
            ],
          ),
          _Section(
            icon: Icons.task_alt_outlined,
            title: 'What happens after you submit',
            points: [
              'Your photo evidence is checked automatically before the report is '
                  'filed, so only reports with genuine evidence are submitted.',
              'You receive a reference number. Keep it — because reporting is '
                  'anonymous, it is your only durable record of the submission.',
              'Your report becomes visible to enforcement officers on their '
                  'monitoring dashboard, where it informs where they patrol.',
              'SCOPE cannot tell you whether enforcement acted on your report. '
                  'There is no status to follow, and no one will contact you.',
            ],
          ),
        ],
      ),
    );
  }
}

class _SafetyCallout extends StatelessWidget {
  const _SafetyCallout();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: ScopeTheme.warning.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ScopeTheme.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: ScopeTheme.warning),
          SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your safety comes first',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: Gap.sm),
                Text(
                  'Do not confront the person you are reporting. Do not argue, '
                  'and do not photograph anyone in a way that draws attention to '
                  'you. If you feel unsafe, leave — no report is worth your '
                  'safety. SCOPE exists so that you never have to intervene in '
                  'person.',
                  style: TextStyle(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.points,
  });

  final IconData icon;
  final String title;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ScopeTheme.primary, size: 22),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          ...points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm, left: Gap.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: Gap.sm),
                    child: SizedBox(
                      width: 5,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ScopeTheme.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(point, style: const TextStyle(height: 1.45)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

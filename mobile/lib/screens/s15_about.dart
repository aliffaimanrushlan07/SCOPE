import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../router.dart';
import '../widgets/scope_logo.dart';

/// S15 — About SCOPE.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Kept in step with the version line in pubspec.yaml (1.0.0+1).
  static const String _version = '1.0.0';
  static const String _build = '1';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About SCOPE')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          const Center(
            child: Column(
              children: [
                SizedBox(height: Gap.md),
                ScopeLogo(size: 72),
                SizedBox(height: Gap.md),
                Text(
                  'SCOPE',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                SizedBox(height: Gap.xs),
                Text(
                  'AI-Assisted Smoking Violation\nReporting and Monitoring System',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ScopeTheme.inkMuted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          const _Block(
            title: 'What SCOPE is for',
            body:
                'Smoking in gazetted non-smoking premises is difficult to enforce '
                'because violations are brief and enforcement officers cannot be '
                'everywhere. Reporting one in person can also mean confronting a '
                'stranger, which many people are unwilling to do.\n\n'
                'SCOPE lets you report a violation anonymously with photo '
                'evidence and a tagged location. Reports are aggregated into '
                'hotspot data that helps enforcement officers decide where to '
                'patrol, rather than relying on reactive, uncoordinated '
                'schedules.',
          ),
          const _Block(
            title: 'Your anonymity',
            body:
                'SCOPE does not have accounts, and does not ask for your name, '
                'phone number or email. No identifier on your report can be '
                'traced back to you.\n\n'
                'Because of that, your report history is stored only on this '
                'device. If you reinstall SCOPE or change phone, your history '
                'will be empty — the reports remain filed, but this app can no '
                'longer show them to you. Keep your reference numbers.',
          ),
          const _Block(
            title: 'How evidence is checked',
            body:
                'Your photos are checked automatically by an AI model before the '
                'report is filed. Photos without clear evidence of a lit '
                'cigarette are not submitted, and you are told why so you can '
                'retake them.\n\n'
                'This check happens before submission, so the report an officer '
                'sees is the report you filed — unchanged.',
          ),
          const _Block(
            title: 'Project',
            body:
                'Developed as a Final Year Project for the Bachelor of '
                'Information Technology (Hons) in Computer Application '
                'Development, in collaboration with the National Cancer Society '
                'Malaysia (NCSM).',
          ),
          const SizedBox(height: Gap.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                children: [
                  _InfoRow(label: 'Version', value: _version),
                  const SizedBox(height: Gap.sm),
                  _InfoRow(label: 'Build', value: _build),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.md),

          // The only entry point to the connection settings, and deliberately
          // the least prominent place in the app — it is a demonstration
          // affordance, not something a reporter should ever need.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_ethernet,
                color: ScopeTheme.inkMuted),
            title: const Text('Connection settings'),
            subtitle: Text(
              context.watch<AppSettings>().baseUrl,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.settings),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Gap.sm),
          Text(body, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: ScopeTheme.inkMuted)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

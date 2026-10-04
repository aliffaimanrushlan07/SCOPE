import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../router.dart';

/// S13 — Submission Success.
///
/// Two things on this screen carry weight beyond confirmation.
///
/// The REFERENCE NUMBER is the reporter's only durable handle on the
/// submission. Reporting is anonymous and history is device-bound, so if the
/// app is reinstalled this number is all that remains. It is large, copyable,
/// and the screen says why it matters.
///
/// The WORDING of what happens next is deliberate: the report becomes visible
/// to enforcement officers on their monitoring dashboard. It is NOT "under
/// review" and it will NOT "be reviewed" — administrators hold read-only
/// access and nothing in the system adjudicates a filed report. Promising
/// review the system does not perform is precisely the gap an examiner looks
/// for.
///
/// Neither action returns into the reporting flow: the draft was cleared when
/// submission was confirmed.
class SubmissionSuccessScreen extends StatelessWidget {
  const SubmissionSuccessScreen({super.key, required this.referenceNo});

  final String referenceNo;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back must not re-enter the reporting flow. The draft no longer exists.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(Routes.home);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(Gap.md),
                  children: [
                    const SizedBox(height: Gap.xl),
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ScopeTheme.success.withValues(alpha: 0.12),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 54,
                          color: ScopeTheme.success,
                        ),
                      ),
                    ),
                    const SizedBox(height: Gap.lg),
                    const Text(
                      'Report successfully submitted',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: Gap.xl),
                    _ReferenceBlock(referenceNo: referenceNo),
                    const SizedBox(height: Gap.lg),
                    Container(
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        color: ScopeTheme.surfaceMuted,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: ScopeTheme.inkMuted),
                          SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(
                              'Your report is now visible to enforcement '
                              'officers on their monitoring dashboard, where it '
                              'helps them decide where to patrol.\n\n'
                              'SCOPE cannot tell you whether enforcement acted '
                              'on it, and no one will contact you.',
                              style: TextStyle(
                                height: 1.5,
                                color: ScopeTheme.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: () => context.go(Routes.home),
                      child: const Text('Back to home'),
                    ),
                    const SizedBox(height: Gap.sm),
                    OutlinedButton(
                      onPressed: () {
                        // go() alone would leave History as the only page, with
                        // no way back; put Home underneath it first.
                        context.go(Routes.home);
                        context.push(Routes.history);
                      },
                      child: const Text('View report history'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceBlock extends StatelessWidget {
  const _ReferenceBlock({required this.referenceNo});

  final String referenceNo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: ScopeTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ScopeTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'Your reference number',
            style: TextStyle(fontSize: 13, color: ScopeTheme.inkMuted),
          ),
          const SizedBox(height: Gap.sm),
          SelectableText(
            referenceNo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: referenceNo));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reference number copied')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy reference number'),
          ),
          const SizedBox(height: Gap.sm),
          const Text(
            'Keep this number. Because your report is anonymous, it is the '
            'only way to refer to this submission — and it will be lost if you '
            'reinstall the app.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: ScopeTheme.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/device_id.dart';
import '../core/theme.dart';
import '../models/report_draft.dart';
import '../router.dart';
import '../services/scope_api.dart';

/// S12 — Report Review.
///
/// A floating sheet over the location screen, showing the complete draft
/// before submission: the validated photographs with their confidence scores,
/// the tagged location, the date and time, an optional free-text premise name,
/// and a plain statement that the report is anonymous.
///
/// There is no violation type and no premise-type dropdown. The reporter
/// supplies a premise NAME or nothing at all — free text, never a category,
/// and never used for aggregation, because free text from an unidentified
/// reporter cannot support reliable grouping.
Future<void> showReportReviewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    builder: (_) => const _ReportReviewSheet(),
  );
}

class _ReportReviewSheet extends StatefulWidget {
  const _ReportReviewSheet();

  @override
  State<_ReportReviewSheet> createState() => _ReportReviewSheetState();
}

class _ReportReviewSheetState extends State<_ReportReviewSheet> {
  late final TextEditingController _premiseController;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _premiseController = TextEditingController(
      text: context.read<ReportDraft>().premiseName ?? '',
    );
  }

  @override
  void dispose() {
    _premiseController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Guards the duplicate-tap case in section 7 on the client side; the
    // backend's idempotency handling is the real protection.
    if (_submitting) return;

    final draft = context.read<ReportDraft>();
    final api = context.read<ScopeApi>();
    final classification = draft.classification;

    if (classification == null || !draft.hasLocation) {
      setState(() => _error = 'This report is incomplete.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final deviceId = await DeviceIdentity.get();
      final result = await api.submitReport(
        validationToken: classification.validationToken,
        deviceId: deviceId,
        latitude: draft.latitude!,
        longitude: draft.longitude!,
        reportedAt: draft.reportedAt,
        premiseName: _premiseController.text,
        addressText: draft.addressText,
        captureLatitude: draft.captureLatitude,
        captureLongitude: draft.captureLongitude,
        idempotencyKey: draft.idempotencyKey,
      );

      // The draft is cleared before navigating: once submission is confirmed
      // no back gesture may return the reporter into the flow.
      await draft.clear();

      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('${Routes.success}?ref=${result.referenceNo}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // The draft is deliberately NOT cleared: section 7 requires the report
        // to survive a failed submit so the reporter can retry.
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ReportDraft>();
    final classification = draft.classification;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Review your report',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(Gap.md),
              children: [
                const _SectionLabel('Photo evidence'),
                const SizedBox(height: Gap.sm),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: draft.photoCount,
                    separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
                    itemBuilder: (context, index) {
                      final score = classification?.photos
                          .where((p) => p.passed)
                          .elementAtOrNull(index)
                          ?.confidence;
                      return _EvidenceThumb(
                        path: draft.photos[index].path,
                        confidence: score,
                      );
                    },
                  ),
                ),
                const SizedBox(height: Gap.lg),

                const _SectionLabel('Location'),
                const SizedBox(height: Gap.sm),
                _InfoTile(
                  icon: Icons.place_outlined,
                  title: draft.addressText ?? 'Address unavailable',
                  subtitle: '${draft.latitude?.toStringAsFixed(5)}, '
                      '${draft.longitude?.toStringAsFixed(5)}',
                ),
                const SizedBox(height: Gap.md),

                TextField(
                  controller: _premiseController,
                  enabled: !_submitting,
                  maxLength: 150,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Premise name (optional)',
                    hintText: 'e.g. Restoran Nasi Kandar, Level 2 food court',
                    helperText:
                        'Helps officers find the exact place. Leave blank if '
                        'you are not sure.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: Gap.md),

                const _SectionLabel('Report details'),
                const SizedBox(height: Gap.sm),
                _InfoTile(
                  icon: Icons.schedule_outlined,
                  title: DateFormat('d MMM yyyy, h:mm a')
                      .format(draft.reportedAt.toLocal()),
                  subtitle: 'Date and time of this report',
                ),
                const SizedBox(height: Gap.sm),
                // Anonymity stated as a plain line of text, per the
                // specification — not a badge or a toggle, because it is not a
                // choice the reporter makes. It is how the system works.
                const _InfoTile(
                  icon: Icons.visibility_off_outlined,
                  title: 'Reported anonymously',
                  subtitle:
                      'No name, phone number or email is attached to this '
                      'report.',
                ),

                if (_error != null) ...[
                  const SizedBox(height: Gap.md),
                  Container(
                    padding: const EdgeInsets.all(Gap.md),
                    decoration: BoxDecoration(
                      color: ScopeTheme.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: ScopeTheme.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: ScopeTheme.danger, size: 20),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_error!,
                                  style: const TextStyle(height: 1.4)),
                              const SizedBox(height: Gap.xs),
                              const Text(
                                'Your report has been kept — you can try again.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: ScopeTheme.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              Gap.md,
              Gap.md,
              Gap.md,
              MediaQuery.of(context).padding.bottom + Gap.md,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ScopeTheme.lineSoft)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit report'),
                ),
                const SizedBox(height: Gap.sm),
                OutlinedButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Back to location tagging'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );
}

class _EvidenceThumb extends StatelessWidget {
  const _EvidenceThumb({required this.path, this.confidence});

  final String path;
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Image.file(File(path), width: 108, height: 132, fit: BoxFit.cover),
          if (confidence != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                color: Colors.black.withValues(alpha: 0.65),
                child: Text(
                  '${(confidence! * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: ScopeTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: ScopeTheme.primary),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, height: 1.35)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: ScopeTheme.inkMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

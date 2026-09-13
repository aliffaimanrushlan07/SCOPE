import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/api_models.dart';
import '../models/report_draft.dart';
import '../router.dart';
import '../services/scope_api.dart';

/// S10 — AI Photo Evidence Validation.
///
/// Four states on one route: verifying, pass, fail, and error.
///
/// The distinction between FAIL and ERROR is the important one and is easy to
/// get wrong. A photograph that the model judged inadequate is a FAIL and the
/// reporter should retake it. A network drop or a service timeout is an ERROR:
/// the photograph was probably fine, nothing was judged, and the reporter
/// should retry rather than be sent back to retake valid evidence. Collapsing
/// the two would tell people to redo work that was never wrong.
enum _Stage { verifying, passed, failed, error }

class ValidationScreen extends StatefulWidget {
  const ValidationScreen({super.key});

  @override
  State<ValidationScreen> createState() => _ValidationScreenState();
}

class _ValidationScreenState extends State<ValidationScreen> {
  _Stage _stage = _Stage.verifying;
  ClassificationResult? _result;
  String _errorMessage = '';
  bool _errorRetryable = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _validate());
  }

  Future<void> _validate() async {
    final draft = context.read<ReportDraft>();
    final api = context.read<ScopeApi>();

    if (!draft.hasPhotos) {
      if (mounted) context.pop();
      return;
    }

    setState(() => _stage = _Stage.verifying);

    try {
      final result = await api.classify(draft.photos);

      // Applying the verdict drops the photographs that failed, so this must
      // happen before the result is rendered.
      await draft.applyClassification(result);

      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = result.passed ? _Stage.passed : _Stage.failed;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = e.message;
        _errorRetryable = e.isRetryable;
      });
    }
  }

  void _backToCapture() {
    // S08 is still on the stack beneath this route.
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // No back action while a request is in flight, so the model is never
      // called twice for the same photograph.
      canPop: _stage != _Stage.verifying,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: _stage != _Stage.verifying,
          title: Text(switch (_stage) {
            _Stage.verifying => 'Verifying evidence',
            _Stage.passed => 'Evidence verified',
            _Stage.failed => 'Retake needed',
            _Stage.error => 'Could not verify',
          }),
        ),
        body: SafeArea(
          child: switch (_stage) {
            _Stage.verifying => _VerifyingState(
                photoCount: context.read<ReportDraft>().photoCount,
              ),
            _Stage.passed => _PassedState(
                result: _result!,
                onProceed: () => context.push(Routes.location),
              ),
            _Stage.failed => _FailedState(
                result: _result!,
                onRetake: _backToCapture,
              ),
            _Stage.error => _ErrorState(
                message: _errorMessage,
                canRetry: _errorRetryable,
                onRetry: _validate,
                onBack: _backToCapture,
              ),
          },
        ),
      ),
    );
  }
}

/// State A — verifying.
class _VerifyingState extends StatelessWidget {
  const _VerifyingState({required this.photoCount});

  final int photoCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PulsingRobot(),
            const SizedBox(height: Gap.xl),
            const Text(
              'Verifying the photo evidence',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              photoCount == 1
                  ? 'Checking your photo'
                  : 'Checking $photoCount photos',
              style: const TextStyle(color: ScopeTheme.inkMuted),
            ),
            const SizedBox(height: Gap.xl),
            const SizedBox(
              width: 160,
              child: LinearProgressIndicator(minHeight: 3),
            ),
            const SizedBox(height: Gap.xl),
            const Text(
              'This usually takes a few seconds. Please keep the app open.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ScopeTheme.inkMuted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingRobot extends StatefulWidget {
  const _PulsingRobot();

  @override
  State<_PulsingRobot> createState() => _PulsingRobotState();
}

class _PulsingRobotState extends State<_PulsingRobot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1.06).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ScopeTheme.primary.withValues(alpha: 0.1),
        ),
        child: const Icon(
          Icons.smart_toy_outlined,
          size: 52,
          color: ScopeTheme.primary,
        ),
      ),
    );
  }
}

/// State B — pass.
class _PassedState extends StatelessWidget {
  const _PassedState({required this.result, required this.onProceed});

  final ClassificationResult result;
  final VoidCallback onProceed;

  @override
  Widget build(BuildContext context) {
    final dropped = result.failedPhotos;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              const _Banner(
                icon: Icons.verified_outlined,
                colour: ScopeTheme.success,
                title: 'Evidence verified',
                message: 'A lit cigarette was detected in your photo evidence.',
              ),
              const SizedBox(height: Gap.lg),
              // Indexed by position among the PASSING photos, not by the
              // verdict index. applyClassification has already removed the
              // failures from the draft, preserving order, so the k-th passing
              // photo now sits at draft.photos[k]. Using photo.index here
              // reads past the end of the shortened list.
              ...result.photos
                  .where((p) => p.passed)
                  .toList()
                  .asMap()
                  .entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: _ConfidenceRow(
                        photo: entry.value,
                        draftIndex: entry.key,
                      ),
                    ),
                  ),

              // Failing photographs are dropped automatically, but the reporter
              // is told which and why. Removing evidence silently would be the
              // wrong trade: they should know what their report now contains.
              if (dropped.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                Container(
                  padding: const EdgeInsets.all(Gap.md),
                  decoration: BoxDecoration(
                    color: ScopeTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dropped.length == 1
                            ? '1 photo was not included'
                            : '${dropped.length} photos were not included',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: Gap.xs),
                      const Text(
                        'You do not need to retake them — your report will be '
                        'filed with the photos that passed.',
                        style: TextStyle(
                          color: ScopeTheme.inkMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: Gap.sm),
                      ...dropped.map(
                        (photo) => Padding(
                          padding: const EdgeInsets.only(top: Gap.xs),
                          child: Row(
                            children: [
                              const Icon(Icons.remove_circle_outline,
                                  size: 18, color: ScopeTheme.inkMuted),
                              const SizedBox(width: Gap.sm),
                              Expanded(
                                child: Text(
                                  'Photo ${photo.index + 1}: '
                                  '${photo.reason ?? 'did not pass'}',
                                  style: const TextStyle(
                                      color: ScopeTheme.inkMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: FilledButton(
            onPressed: onProceed,
            child: const Text('Proceed to location tagging'),
          ),
        ),
      ],
    );
  }
}

/// State B — fail. Reached only when NO photograph cleared the threshold.
class _FailedState extends StatelessWidget {
  const _FailedState({required this.result, required this.onRetake});

  final ClassificationResult result;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              const _Banner(
                icon: Icons.error_outline,
                colour: ScopeTheme.warning,
                title: 'You need to retake the photo',
                message:
                    'No lit cigarette could be confirmed in your evidence, so '
                    'this report cannot be filed yet.',
              ),
              const SizedBox(height: Gap.lg),
              // The reason per photograph makes the retake actionable: "too
              // blurry" and "subject too far" call for different fixes.
              // On a total failure nothing is dropped from the draft, so the
              // verdict index still addresses the right photograph.
              ...result.photos.map(
                (photo) => Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: _ConfidenceRow(
                    photo: photo,
                    draftIndex: photo.index,
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              Container(
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  color: ScopeTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tips for a photo that passes',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: Gap.sm),
                    Text(
                      '• Make sure the lit cigarette is visible in the frame.\n'
                      '• Get closer if the person is far away — but stay safe '
                      'and do not approach them.\n'
                      '• Hold the phone steady for a moment before tapping.',
                      style: TextStyle(height: 1.5, color: ScopeTheme.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: FilledButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.photo_camera_rounded, size: 20),
            label: const Text('Retake photo'),
          ),
        ),
      ],
    );
  }
}

/// Error — a transport failure, NOT a verdict on the evidence.
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.canRetry,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 56, color: ScopeTheme.inkMuted),
            const SizedBox(height: Gap.md),
            const Text(
              'Could not check your photos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ScopeTheme.inkMuted, height: 1.45),
            ),
            const SizedBox(height: Gap.md),
            // Said explicitly: the reporter has not been told their evidence is
            // bad, and their photographs are still held.
            const Text(
              'Your photos have not been rejected and are still saved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ScopeTheme.inkMuted, height: 1.45),
            ),
            const SizedBox(height: Gap.lg),
            if (canRetry)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try again'),
              ),
            const SizedBox(height: Gap.sm),
            OutlinedButton(
              onPressed: onBack,
              child: const Text('Back to photos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.colour,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colour, size: 26),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Text(message, style: const TextStyle(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One photograph with its confidence score.
class _ConfidenceRow extends StatelessWidget {
  const _ConfidenceRow({required this.photo, required this.draftIndex});

  final PhotoVerdict photo;

  /// Position of this photograph in the draft AFTER the verdict was applied.
  /// See the call sites: it is not always `photo.index`.
  final int draftIndex;

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ReportDraft>();
    final file = draftIndex < draft.photoCount
        ? File(draft.photos[draftIndex].path)
        : null;

    final colour = photo.passed ? ScopeTheme.success : ScopeTheme.warning;

    return Container(
      padding: const EdgeInsets.all(Gap.sm),
      decoration: BoxDecoration(
        color: ScopeTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 62,
              height: 62,
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover)
                  : Container(
                      color: Colors.black12,
                      child: const Icon(Icons.image_not_supported_outlined,
                          color: ScopeTheme.inkMuted),
                    ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      photo.passed
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      size: 18,
                      color: colour,
                    ),
                    const SizedBox(width: Gap.xs),
                    Text(
                      'Photo ${photo.index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  photo.passed
                      ? 'Confidence ${(photo.confidence * 100).toStringAsFixed(1)}%'
                      : photo.reason ?? 'Did not pass',
                  style: TextStyle(
                    color: photo.passed ? ScopeTheme.inkMuted : colour,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: photo.confidence.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: Colors.black12,
                    valueColor: AlwaysStoppedAnimation(colour),
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

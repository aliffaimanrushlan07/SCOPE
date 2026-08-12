import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';


import '../core/theme.dart';
import '../models/report_draft.dart';
import '../router.dart';
import '../widgets/photo_review_sheet.dart';

/// S08 — Capture Evidence.
///
/// Full-bleed viewfinder, one photograph per shutter tap, up to three. The
/// shutter disables at three and the counter changes to the maximum-reached
/// message.
///
/// Capture coordinates are recorded here rather than at S11. That gives the
/// report an evidentiary link between the photograph and the place, and lets
/// the backend flag a report whose tagged location is far from where the
/// photograph was taken. It is best-effort: a missing fix never blocks capture.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

enum _CameraState { initialising, ready, permissionDenied, unavailable }

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _CameraState _state = _CameraState.initialising;
  bool _isCapturing = false;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialiseCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    // The camera must be released when the app is backgrounded, or it will be
    // unavailable on resume.
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initialiseCamera();
    }
  }

  Future<void> _initialiseCamera() async {
    setState(() => _state = _CameraState.initialising);

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _state = _CameraState.permissionDenied);
      return;
    }

    // Requested here, not at S11, so a fix is available at capture time.
    // Never awaited in a way that blocks the viewfinder.
    unawaited(_ensureLocationPermission());

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _state = _CameraState.unavailable;
            _errorDetail = 'No camera was found on this device.';
          });
        }
        return;
      }

      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _state = _CameraState.ready;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _state = _CameraState.unavailable;
          _errorDetail = e.description ?? 'The camera could not be started.';
        });
      }
    }
  }

  Future<void> _ensureLocationPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } on Object {
      // Location is optional at capture. S11 handles a denial properly.
    }
  }

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _capture() async {
    final draft = context.read<ReportDraft>();
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) return;
    if (_isCapturing || !draft.canAddPhoto) return;

    setState(() => _isCapturing = true);
    try {
      final file = await controller.takePicture();
      final position = await _currentPosition();

      draft.addPhoto(CapturedPhoto(
        path: file.path,
        capturedAt: DateTime.now(),
        latitude: position?.latitude,
        longitude: position?.longitude,
      ));
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.description ?? 'Could not take the photo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Back or cancel. Confirms before discarding captured photographs.
  Future<void> _handleExit() async {
    final draft = context.read<ReportDraft>();

    if (!draft.hasPhotos) {
      if (mounted) context.go(Routes.home);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this report?'),
        content: Text(
          draft.photoCount == 1
              ? 'Your photo will be deleted and the report will not be filed.'
              : 'Your ${draft.photoCount} photos will be deleted and the report '
                  'will not be filed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep reporting'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: ScopeTheme.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (discard ?? false) {
      await draft.clear();
      if (mounted) context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ReportDraft>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildViewfinder(),
            _buildTopBar(draft),
            if (_state == _CameraState.ready) _buildControls(draft),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    switch (_state) {
      case _CameraState.initialising:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );

      case _CameraState.permissionDenied:
        return _BlockingState(
          icon: Icons.no_photography_outlined,
          title: 'Camera access is needed',
          message:
              'SCOPE cannot file a report without photo evidence. Allow camera '
              'access in Settings to continue.',
          primaryLabel: 'Open Settings',
          onPrimary: openAppSettings,
          onBack: () => context.go(Routes.home),
        );

      case _CameraState.unavailable:
        return _BlockingState(
          icon: Icons.videocam_off_outlined,
          title: 'Camera unavailable',
          message: _errorDetail ?? 'The camera could not be started.',
          primaryLabel: 'Try again',
          onPrimary: _initialiseCamera,
          onBack: () => context.go(Routes.home),
        );

      case _CameraState.ready:
        final controller = _controller!;
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 1,
            height: controller.value.previewSize?.width ?? 1,
            child: CameraPreview(controller),
          ),
        );
    }
  }

  Widget _buildTopBar(ReportDraft draft) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: _handleExit,
              tooltip: 'Cancel report',
            ),
            // Expanded, not Spacer-wrapped: the counter text changes length
            // ("Photo 1 of 3" -> "Maximum reached — review your photos") and
            // an unconstrained chip overflows the row on a narrow screen.
            Expanded(
              child: Center(
                child: _state == _CameraState.ready
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.md,
                          vertical: Gap.sm,
                        ),
                        decoration: BoxDecoration(
                          color: draft.isFull
                              ? ScopeTheme.warning.withValues(alpha: 0.92)
                              : Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          draft.counterLabel,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(ReportDraft draft) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          Gap.md,
          Gap.md,
          Gap.md,
          MediaQuery.of(context).padding.bottom + Gap.md,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (draft.hasPhotos) _buildThumbnailStrip(draft),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                const SizedBox(width: 72),
                Expanded(
                  child: Center(child: _buildShutter(draft)),
                ),
                SizedBox(
                  width: 72,
                  child: draft.hasPhotos
                      ? TextButton(
                          onPressed: () => showPhotoReviewSheet(context),
                          child: const Text(
                            'Review',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShutter(ReportDraft draft) {
    final enabled = draft.canAddPhoto && !_isCapturing;

    return GestureDetector(
      onTap: enabled ? _capture : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.white : Colors.white38,
          border: Border.all(color: Colors.white70, width: 4),
        ),
        child: _isCapturing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : null,
      ),
    );
  }

  Widget _buildThumbnailStrip(ReportDraft draft) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: draft.photoCount,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(draft.photos[index].path),
            width: 46,
            height: 58,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _BlockingState extends StatelessWidget {
  const _BlockingState({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onBack,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white54),
            const SizedBox(height: Gap.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
            const SizedBox(height: Gap.lg),
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            const SizedBox(height: Gap.sm),
            TextButton(
              onPressed: onBack,
              child: const Text(
                'Back to home',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

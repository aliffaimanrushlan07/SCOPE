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
///
/// Zoom is by pinch on the viewfinder or the preset pill above the shutter.
/// It is capped at [_zoomCap] because digital zoom beyond that degrades the
/// photograph faster than it helps the reporter, both as evidence and as
/// classifier input.
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

  /// Guards against overlapping starts: the permission prompt and a shade
  /// pull both produce inactive -> resumed while a start may be under way.
  bool _isInitialising = false;
  String? _errorDetail;

  static const double _zoomCap = 8.0;
  static const List<double> _zoomPresets = [1.0, 2.0, 5.0];

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoom = 1.0;
  double _zoomAtPinchStart = 1.0;

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
    // The camera must be released when the app loses focus, or it will be
    // unavailable on resume. `inactive` is also what pulling down the
    // notification shade or taking a screenshot produces, with no `paused`
    // in between, so resume must restart the camera from `_controller` being
    // null — not bail out because there is no controller to inspect.
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      if (controller == null) return;
      _controller = null;
      // Take the preview out of the tree before the controller is disposed,
      // so it never draws a dead texture (the blank viewfinder).
      if (mounted) setState(() => _state = _CameraState.initialising);
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_isInitialising) _initialiseCamera();
    }
  }

  Future<void> _initialiseCamera() async {
    if (_isInitialising) return;
    _isInitialising = true;
    try {
      await _startCamera();
    } finally {
      _isInitialising = false;
    }
  }

  Future<void> _startCamera() async {
    if (mounted) setState(() => _state = _CameraState.initialising);

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

      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();

      // Lost focus again while starting (shade pulled mid-start): release it;
      // the next resume starts it afresh.
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!mounted ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _state = _CameraState.ready;
        _minZoom = minZoom;
        _maxZoom = maxZoom.clamp(minZoom, _zoomCap);
        // The controller starts at its minimum, and a resume re-creates it.
        _zoom = minZoom;
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

  Future<void> _setZoom(double level) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final clamped = level.clamp(_minZoom, _maxZoom);
    if (clamped == _zoom) return;
    setState(() => _zoom = clamped);
    try {
      await controller.setZoomLevel(clamped);
    } on CameraException {
      // A dropped zoom step is harmless; the next pinch update corrects it.
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) => _zoomAtPinchStart = _zoom,
          onScaleUpdate: (details) {
            if (details.pointerCount < 2) return;
            _setZoom(_zoomAtPinchStart * details.scale);
          },
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize?.height ?? 1,
              height: controller.value.previewSize?.width ?? 1,
              child: CameraPreview(controller),
            ),
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
            if (_maxZoom > _minZoom) ...[
              _buildZoomPill(),
              const SizedBox(height: Gap.md),
            ],
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

  /// Preset buttons in the style of the stock camera: the segment the current
  /// zoom falls in shows the live value ("2.4×"), the others their preset.
  Widget _buildZoomPill() {
    final presets =
        _zoomPresets.where((p) => p >= _minZoom && p <= _maxZoom).toList();
    if (presets.isEmpty) return const SizedBox.shrink();

    final active = presets.lastWhere(
      (p) => _zoom >= p - 0.05,
      orElse: () => presets.first,
    );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final preset in presets)
            Semantics(
              button: true,
              label: 'Zoom ${_formatZoom(preset)}',
              child: GestureDetector(
                onTap: () => _setZoom(preset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: preset == active ? 48 : 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: preset == active
                        ? Colors.white.withValues(alpha: 0.22)
                        : Colors.transparent,
                  ),
                  child: Text(
                    _formatZoom(preset == active ? _zoom : preset),
                    style: TextStyle(
                      color: preset == active
                          ? ScopeTheme.warning
                          : Colors.white,
                      fontSize: preset == active ? 13 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatZoom(double level) {
    final rounded = (level * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return '$text×';
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

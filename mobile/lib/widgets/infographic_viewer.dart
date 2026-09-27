import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../core/theme.dart';
import '../models/api_models.dart';
import '../services/scope_api.dart';

/// S05 — Infographic Viewer.
///
/// A floating overlay over a dimmed backdrop, not a route: it returns to the
/// Awareness Hub (S04) that opened it.
///
/// Pinch-to-zoom and pan come from PhotoView, and they are not decoration —
/// an infographic legible on A4 is not legible on a phone without them.
Future<void> showInfographicViewer(
  BuildContext context,
  Infographic infographic,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (dialogContext) => _InfographicViewer(infographic: infographic),
  );
}

class _InfographicViewer extends StatelessWidget {
  const _InfographicViewer({required this.infographic});

  final Infographic infographic;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          // Tap-outside-to-dismiss.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: PhotoView(
              imageProvider:
                  NetworkImage(ScopeApi.mediaUrl(infographic.imagePath)),
              backgroundDecoration:
                  const BoxDecoration(color: Colors.transparent),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              errorBuilder: (_, _, _) => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: Colors.white54, size: 48),
                    SizedBox(height: Gap.sm),
                    Text(
                      'Could not load this infographic.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + Gap.sm,
            right: Gap.md,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
            ),
          ),
          Positioned(
            left: Gap.md,
            right: Gap.md,
            bottom: MediaQuery.of(context).padding.bottom + Gap.lg,
            child: Text(
              infographic.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

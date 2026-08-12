import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/report_draft.dart';
import '../router.dart';

/// S09 — Photo Review.
///
/// A floating sheet layered over the camera, not a route. That is the point:
/// the reporter is still in the capture context, so "Add photo" returns to the
/// viewfinder with existing photographs intact rather than restarting the task.
///
/// Rules:
///   - Add photo is hidden once three photographs are held.
///   - Continue is disabled at zero.
///   - Deleting the last photograph prompts for a capture rather than
///     silently leaving an unusable sheet.
Future<void> showPhotoReviewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PhotoReviewSheet(),
  );
}

class _PhotoReviewSheet extends StatelessWidget {
  const _PhotoReviewSheet();

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<ReportDraft>();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Review your photos',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        draft.hasPhotos
                            ? '${draft.photoCount} of 3 photos'
                            : 'No photos yet',
                        style: const TextStyle(color: ScopeTheme.inkMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: draft.hasPhotos
                ? ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(Gap.md),
                    itemCount: draft.photoCount,
                    separatorBuilder: (_, _) => const SizedBox(height: Gap.md),
                    itemBuilder: (context, index) => _PhotoTile(
                      photo: draft.photos[index],
                      position: index + 1,
                      onDelete: () => _confirmDelete(context, draft, index),
                    ),
                  )
                : const _EmptyState(),
          ),
          _buildActions(context, draft),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ReportDraft draft) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Gap.md,
        Gap.md,
        Gap.md,
        MediaQuery.of(context).padding.bottom + Gap.md,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE4E9E7))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            // Disabled at zero photographs, per the specification.
            onPressed: draft.hasPhotos
                ? () {
                    Navigator.of(context).pop();
                    context.push(Routes.validation);
                  }
                : null,
            child: const Text('Continue'),
          ),
          if (draft.canAddPhoto) ...[
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              // Simply closes the sheet: the camera is still beneath it, and
              // the photographs already held are untouched.
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.add_a_photo_outlined, size: 20),
              label: Text(
                draft.hasPhotos ? 'Add another photo' : 'Take a photo',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ReportDraft draft,
    int index,
  ) async {
    final isLast = draft.photoCount == 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isLast ? 'Delete your only photo?' : 'Delete this photo?'),
        content: Text(
          isLast
              ? 'You need at least one photo to continue. You will be asked to '
                  'take another.'
              : 'This photo will be removed from your report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: ScopeTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await draft.removePhotoAt(index);
    }
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.position,
    required this.onDelete,
  });

  final CapturedPhoto photo;
  final int position;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ScopeTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _expand(context),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: Image.file(File(photo.path), fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Photo $position',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        photo.latitude != null
                            ? 'Location recorded at capture'
                            : 'No location recorded',
                        style: const TextStyle(
                          fontSize: 12,
                          color: ScopeTheme.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: ScopeTheme.danger,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _expand(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Center(child: Image.file(File(photo.path))),
              Positioned(
                top: MediaQuery.of(dialogContext).padding.top + Gap.sm,
                right: Gap.md,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_a_photo_outlined,
                size: 44, color: ScopeTheme.inkMuted),
            SizedBox(height: Gap.md),
            Text(
              'You need at least one photo to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ScopeTheme.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

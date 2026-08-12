import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/device_id.dart';
import '../core/theme.dart';
import '../models/api_models.dart';
import '../router.dart';
import '../services/scope_api.dart';

/// S14 — Report History.
///
/// A receipt log keyed to the anonymous device identifier, newest first.
///
/// There is deliberately NO status badge. Because evidence is validated before
/// submission and administrators hold read-only access, nothing in the system
/// can change a report's state after it is filed — every stored report has
/// already passed validation. A badge reading "Under Review" or "Verified"
/// would advertise a workflow that does not exist.
///
/// The trade-off is real and the screen states it rather than hiding it:
/// reporters get confirmation that their report was filed, but no feedback on
/// whether enforcement acted on it.
class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  late Future<List<ReportHistoryItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ReportHistoryItem>> _load() async {
    final deviceId = await DeviceIdentity.get();
    if (!mounted) return const [];
    return context.read<ScopeApi>().reportHistory(deviceId);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report History')),
      body: FutureBuilder<List<ReportHistoryItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            return _LoadFailed(
              message: error is ApiException
                  ? error.message
                  : 'Your reports could not be loaded.',
              onRetry: _reload,
            );
          }

          final reports = snapshot.data ?? const [];
          if (reports.isEmpty) return const _EmptyState();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(Gap.md),
              itemCount: reports.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
              itemBuilder: (context, index) {
                if (index == reports.length) return const _DeviceBoundNotice();
                return _ReportRow(item: reports[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.item});

  final ReportHistoryItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ScopeTheme.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context, item.referenceNo),
        child: Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: item.thumbnailPath == null
                      ? Container(
                          color: Colors.black12,
                          child: const Icon(Icons.image_outlined,
                              color: ScopeTheme.inkMuted),
                        )
                      : Image.network(
                          ScopeApi.mediaUrl(item.thumbnailPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.black12,
                            child: const Icon(Icons.image_outlined,
                                color: ScopeTheme.inkMuted),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(item.submittedAt),
                      style: const TextStyle(
                        fontSize: 13,
                        color: ScopeTheme.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // The reference number, not a status: it is the reporter's
                    // only durable handle on an anonymous submission.
                    Text(
                      item.referenceNo,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ScopeTheme.primary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: ScopeTheme.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state.
///
/// Says plainly that history is device-bound. A reporter who loses their
/// history to a reinstall and was never warned will read it as a bug, so the
/// warning belongs here rather than buried in About.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 56, color: ScopeTheme.inkMuted),
            const SizedBox(height: Gap.md),
            const Text(
              "You haven't filed any reports yet",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Gap.sm),
            const Text(
              'Reports you file from this phone will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ScopeTheme.inkMuted, height: 1.45),
            ),
            const SizedBox(height: Gap.lg),
            FilledButton.icon(
              onPressed: () => context.go(Routes.capture),
              icon: const Icon(Icons.photo_camera_rounded, size: 20),
              label: const Text('Make a report'),
            ),
            const SizedBox(height: Gap.xl),
            const _DeviceBoundNotice(),
          ],
        ),
      ),
    );
  }
}

class _DeviceBoundNotice extends StatelessWidget {
  const _DeviceBoundNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: ScopeTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: ScopeTheme.inkMuted),
          SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'Because SCOPE reports are anonymous, your history is stored only '
              'on this phone. It will be empty if you reinstall the app or '
              'change phone — your reports stay filed, but this app can no '
              'longer show them to you. Keep your reference numbers.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: ScopeTheme.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 48, color: ScopeTheme.inkMuted),
            const SizedBox(height: Gap.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ScopeTheme.inkMuted, height: 1.45),
            ),
            const SizedBox(height: Gap.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Read-only detail
// ---------------------------------------------------------------------------

void _openDetail(BuildContext context, String referenceNo) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _ReportDetailScreen(referenceNo: referenceNo),
    ),
  );
}

class _ReportDetailScreen extends StatefulWidget {
  const _ReportDetailScreen({required this.referenceNo});

  final String referenceNo;

  @override
  State<_ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<_ReportDetailScreen> {
  late Future<ReportDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ReportDetail> _load() async {
    final deviceId = await DeviceIdentity.get();
    if (!mounted) throw StateError('disposed');
    return context.read<ScopeApi>().reportDetail(
          referenceNo: widget.referenceNo,
          deviceId: deviceId,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.referenceNo)),
      body: FutureBuilder<ReportDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _LoadFailed(
              message: 'This report could not be loaded.',
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final report = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              _ReferenceCard(referenceNo: report.referenceNo),
              const SizedBox(height: Gap.lg),
              const _SectionTitle('Photo evidence'),
              const SizedBox(height: Gap.sm),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: report.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
                  itemBuilder: (context, index) {
                    final photo = report.photos[index];
                    final url = ScopeApi.mediaUrl(photo.storagePath);
                    return GestureDetector(
                      onTap: () => _viewPhoto(context, url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          url,
                          width: 150,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 150,
                            color: Colors.black12,
                            child: const Icon(Icons.broken_image_outlined,
                                color: ScopeTheme.inkMuted),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: Gap.lg),
              const _SectionTitle('Details'),
              const SizedBox(height: Gap.sm),
              _DetailRow(label: 'Location', value: report.locationLabel),
              if (report.addressText != null)
                _DetailRow(label: 'Address', value: report.addressText!),
              _DetailRow(
                label: 'Coordinates',
                value: '${report.latitude.toStringAsFixed(5)}, '
                    '${report.longitude.toStringAsFixed(5)}',
              ),
              _DetailRow(
                label: 'Submitted',
                value: _formatDate(report.submittedAt),
              ),
              _DetailRow(
                label: 'Photos',
                value: '${report.photos.length}',
              ),
              const _DetailRow(label: 'Reported as', value: 'Anonymous'),
              const SizedBox(height: Gap.lg),
              // Stated once, plainly. Nothing in the system produces a status,
              // so the screen explains the absence rather than leaving the
              // reporter wondering where it went.
              const _DeviceBoundNotice(),
            ],
          );
        },
      ),
    );
  }

  void _viewPhoto(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            PhotoView(
              imageProvider: NetworkImage(url),
              backgroundDecoration:
                  const BoxDecoration(color: Colors.transparent),
              minScale: PhotoViewComputedScale.contained,
            ),
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
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.referenceNo});

  final String referenceNo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: ScopeTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ScopeTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reference number',
                  style: TextStyle(fontSize: 13, color: ScopeTheme.inkMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  referenceNo,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy reference number',
            icon: const Icon(Icons.copy_rounded, color: ScopeTheme.primary),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: referenceNo));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reference number copied')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: ScopeTheme.inkMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime utc) =>
    DateFormat('d MMM yyyy, h:mm a').format(utc.toLocal());

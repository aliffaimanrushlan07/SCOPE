import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/api_models.dart';
import '../services/scope_api.dart';

/// S06 — Smoking Violation Hotspot Map.
///
/// VIEW-ONLY. There is deliberately no reporting entry point from this screen:
/// a reporter arriving here is browsing, not filing, and a "report here"
/// button would invite reports about places rather than observed violations.
///
/// Rendering is a HEATMAP, never individual pins. A pin is resolvable to a
/// single premise, which would publicly attribute a report to a named business
/// — that matters both for reporter safety and for the project's defamation
/// exposure. Density shows where violations concentrate without naming anyone.
///
/// The backend reinforces this rather than trusting the client: /hotspots
/// returns coordinates already rounded to roughly 110 m, with weights and
/// nothing else. No reference number, premise name or timestamp ever reaches
/// this screen, so there is no way for the public map to leak an individual
/// report even if this widget were rewritten.
class HotspotMapScreen extends StatefulWidget {
  const HotspotMapScreen({super.key});

  @override
  State<HotspotMapScreen> createState() => _HotspotMapScreenState();
}

const LatLng _kualaLumpur = LatLng(3.1390, 101.6869);

class _HotspotMapScreenState extends State<HotspotMapScreen> {
  GoogleMapController? _map;
  late Future<List<HotspotPoint>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ScopeApi>().hotspots();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  void _reload() =>
      setState(() => _future = context.read<ScopeApi>().hotspots());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Violation Hotspots'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<HotspotPoint>>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final points = snapshot.data ?? const <HotspotPoint>[];

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _kualaLumpur,
                  zoom: 12,
                ),
                onMapCreated: (controller) => _map = controller,
                heatmaps: points.isEmpty
                    ? const {}
                    : {
                        Heatmap(
                          heatmapId: const HeatmapId('violations'),
                          data: [
                            for (final p in points)
                              WeightedLatLng(
                                LatLng(p.latitude, p.longitude),
                                weight: p.weight.toDouble(),
                              ),
                          ],
                          radius: HeatmapRadius.fromPixels(48),
                          opacity: 0.75,
                        ),
                      },
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
              if (loading)
                const Positioned(
                  top: Gap.md,
                  left: 0,
                  right: 0,
                  child: Center(child: _LoadingChip()),
                ),
              // The map still renders when data fails — the empty state is an
              // overlay, not a replacement, so the reporter is not left staring
              // at a blank screen.
              if (!loading && snapshot.hasError)
                Positioned(
                  left: Gap.md,
                  right: Gap.md,
                  top: Gap.md,
                  child: _MapNotice(
                    icon: Icons.wifi_off_rounded,
                    message:
                        'No hotspot data available. Check your connection.',
                    actionLabel: 'Retry',
                    onAction: _reload,
                  ),
                ),
              if (!loading && !snapshot.hasError && points.isEmpty)
                const Positioned(
                  left: Gap.md,
                  right: Gap.md,
                  top: Gap.md,
                  child: _MapNotice(
                    icon: Icons.map_outlined,
                    message:
                        'No violations have been reported in this area yet.',
                  ),
                ),
              Positioned(
                left: Gap.md,
                right: Gap.md,
                bottom: Gap.md,
                child: _Legend(pointCount: points.length),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingChip extends StatelessWidget {
  const _LoadingChip();

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      elevation: 2,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: Gap.sm),
            Text('Loading hotspots…', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(Gap.sm),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ScopeTheme.inkMuted),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, height: 1.3),
              ),
            ),
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

/// Explains the colour ramp and, more importantly, what the map does NOT show.
class _Legend extends StatelessWidget {
  const _Legend({required this.pointCount});

  final int pointCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Reported violation density',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF7FD4A8),
                          Color(0xFFFFD166),
                          Color(0xFFE76F51),
                          Color(0xFFB33F2B),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fewer reports',
                    style: TextStyle(fontSize: 11, color: ScopeTheme.inkMuted)),
                Text('More reports',
                    style: TextStyle(fontSize: 11, color: ScopeTheme.inkMuted)),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Text(
              pointCount == 0
                  ? 'This map shows where violations are reported, not which '
                      'premises were reported.'
                  : 'Shows where violations are reported, not which premises '
                      'were reported. Individual reports are never shown.',
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: ScopeTheme.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

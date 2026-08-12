import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/api_models.dart';
import '../services/scope_api.dart';
import '../widgets/infographic_viewer.dart';

/// S04 — Awareness Hub.
///
/// Three buttons, one per infographic slot, each with its topic and a
/// thumbnail. Tapping opens the same floating viewer (S05) the Home carousel
/// uses.
///
/// The count is fixed at three by the data model — the D06 slots are keyed 1-3
/// and the database rejects a fourth — so this screen needs no overflow state.
class AwarenessHubScreen extends StatefulWidget {
  const AwarenessHubScreen({super.key});

  @override
  State<AwarenessHubScreen> createState() => _AwarenessHubScreenState();
}

class _AwarenessHubScreenState extends State<AwarenessHubScreen> {
  late Future<List<Infographic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ScopeApi>().infographics();
  }

  void _reload() {
    setState(() => _future = context.read<ScopeApi>().infographics());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Awareness Hub')),
      body: FutureBuilder<List<Infographic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
            return _ErrorState(onRetry: _reload);
          }

          final items = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(Gap.md),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gap.md),
            itemBuilder: (context, index) => _InfographicCard(
              infographic: items[index],
              onTap: () => showInfographicViewer(context, items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _InfographicCard extends StatelessWidget {
  const _InfographicCard({required this.infographic, required this.onTap});

  final Infographic infographic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ScopeTheme.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 68,
                  height: 88,
                  child: Image.network(
                    ScopeApi.mediaUrl(infographic.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: ScopeTheme.primary.withValues(alpha: 0.1),
                      child: const Icon(Icons.image_outlined,
                          color: ScopeTheme.inkMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  infographic.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

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
                size: 44, color: ScopeTheme.inkMuted),
            const SizedBox(height: Gap.md),
            const Text(
              'Awareness content could not be loaded. Check your connection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ScopeTheme.inkMuted),
            ),
            const SizedBox(height: Gap.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

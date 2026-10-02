import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../router.dart';
import '../services/backend_status.dart';
import '../widgets/scope_logo.dart';

/// S02 — Home.
///
/// Layout order is fixed by the specification, top to bottom: logo header,
/// poster, three feature buttons, then the MAKE A REPORT button anchored near
/// the bottom and visually dominant.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _HomeHeader(),
            const _OfflineBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _HomePoster(),
                    const SizedBox(height: Gap.lg),
                    _FeatureButton(
                      icon: Icons.menu_book_outlined,
                      label: 'Awareness Hub',
                      onTap: () => context.push(Routes.awarenessHub),
                    ),
                    const SizedBox(height: Gap.sm),
                    _FeatureButton(
                      icon: Icons.map_outlined,
                      label: 'View Smoking Violation Hotspot Map',
                      onTap: () => context.push(Routes.hotspotMap),
                    ),
                    const SizedBox(height: Gap.sm),
                    _FeatureButton(
                      icon: Icons.rule_outlined,
                      label: 'Reporting Guidelines',
                      onTap: () => context.push(Routes.guidelines),
                    ),
                    const SizedBox(height: Gap.lg),
                  ],
                ),
              ),
            ),
            _buildPrimaryAction(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
      child: SizedBox(
        height: 64,
        child: FilledButton.icon(
          onPressed: () => context.push(Routes.capture),
          icon: const Icon(Icons.photo_camera_rounded, size: 26),
          label: const Text(
            'MAKE A REPORT',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the backend failed its last health check, whether at launch
/// (S01) or on a retry here.
///
/// Home itself is bundled and works offline, so this informs rather than
/// blocks. Settings is offered because the usual cause during a demonstration
/// is a changed hotspot address, and the connection settings are otherwise
/// two screens deep behind About.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  Future<void> _openSettings(BuildContext context) async {
    final status = context.read<BackendStatus>();
    await context.push(Routes.settings);
    // The address may have changed; check it rather than keep a stale warning.
    await status.check();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<BackendStatus>();
    if (!status.isUnreachable) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.sm, Gap.xs),
        decoration: BoxDecoration(
          color: ScopeTheme.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ScopeTheme.warning.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_rounded, color: ScopeTheme.warning),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    "Can't reach the SCOPE server. Reports can't be sent and "
                    "online content won't load until it's back.",
                    style: const TextStyle(
                      color: ScopeTheme.ink,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _openSettings(context),
                  child: const Text('Settings'),
                ),
                TextButton(
                  onPressed: status.isChecking ? null : status.check,
                  child: status.isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The logo header. Tapping it opens S03.
///
/// A chevron sits beside the mark because a tappable logo is not a control
/// users expect — without an affordance the navigation menu is undiscoverable.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => _showNavigationMenu(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.sm,
                vertical: Gap.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ScopeLogo(size: 38),
                  const SizedBox(width: Gap.sm),
                  Text(
                    'SCOPE',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// S03 — Navigation Menu.
///
/// A popup over a dimmed Home rather than a route, dismissed by tapping
/// outside or pressing back.
Future<void> _showNavigationMenu(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) => Stack(
      children: [
        Positioned(
          top: MediaQuery.of(dialogContext).padding.top + 60,
          left: Gap.md,
          right: Gap.md * 4,
          child: Material(
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Report History'),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    context.push(Routes.history);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About SCOPE'),
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    context.push(Routes.about);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The Home poster.
///
/// Standing artwork, not a preview: the awareness infographics this
/// replaced are still one tap away in the Awareness Hub (S04), so Home no
/// longer needs to page through them. Being a bundled asset it has no
/// loading, error or offline state, which is the point — Home is the screen
/// someone opens with a violation in front of them.
///
/// 190 is the height the carousel occupied, kept so everything below it lands
/// where it did. The artwork is authored at 1200 × 630; see
/// docs/home-poster-prompt.md for why that aspect and what has to stay inside
/// its safe zone, because [BoxFit.cover] crops the sides on a narrow phone and
/// the top and bottom on a wide one.
class _HomePoster extends StatelessWidget {
  const _HomePoster();

  @override
  Widget build(BuildContext context) {
    // The poster is an animated WebP: a camera reticle and a smoke plume loop
    // for as long as Home is on screen, which is the whole time for most of a
    // session. Motion that starts by itself and never stops needs a way out
    // (WCAG 2.2.2), and the platform already offers one, so take the still
    // first frame when the user has asked for less motion.
    final asset = MediaQuery.disableAnimationsOf(context)
        ? 'assets/poster/home-poster-still.png'
        : 'assets/poster/home-poster.webp';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 190,
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          // The poster's wording lives in the artwork, where a screen reader
          // cannot reach it.
          semanticLabel: 'Poster: Nampak orang merokok? Ambil gambar dan '
              'lapor. See someone smoking? Snap it and report it.',
        ),
      ),
    );
  }
}

class _FeatureButton extends StatelessWidget {
  const _FeatureButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, size: 22, color: ScopeTheme.primary),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(label, textAlign: TextAlign.left)),
          const Icon(Icons.chevron_right_rounded, color: ScopeTheme.inkMuted),
        ],
      ),
    );
  }
}

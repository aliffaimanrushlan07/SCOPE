import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/api_models.dart';
import '../router.dart';
import '../services/scope_api.dart';
import '../widgets/infographic_viewer.dart';
import '../widgets/scope_logo.dart';

/// S02 — Home.
///
/// Layout order is fixed by the specification, top to bottom: logo header,
/// infographic carousel, three feature buttons, then the MAKE A REPORT button
/// anchored near the bottom and visually dominant.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Infographic>> _infographics;
  int _carouselIndex = 0;

  @override
  void initState() {
    super.initState();
    _infographics = context.read<ScopeApi>().infographics();
  }

  void _reload() {
    setState(() {
      _infographics = context.read<ScopeApi>().infographics();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _HomeHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCarousel(),
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

  Widget _buildCarousel() {
    return FutureBuilder<List<Infographic>>(
      future: _infographics,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _CarouselPlaceholder(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
          return _CarouselPlaceholder(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, color: ScopeTheme.inkMuted),
                const SizedBox(height: Gap.sm),
                const Text(
                  'Awareness content unavailable',
                  style: TextStyle(color: ScopeTheme.inkMuted),
                ),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }

        final items = snapshot.data!;
        return Column(
          children: [
            CarouselSlider.builder(
              itemCount: items.length,
              options: CarouselOptions(
                height: 190,
                viewportFraction: 1,
                autoPlay: true,
                autoPlayInterval: const Duration(seconds: 6),
                onPageChanged: (index, _) =>
                    setState(() => _carouselIndex = index),
              ),
              itemBuilder: (context, index, _) => _CarouselSlide(
                infographic: items[index],
                // Tapping a slide opens the same viewer the Awareness Hub uses.
                onTap: () => showInfographicViewer(context, items[index]),
              ),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                items.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _carouselIndex == index ? 20 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _carouselIndex == index
                        ? ScopeTheme.primary
                        : const Color(0xFFCBD5D2),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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

class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({required this.infographic, required this.onTap});

  final Infographic infographic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ScopeTheme.surfaceMuted,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              ScopeApi.mediaUrl(infographic.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: ScopeTheme.primary.withValues(alpha: 0.08),
                child: const Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 44,
                    color: ScopeTheme.inkMuted,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
                child: Text(
                  infographic.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselPlaceholder extends StatelessWidget {
  const _CarouselPlaceholder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ScopeTheme.surfaceMuted,
      ),
      child: Center(child: child),
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

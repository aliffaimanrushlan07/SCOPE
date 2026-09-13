import 'package:flutter/material.dart';

/// SCOPE brand mark: a camera aperture with a location pin punched out of its
/// centre — the two things every report carries, photographic evidence and a
/// GPS fix.
///
/// [onDark] swaps to the knockout-white variant, whose negative space is
/// transparent so the surface behind shows through it. Use it on
/// [ScopeTheme.chrome]; the default colour mark is for light surfaces.
class ScopeLogo extends StatelessWidget {
  const ScopeLogo({super.key, this.size = 40, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      onDark
          ? 'assets/branding/scope_mark_white.png'
          : 'assets/branding/scope_mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'SCOPE',
    );
  }
}

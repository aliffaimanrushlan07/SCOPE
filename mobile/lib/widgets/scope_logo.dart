import 'package:flutter/material.dart';

/// SCOPE brand mark: a magnifying glass held over a lit cigarette — the
/// enforcement act itself, inspection of a smoking violation.
///
/// [onDark] is kept as the call site's statement of intent, but currently
/// resolves to the same artwork as the light variant: the brand set ships one
/// full-colour mark and no white knockout. The mark is transparent outside its
/// own silhouette, and its teal ring carries enough contrast to stay legible on
/// [ScopeTheme.chrome]. Point [onDark] at a dedicated asset if one is drawn.
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

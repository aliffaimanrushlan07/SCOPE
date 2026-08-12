import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Placeholder brand mark.
///
/// Drawn rather than loaded from an asset so the app runs before any artwork
/// exists. Replace with the real logo asset when it is ready; nothing else
/// needs to change.
class ScopeLogo extends StatelessWidget {
  const ScopeLogo({super.key, this.size = 40, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final colour = onDark ? Colors.white : ScopeTheme.primary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colour, width: size * 0.07),
      ),
      child: Icon(
        Icons.smoke_free_rounded,
        size: size * 0.6,
        color: colour,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Placeholder for a screen scheduled for a later sprint.
///
/// It names the sprint and what the screen will do, so that running the app
/// mid-build never leaves an unexplained blank page — and so a screenshot
/// taken during development is never mistaken for a finished screen.
class NotYetBuilt extends StatelessWidget {
  const NotYetBuilt({
    super.key,
    required this.screenId,
    required this.title,
    required this.sprint,
    required this.description,
  });

  final String screenId;
  final String title;
  final String sprint;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: Gap.xs,
                ),
                decoration: BoxDecoration(
                  color: ScopeTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$screenId · $sprint',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: ScopeTheme.inkMuted,
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              const Icon(Icons.construction_rounded,
                  size: 44, color: ScopeTheme.inkMuted),
              const SizedBox(height: Gap.md),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.5, color: ScopeTheme.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

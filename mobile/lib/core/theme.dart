import 'package:flutter/material.dart';

/// Visual language for the reporting app.
///
/// Restrained on purpose. A member of the public may be using this while
/// standing near the person they are reporting, so the interface should read
/// as an official reporting tool rather than a consumer app: high contrast,
/// large touch targets, no decoration competing with the primary action.
class ScopeTheme {
  ScopeTheme._();

  /// Brand blue. Identical to the dashboard's `--brand`, so a screenshot of
  /// the app and a screenshot of the dashboard read as one system.
  ///
  /// Derived from the Jalur Gemilang blue (#010066) but held at ~70%
  /// saturation: the flag value is meant for fabric, and at full saturation
  /// it fringes badly behind white label text.
  static const Color primary = Color(0xFF1A3D8F);

  /// The same flag blue taken darker, used only for full-bleed chrome — the
  /// splash here, the sidebar on the dashboard. Shared with `--chrome`.
  static const Color chrome = Color(0xFF0B1F4D);

  static const Color danger = Color(0xFFB3261E);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFE65100);
  static const Color surfaceMuted = Color(0xFFF2F4F3);
  static const Color ink = Color(0xFF17211F);
  static const Color inkMuted = Color(0xFF5A6663);

  /// Hairlines. [line] separates controls, [lineSoft] separates a sheet's
  /// action bar from its content.
  static const Color line = Color(0xFFCBD5D2);
  static const Color lineSoft = Color(0xFFE4E9E7);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      // Pinned: Material 3 otherwise renders a tonal approximation of the
      // seed, so the button would not actually be the documented brand hex.
      primary: primary,
      onPrimary: Colors.white,
      surface: Colors.white,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: line),
          foregroundColor: ink,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
      ),
    );
  }
}

/// Spacing scale. Using named steps keeps padding consistent across fifteen
/// screens built at different times.
class Gap {
  Gap._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

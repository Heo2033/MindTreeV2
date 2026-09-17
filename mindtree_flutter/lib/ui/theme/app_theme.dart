import 'package:flutter/material.dart';

/// Semantic colors shared across screens.
class AppColors {
  AppColors._();

  static const Color seed = Color(0xFF2563EB);
  static const Color ok = Color(0xFF16A34A);
  static const Color warn = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color ink = Color(0xFF1F2937);
  static const Color muted = Color(0xFF6B7280);

  // Shadows matching web (--shadow-card, --shadow-pop)
  static const List<BoxShadow> shadowCard = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];
  static const List<BoxShadow> shadowPop = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 8,
      offset: Offset(0, 6),
    ),
  ];

  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF4ADE80)
          : ok;
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFBBF24)
          : warn;
  static Color error(BuildContext context) =>
      Theme.of(context).colorScheme.error;
  static Color textMuted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
}

ThemeData lightTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.seed);
  return _baseTheme(scheme);
}

ThemeData darkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: Brightness.dark,
  );
  return _baseTheme(scheme);
}

/// A page transition that blocks pointer hit-testing (including mouse hover)
/// on the incoming route until its entrance animation has completed and layout
/// has settled.
///
/// Works around a Flutter framework defect where a pointer event hitting a
/// `Scaffold`'s implicit `_ScaffoldSlot.floatingActionButton` (which is
/// `NEEDS-LAYOUT`/`NEEDS-PAINT`, no size yet) during a route transition throws
/// "Cannot hit test a render box that has never been laid out".
class IgnorePointerPageTransitionsBuilder extends PageTransitionsBuilder {
  const IgnorePointerPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return IgnorePointer(
      ignoring: !animation.isCompleted || animation.isAnimating,
      child: child,
    );
  }
}

ThemeData _baseTheme(ColorScheme scheme) {
  final baseTextTheme = Typography.material2021().black;
  final letterSpacing = -0.011;

  TextStyle addLetterSpacing(TextStyle s) => s.copyWith(
        letterSpacing: letterSpacing * (s.fontSize ?? 14),
        height: 1.5,
      );

  final textTheme = TextTheme(
    displayLarge: addLetterSpacing(baseTextTheme.displayLarge!),
    displayMedium: addLetterSpacing(baseTextTheme.displayMedium!),
    displaySmall: addLetterSpacing(baseTextTheme.displaySmall!),
    headlineLarge: addLetterSpacing(baseTextTheme.headlineLarge!),
    headlineMedium: addLetterSpacing(baseTextTheme.headlineMedium!),
    headlineSmall: addLetterSpacing(baseTextTheme.headlineSmall!),
    titleLarge: addLetterSpacing(baseTextTheme.titleLarge!),
    titleMedium: addLetterSpacing(baseTextTheme.titleMedium!),
    titleSmall: addLetterSpacing(baseTextTheme.titleSmall!),
    bodyLarge: addLetterSpacing(baseTextTheme.bodyLarge!),
    bodyMedium: addLetterSpacing(baseTextTheme.bodyMedium!),
    bodySmall: addLetterSpacing(baseTextTheme.bodySmall!),
    labelLarge: addLetterSpacing(baseTextTheme.labelLarge!),
    labelMedium: addLetterSpacing(baseTextTheme.labelMedium!),
    labelSmall: addLetterSpacing(baseTextTheme.labelSmall!),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    textTheme: textTheme,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: IgnorePointerPageTransitionsBuilder(),
        TargetPlatform.iOS: IgnorePointerPageTransitionsBuilder(),
        TargetPlatform.macOS: IgnorePointerPageTransitionsBuilder(),
        TargetPlatform.windows: IgnorePointerPageTransitionsBuilder(),
        TargetPlatform.linux: IgnorePointerPageTransitionsBuilder(),
        TargetPlatform.fuchsia: IgnorePointerPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

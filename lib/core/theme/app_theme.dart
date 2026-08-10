import 'package:flutter/material.dart';

/// Central design tokens. Everything visual derives from here so the app
/// stays consistent as it grows.
abstract final class Tokens {
  static const double s4 = 4, s8 = 8, s12 = 12, s16 = 16, s20 = 20, s24 = 24, s32 = 32;
  static const double rCard = 20, rSheet = 28, rControl = 14, rChip = 10;
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
  static const Curve curve = Curves.easeOutCubic;
}

enum AppThemeMode { system, light, dark, oled }

class AccentColor {
  final String name;
  final Color color;
  const AccentColor(this.name, this.color);
}

const accentPalette = <AccentColor>[
  AccentColor('Indigo', Color(0xFF5B5BD6)),
  AccentColor('Blue', Color(0xFF0B84FF)),
  AccentColor('Teal', Color(0xFF0CA5A5)),
  AccentColor('Green', Color(0xFF2E9E5B)),
  AccentColor('Amber', Color(0xFFDB8B00)),
  AccentColor('Orange', Color(0xFFE8590C)),
  AccentColor('Pink', Color(0xFFD6437E)),
  AccentColor('Purple', Color(0xFF8E4EC6)),
  AccentColor('Red', Color(0xFFD64545)),
  AccentColor('Slate', Color(0xFF5C6470)),
];

/// Palette used for user-pickable item colors (habits, accounts, subjects...).
const itemColors = <Color>[
  Color(0xFF5B5BD6), Color(0xFF0B84FF), Color(0xFF00A3C4), Color(0xFF0CA5A5),
  Color(0xFF2E9E5B), Color(0xFF7CB518), Color(0xFFDB8B00), Color(0xFFE8590C),
  Color(0xFFD64545), Color(0xFFD6437E), Color(0xFF8E4EC6), Color(0xFF5C6470),
];

ThemeData buildAppTheme({
  required Brightness brightness,
  required Color accent,
  bool oled = false,
  bool compact = false,
}) {
  final dark = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);

  final Color bg;
  final Color card;
  final Color cardAlt;
  if (!dark) {
    bg = const Color(0xFFF5F5F7);
    card = Colors.white;
    cardAlt = const Color(0xFFEDEDF1);
  } else if (oled) {
    bg = Colors.black;
    card = const Color(0xFF101013);
    cardAlt = const Color(0xFF1A1A1E);
  } else {
    bg = const Color(0xFF121216);
    card = const Color(0xFF1C1C21);
    cardAlt = const Color(0xFF26262C);
  }

  scheme = scheme.copyWith(
    primary: dark ? _lighten(accent, .18) : accent,
    surface: bg,
    surfaceContainerLowest: card,
    surfaceContainerLow: card,
    surfaceContainer: card,
    surfaceContainerHigh: cardAlt,
    surfaceContainerHighest: cardAlt,
    outlineVariant: dark ? Colors.white.withValues(alpha: .08) : Colors.black.withValues(alpha: .07),
  );

  final baseText = Typography.material2021(platform: TargetPlatform.android)
      .englishLike
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      );

  final text = baseText.copyWith(
    headlineLarge: baseText.headlineLarge!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.8),
    headlineMedium: baseText.headlineMedium!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.6),
    headlineSmall: baseText.headlineSmall!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.4),
    titleLarge: baseText.titleLarge!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.3),
    titleMedium: baseText.titleMedium!.copyWith(fontWeight: FontWeight.w600, letterSpacing: -.2),
    titleSmall: baseText.titleSmall!.copyWith(fontWeight: FontWeight.w600),
    labelLarge: baseText.labelLarge!.copyWith(fontWeight: FontWeight.w600),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rCard)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: oled ? Colors.black : card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: .14),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium!.copyWith(fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardAlt.withValues(alpha: dark ? .6 : 1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.rControl),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.rControl),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rControl)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rControl)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rControl)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rControl)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rChip)),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: card,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rSheet)),
      ),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rSheet)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rControl)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rControl)),
    ),
  );
}

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

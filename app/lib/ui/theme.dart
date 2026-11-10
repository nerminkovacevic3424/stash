import 'package:flutter/material.dart';

const _seed = Color(0xFF5B5BD6);

const folderColors = <Color>[
  Color(0xFF5B5BD6), // indigo
  Color(0xFFE5484D), // red
  Color(0xFFF76B15), // orange
  Color(0xFFFFB224), // amber
  Color(0xFF30A46C), // green
  Color(0xFF12A594), // teal
  Color(0xFF0090FF), // blue
  Color(0xFFD6409F), // pink
];

Color folderColor(int index) => folderColors[index % folderColors.length];

const folderEmojis = [
  '📁',
  '🍳',
  '🍝',
  '🍰',
  '☕',
  '🍹',
  '✈️',
  '🏝️',
  '🏔️',
  '🏋️',
  '🧘',
  '🏃',
  '👗',
  '💄',
  '🛍️',
  '🏠',
  '🛋️',
  '🌱',
  '🎨',
  '📸',
  '🎬',
  '🎵',
  '🎮',
  '📚',
  '💡',
  '💻',
  '💰',
  '🧠',
  '😂',
  '🐶',
  '🐱',
  '👶',
  '🎁',
  '💍',
  '🚗',
  '⚽',
  '🔧',
  '❤️',
  '⭐',
  '🔥',
];

/// [fontFamily] is only set by the screenshot harness; devices use the system font.
ThemeData buildTheme(Brightness brightness, {String? fontFamily, List<String>? fontFamilyFallback}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    // The generated primary is washed out; keep the brand indigo at full strength.
    primary: dark ? const Color(0xFF8E8EF5) : _seed,
    onPrimary: dark ? const Color(0xFF14143A) : Colors.white,
    surface: dark ? const Color(0xFF111113) : const Color(0xFFFCFCFD),
  );
  TextStyle style({double? size, FontWeight? weight, Color? color}) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: style(size: 20, weight: FontWeight.w700, color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: style(size: 17, weight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: dark ? 0.6 : 0.5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF1A1A1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: style(size: 15, weight: FontWeight.w600)),
    ),
    popupMenuTheme: PopupMenuThemeData(textStyle: style(size: 15, color: scheme.onSurface)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    chipTheme: ChipThemeData(
      labelStyle: style(size: 14, weight: FontWeight.w500, color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

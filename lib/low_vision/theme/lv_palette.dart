import 'package:flutter/material.dart';

/// ערכות צבע בניגודיות גבוהה לקריאה מקרוב.
/// שחור על לבן (כמו ספר פיזי) הוא ברירת המחדל והראשון ברשימה.
enum LvPalette {
  blackOnWhite(
    label: 'שחור על לבן',
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF000000),
    surface: Color(0xFFEDEDED),
    accent: Color(0xFF000000),
    onAccent: Color(0xFFFFFFFF),
  ),
  yellowOnBlack(
    label: 'צהוב על שחור',
    background: Color(0xFF000000),
    foreground: Color(0xFFFFEB3B),
    surface: Color(0xFF1C1C1C),
    accent: Color(0xFFFFEB3B),
    onAccent: Color(0xFF000000),
  ),
  whiteOnBlack(
    label: 'לבן על שחור',
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    surface: Color(0xFF1C1C1C),
    accent: Color(0xFFFFFFFF),
    onAccent: Color(0xFF000000),
  ),
  blackOnYellow(
    label: 'שחור על צהוב',
    background: Color(0xFFFFF176),
    foreground: Color(0xFF000000),
    surface: Color(0xFFFFEE58),
    accent: Color(0xFF000000),
    onAccent: Color(0xFFFFF176),
  );

  const LvPalette({
    required this.label,
    required this.background,
    required this.foreground,
    required this.surface,
    required this.accent,
    required this.onAccent,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color surface;

  /// רקע הכפתורים הראשיים.
  final Color accent;
  final Color onAccent;

  bool get isDark => background.computeLuminance() < 0.5;

  LvPalette get next => values[(index + 1) % values.length];
}

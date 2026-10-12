import 'package:flutter/material.dart';

import 'palette.dart';

/// Editorial type system (same families as the web): Newsreader for display,
/// Hanken Grotesk for body copy, IBM Plex Mono for ledger figures and labels.
class Fonts {
  static const display = 'Newsreader';
  static const body = 'HankenGrotesk';
  static const mono = 'IBMPlexMono';
}

const _tabular = [FontFeature.tabularFigures()];

TextStyle displayStyle(Palette p, double size, {FontWeight weight = FontWeight.w600, Color? color}) => TextStyle(
      fontFamily: Fonts.display,
      fontSize: size,
      fontWeight: weight,
      height: 1.05,
      letterSpacing: -0.025 * size,
      color: color ?? p.ink,
    );

/// Italic serif accent phrase ("so far.", "limits.").
TextStyle accentItalic(Palette p, double size, {double alpha = 0.9}) => TextStyle(
      fontFamily: Fonts.display,
      fontSize: size,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
      color: p.accent.withValues(alpha: alpha),
    );

TextStyle monoStyle(Palette p, double size, {Color? color, FontWeight weight = FontWeight.w400, double? letterSpacing}) =>
    TextStyle(
      fontFamily: Fonts.mono,
      fontSize: size,
      fontWeight: weight,
      fontFeatures: _tabular,
      letterSpacing: letterSpacing,
      color: color ?? p.ink,
    );

TextStyle bodyStyle(Palette p, double size, {Color? color, FontWeight weight = FontWeight.w400, double? height}) =>
    TextStyle(fontFamily: Fonts.body, fontSize: size, fontWeight: weight, height: height, color: color ?? p.ink);

ThemeData buildTheme(Palette p) {
  final brightness = p.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.saving,
    onSecondary: Colors.white,
    error: p.expense,
    onError: Colors.white,
    surface: p.card,
    onSurface: p.ink,
    surfaceContainerHighest: p.card,
    outline: p.line,
  );
  final base = ThemeData(brightness: brightness, colorScheme: scheme, useMaterial3: true, fontFamily: Fonts.body);
  OutlineInputBorder border(Color c) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c));

  return base.copyWith(
    scaffoldBackgroundColor: p.paper,
    canvasColor: p.card,
    dividerColor: p.line,
    extensions: [p],
    textTheme: base.textTheme.apply(fontFamily: Fonts.body, bodyColor: p.ink, displayColor: p.ink),
    splashColor: p.inkA(0.06),
    highlightColor: p.inkA(0.04),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.25),
      selectionHandleColor: p.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: p.inkA(0.02),
      hintStyle: TextStyle(fontFamily: Fonts.body, color: p.muted(0.35), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: border(p.line),
      enabledBorder: border(p.line),
      focusedBorder: border(p.accent.withValues(alpha: 0.5)),
      disabledBorder: border(p.line),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent, elevation: 0),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.dark ? const Color(0xFF1A1A1A) : p.ink,
      contentTextStyle: TextStyle(fontFamily: Fonts.body, color: p.dark ? p.ink : p.paper, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    datePickerTheme: DatePickerThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    timePickerTheme: TimePickerThemeData(backgroundColor: p.card),
    popupMenuTheme: PopupMenuThemeData(color: p.card, surfaceTintColor: Colors.transparent),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
  );
}

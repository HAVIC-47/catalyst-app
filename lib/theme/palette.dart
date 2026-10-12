import 'package:flutter/material.dart';

/// Design tokens — the same values as the web app's globals.css (:root = light,
/// .dark = dark). Exposed as a ThemeExtension: `Palette.of(context)`.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.dark,
    required this.paper,
    required this.panel,
    required this.card,
    required this.ink,
    required this.accent,
    required this.line,
    required this.income,
    required this.expense,
    required this.saving,
    required this.tintSpend,
    required this.tintIncome,
    required this.tintK,
    required this.tintMoodK,
    required this.tintTextMix,
    required this.yrMood,
    required this.yrFloor,
    required this.yrSpan,
  });

  final bool dark;
  final Color paper, panel, card, ink, accent, line;
  final Color income, expense, saving;
  final Color tintSpend, tintIncome;
  final double tintK, tintMoodK, tintTextMix;
  final double yrMood, yrFloor, yrSpan;

  /// Fresh newsprint: warm-white paper, white cards, near-black ink, terracotta.
  static const light = Palette(
    dark: false,
    paper: Color(0xFFF6F5F1),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF181512),
    accent: Color(0xFFB2462C),
    line: Color(0x1A181512),
    income: Color(0xFF1F7049),
    expense: Color(0xFFB93A30),
    saving: Color(0xFF2C6CA6),
    tintSpend: Color(0xFFCB453B),
    tintIncome: Color(0xFF3D80BC),
    tintK: 0.6,
    tintMoodK: 0.75,
    tintTextMix: 0.62,
    yrMood: 0.55,
    yrFloor: 0.35,
    yrSpan: 0.45,
  );

  /// True black, near-white ink, bright clay accent.
  static const night = Palette(
    dark: true,
    paper: Color(0xFF000000),
    panel: Color(0xFF000000),
    card: Color(0xFF080808),
    ink: Color(0xFFFAF9F6),
    accent: Color(0xFFE28670),
    line: Color(0x29FFFFFF),
    income: Color(0xFF2E8159),
    expense: Color(0xFFCB453B),
    saving: Color(0xFF3D80BC),
    tintSpend: Color(0xFF9B3A2D),
    tintIncome: Color(0xFF34618A),
    tintK: 1,
    tintMoodK: 1,
    tintTextMix: 1,
    yrMood: 0.7,
    yrFloor: 0.42,
    yrSpan: 0.45,
  );

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  /// Muted text at the web's ink alpha (`text-ink/45` -> muted(0.45)). On light
  /// paper the faint steps are lifted exactly like the web so text clears AA.
  Color muted(double a) => ink.withValues(alpha: dark ? a : _lift(a));

  /// Ink at an exact alpha — for surfaces, borders and fills (no lift).
  Color inkA(double a) => ink.withValues(alpha: a);

  Color accentA(double a) => accent.withValues(alpha: a);

  /// Mono uppercase label color (`.label`).
  Color get labelColor => dark ? ink.withValues(alpha: 0.45) : ink.withValues(alpha: 0.64);

  /// A data color (category / mood) made readable as text on its own pale tint:
  /// pulled toward ink on white, unchanged on black.
  Color tintText(Color c) => Color.lerp(ink, c, tintTextMix)!;

  /// Text color on the solid accent (entry buttons).
  Color get onAccent => const Color(0xFFF7F2E7);

  static double _lift(double a) {
    const steps = [
      (0.25, 0.5), (0.30, 0.6), (0.35, 0.6), (0.40, 0.62), (0.45, 0.65),
      (0.50, 0.68), (0.55, 0.70), (0.60, 0.72), (0.65, 0.75), (0.70, 0.78),
    ];
    if (a >= 0.75) return a;
    var best = steps.first;
    for (final s in steps) {
      if ((s.$1 - a).abs() < (best.$1 - a).abs()) best = s;
    }
    return best.$2;
  }

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) => t < 0.5 || other is! Palette ? this : other;
}

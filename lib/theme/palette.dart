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
    required this.violet,
    required this.violetText,
    required this.moods,
  });

  final bool dark;
  final Color paper, panel, card, ink, accent, line;
  final Color income, expense, saving;
  final Color tintSpend, tintIncome;
  final double tintK, tintMoodK, tintTextMix;
  final double yrMood, yrFloor, yrSpan;
  final Color violet, violetText; // the mood line and its labels
  final List<Color> moods; // awful → great

  /// Vivid and airy: lavender-white paper, white cards, deep indigo ink, a vivid
  /// coral accent, saturated data tones — text 4.5:1, icons and marks 3:1.
  static const light = Palette(
    dark: false,
    paper: Color(0xFFF8F7FC),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF11101F),
    accent: Color(0xFFD4381C),
    line: Color(0x1A11101F),
    income: Color(0xFF047857),
    expense: Color(0xFFDC2626),
    saving: Color(0xFF2563EB),
    tintSpend: Color(0xFFF43F5E),
    tintIncome: Color(0xFF3B82F6),
    tintK: 0.75,
    tintMoodK: 0.9,
    tintTextMix: 0.74,
    yrMood: 0.55,
    yrFloor: 0.35,
    yrSpan: 0.45,
    violet: Color(0xFF7C3AED),
    violetText: Color(0xFF6D28D9),
    // rose, orange, amber, lime, emerald
    moods: [Color(0xFFE11D48), Color(0xFFEA580C), Color(0xFFD97706), Color(0xFF65A30D), Color(0xFF059669)],
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
    violet: Color(0xFF7A4E86),
    violetText: Color(0xFF9268A0),
    // brick, burnt orange, ochre, olive, forest
    moods: [Color(0xFFA8322A), Color(0xFFC06A33), Color(0xFFB59A3C), Color(0xFF6E8C46), Color(0xFF2E8159)],
  );

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  /// A mood's color (1 = awful … 5 = great) in this theme.
  Color mood(int value) => moods[(value < 1 ? 1 : (value > 5 ? 5 : value)) - 1];

  /// A stored color (a category's, a tag's) the way this theme wants it: more
  /// saturated on light paper so it pops, unchanged on black (the web's vivid()).
  Color vivid(Color c) {
    if (dark) return c;
    final h = HSLColor.fromColor(c);
    return h.withSaturation((h.saturation * 1.35).clamp(0.0, 1.0)).withLightness((h.lightness * 0.97).clamp(0.0, 1.0)).toColor();
  }

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

  /// Text color on the solid accent (entry buttons): white on the vivid coral (4.8:1).
  Color get onAccent => dark ? const Color(0xFFF7F2E7) : const Color(0xFFFFFFFF);

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

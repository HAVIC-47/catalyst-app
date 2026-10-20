import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models.dart';
import '../theme/palette.dart';

// One face per mood level (1 = awful … 5 = great) — same line icons as the web.
const _faces = {1: LucideIcons.angry, 2: LucideIcons.frown, 3: LucideIcons.meh, 4: LucideIcons.smile, 5: LucideIcons.laugh};

/// A mood's face icon, tinted with the mood color unless [muted] (then [color] or the ambient icon color).
class MoodFace extends StatelessWidget {
  const MoodFace(this.mood, {super.key, this.size = 18, this.muted = false, this.color});

  final int mood;
  final double size;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final m = moodPreset(mood);
    return Icon(_faces[m.value], size: size, color: muted ? color : Palette.of(context).mood(m.value), semanticLabel: m.label);
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models.dart';

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
    final p = moodPreset(mood);
    return Icon(_faces[p.value], size: size, color: muted ? color : p.color, semanticLabel: p.label);
  }
}

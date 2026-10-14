// Pieces shared by the photo scanners (memo_sheet, list_scan_sheet): the bottom
// sheet itself, the big choice buttons, the photo preview, and the reading and
// failed states.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';
import 'ui.dart';

/// A scanner's sheet: grab handle, label and title, close, then [body]. [tall]
/// fills most of the screen (for long reviews); otherwise it fits its content.
class ScanSheet extends StatelessWidget {
  const ScanSheet({super.key, required this.label, required this.title, required this.body, this.tall = false});

  final String label;
  final String title;
  final Widget body;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: tall ? 0.94 : null,
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: p.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: p.inkA(0.2), borderRadius: BorderRadius.circular(4))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Label(label),
                          const SizedBox(height: 4),
                          Text(title, style: displayStyle(p, 30)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, color: p.muted(0.4)),
                    ),
                  ],
                ),
              ),
              Divider(color: p.line, height: 1),
              if (tall) Expanded(child: body) else Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the big "Take photo" / "Choose…" buttons.
class ScanChoice extends StatelessWidget {
  const ScanChoice({super.key, required this.icon, required this.label, required this.primary, required this.onTap});

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = primary ? p.onAccent : p.muted(0.85);
    return SizedBox(
      height: 104,
      child: Material(
        color: primary ? p.accent : p.inkA(0.02),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: primary ? BorderSide.none : BorderSide(color: p.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: fg),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: bodyStyle(p, 14, weight: FontWeight.w600, color: fg, height: 1.25)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo being read, fitted into [maxHeight].
class ScanPreview extends StatelessWidget {
  const ScanPreview({super.key, required this.photo, required this.maxHeight});

  final Uint8List? photo;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => photo == null
      ? const SizedBox.shrink()
      : ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(photo!, fit: BoxFit.contain),
          ),
        );
}

/// The photo with a spinner and [text] ("Reading the memo…").
class ScanReading extends StatelessWidget {
  const ScanReading({super.key, required this.photo, required this.text});

  final Uint8List? photo;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScanPreview(photo: photo, maxHeight: 220),
          const SizedBox(height: 18),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
            const SizedBox(width: 10),
            Text(text, style: bodyStyle(p, 14, color: p.muted(0.75))),
          ]),
          const SizedBox(height: 6),
          Text('Usually a few seconds.', style: bodyStyle(p, 12, color: p.muted(0.5))),
        ],
      ),
    );
  }
}

/// What went wrong, with Try again.
class ScanFailed extends StatelessWidget {
  const ScanFailed({super.key, required this.photo, required this.message, required this.onRetry});

  final Uint8List? photo;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScanPreview(photo: photo, maxHeight: 160),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(message, textAlign: TextAlign.center, style: bodyStyle(p, 14, color: p.expense)),
          ),
          const SizedBox(height: 16),
          HairlineButton(
            height: 44,
            onPressed: onRetry,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.rotateCcw, size: 16, color: p.muted(0.8)),
              const SizedBox(width: 8),
              Text('Try again', style: bodyStyle(p, 14, color: p.muted(0.85))),
            ]),
          ),
        ],
      ),
    );
  }
}

/// An amber note: [lead] in bold, then [text] ("New categories … will be created").
class ScanNotice extends StatelessWidget {
  const ScanNotice({super.key, required this.lead, required this.text});

  final String lead;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: p.accentA(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accentA(0.3)),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: lead, style: TextStyle(fontWeight: FontWeight.w600, color: p.accent)),
          TextSpan(text: text),
        ]),
        style: bodyStyle(p, 12.5, color: p.muted(0.75), height: 1.45),
      ),
    );
  }
}

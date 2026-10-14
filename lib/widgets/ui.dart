// Shared building blocks that mirror the web's component classes
// (.card, .label, .entry-btn, .hairline, segmented controls, pill switches).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';

/// `.card`: hairline border, card fill, soft lift on light; lit slab on black.
class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 10, this.margin});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: r,
        border: Border.all(color: p.line),
        boxShadow: p.dark
            ? const [BoxShadow(color: Color(0xF2000000), blurRadius: 40, offset: Offset(0, 14), spreadRadius: -22)]
            : const [
                BoxShadow(color: Color(0x0D181512), blurRadius: 2, offset: Offset(0, 1)),
                BoxShadow(color: Color(0x29181512), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -14),
              ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(
          children: [
            if (p.dark) ...[
              // Lit top-left corner (accent) + top-down sheen, like the web's dark cards.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.3,
                      colors: [p.accentA(0.07), p.accentA(0)],
                      stops: const [0, 0.42],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x0AFFFFFF), Color(0x00FFFFFF)],
                      stops: [0, 0.46],
                    ),
                  ),
                ),
              ),
            ],
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// `.label`: mono, uppercase, wide tracking, muted.
class Label extends StatelessWidget {
  const Label(this.text, {super.key, this.color, this.size = 11});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: Fonts.mono,
        fontSize: size,
        letterSpacing: size * 0.18,
        height: 1.4,
        color: color ?? p.labelColor,
      ),
    );
  }
}

/// Page header: kicker label + display title with an italic accent phrase.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.kicker, required this.title, required this.accent, this.trailing, this.below, this.size = 42, this.joined = false});

  final String kicker;
  final String title;
  final String accent;
  final Widget? trailing;
  final Widget? below;
  final double size;
  final bool joined; // no space between title and accent

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Label(kicker),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: title.isEmpty || joined ? title : '$title '),
                    TextSpan(text: accent, style: accentItalic(p, size)),
                  ]),
                  style: displayStyle(p, size),
                ),
                if (below != null) ...[const SizedBox(height: 8), below!],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// Section title inside cards: serif + italic accent ("Spent by category").
class CardTitle extends StatelessWidget {
  const CardTitle(this.title, this.accent, {super.key, this.size = 19});

  final String title;
  final String accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Text.rich(
      TextSpan(children: [TextSpan(text: '$title '), TextSpan(text: accent, style: accentItalic(p, size))]),
      style: displayStyle(p, size),
    );
  }
}

/// `.entry-btn`: solid accent block button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed, this.expand = false, this.height = 46, this.busy = false, this.semanticLabel});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;
  final double height;
  final bool busy;
  final String? semanticLabel; // for icon-only buttons

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onPressed != null && !busy;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent))
        else if (icon != null)
          Icon(icon, size: 16, color: p.onAccent),
        if ((busy || icon != null) && label.isNotEmpty) const SizedBox(width: 8),
        if (label.isNotEmpty)
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: bodyStyle(p, 14, weight: FontWeight.w600, color: p.onAccent)),
          ),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [BoxShadow(color: p.accentA(p.dark ? 0.45 : 0.5), blurRadius: p.dark ? 26 : 16, offset: Offset(0, p.dark ? 8 : 6), spreadRadius: -8)]
              : null,
        ),
        child: Material(
          color: p.accent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onPressed : null,
            child: Semantics(
              label: semanticLabel,
              button: true,
              child: Padding(padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 0 : 16), child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.hairline` square icon button (prev / next / small actions).
class HairlineIconButton extends StatelessWidget {
  const HairlineIconButton({super.key, required this.icon, this.onPressed, this.size = 40, this.tooltip, this.color});

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final btn = Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: 16, color: color ?? p.muted(0.6))),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Bordered pill/box button with text (TODAY, Now, Log in, …).
class HairlineButton extends StatelessWidget {
  const HairlineButton({super.key, required this.child, this.onPressed, this.height = 40, this.padding = const EdgeInsets.symmetric(horizontal: 14), this.radius = 12, this.borderColor, this.fill});

  final Widget child;
  final VoidCallback? onPressed;
  final double height;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: fill ?? Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: borderColor ?? p.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onPressed,
          child: Container(height: height, padding: padding, alignment: Alignment.center, child: child),
        ),
      ),
    );
  }
}

/// Segmented control (`seg-on`: tint on black, raised white pill on paper).
class SegTabs<T> extends StatelessWidget {
  const SegTabs({super.key, required this.options, required this.value, required this.onChanged, this.label, this.compact = false, this.expand = false});

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T)? label;
  final bool compact;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget tab(T o) {
      final on = o == value;
      final text = label?.call(o) ?? '$o';
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(o),
        child: Semantics(
          button: true,
          selected: on,
          label: text,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: compact ? 6 : 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: on ? (p.dark ? p.inkA(0.08) : p.card) : Colors.transparent,
              boxShadow: on && !p.dark
                  ? const [
                      BoxShadow(color: Color(0x1A181512), blurRadius: 2, offset: Offset(0, 1)),
                      BoxShadow(color: Color(0x0F181512), blurRadius: 0, spreadRadius: 1),
                    ]
                  : null,
            ),
            child: ExcludeSemantics(
              child: Text(
                text,
                style: bodyStyle(p, compact ? 11.5 : 12.5, weight: FontWeight.w500, color: on ? p.accent : p.muted(0.45)),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
        color: p.inkA(0.02),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final o in options) expand ? Expanded(child: tab(o)) : tab(o),
        ],
      ),
    );
  }
}

/// Pill switch (Vault Mode / dashboard sections).
class PillSwitch extends StatelessWidget {
  const PillSwitch({super.key, required this.on, this.width = 36, this.height = 20});

  final bool on;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final knob = height - 4;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height),
        color: on ? p.accentA(0.7) : p.inkA(0.2),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.all(2),
          width: knob,
          height: knob,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.card,
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}

/// Chip-style option button (filters, mood tags).
class OptionChip extends StatelessWidget {
  const OptionChip({super.key, required this.label, required this.selected, required this.onTap, this.round = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = BorderRadius.circular(round ? 99 : 9);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? p.accentA(round ? 0.15 : 0.08) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: selected ? p.accentA(round ? 0.5 : 0.4) : p.line),
        ),
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: round ? 7 : 8),
            child: ExcludeSemantics(
              child: Text(label,
                  style: bodyStyle(p, 12.5, weight: FontWeight.w500, color: selected ? p.accent : p.muted(0.55))),
            ),
          ),
        ),
      ),
    );
  }
}

/// Category initial badge (letter on a pale tint of the category color).
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.name, required this.color, this.size = 36});

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: bodyStyle(p, 12, weight: FontWeight.w700, color: p.tintText(color)),
      ),
    );
  }
}

/// Empty-state card.
class EmptyCard extends StatelessWidget {
  const EmptyCard(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CardBox(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Column(
          children: [
            Text(text, textAlign: TextAlign.center, style: bodyStyle(p, 14, color: p.muted(0.4), height: 1.5)),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      ),
    );
  }
}

/// Labeled form field row (label above control).
class FieldBlock extends StatelessWidget {
  const FieldBlock({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Label(label), const SizedBox(height: 7), child],
      );
}

/// Taka-prefixed amount field.
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.hint = '0', this.large = false, this.onSubmitted, this.autofocus = false, this.semanticLabel});

  final TextEditingController controller;
  final String hint;
  final bool large;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onSubmitted: onSubmitted,
      style: monoStyle(p, large ? 28 : 14, weight: large ? FontWeight.w600 : FontWeight.w400),
      decoration: InputDecoration(
        hintText: hint,
        labelText: null,
        semanticCounterText: semanticLabel,
        hintStyle: monoStyle(p, large ? 28 : 14, color: p.muted(0.3)),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: large ? 14 : 13),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Text('৳', style: monoStyle(p, large ? 24 : 14, color: p.muted(0.4))),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

/// Parse a typed amount ("1,250.5" -> 1250.5); null when not a positive number.
double? parseAmount(String s) {
  final v = double.tryParse(s.replaceAll(',', '').trim());
  return v != null && v > 0 ? v : null;
}

/// Standard snack for failed actions.
void showError(BuildContext context, Object e) {
  final msg = e.toString().replaceFirst('Exception: ', '');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Confirm before destroying data.
Future<bool> confirm(BuildContext context, String title, {String action = 'Delete'}) async {
  final p = Palette.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: displayStyle(p, 22)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel', style: TextStyle(color: p.muted(0.6)))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action, style: TextStyle(color: p.expense))),
      ],
    ),
  );
  return ok ?? false;
}

/// Small trailing trash button used in lists.
class TrashButton extends StatelessWidget {
  const TrashButton({super.key, required this.onPressed, this.tooltip = 'Delete'});

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(LucideIcons.trash2, size: 16, color: p.muted(0.3)),
    );
  }
}

/// Bordered button that opens the date picker.
class DateButton extends StatelessWidget {
  const DateButton({super.key, required this.value, required this.hint, required this.onPicked, this.lastDate});

  final DateTime? value;
  final String hint;
  final ValueChanged<DateTime?> onPicked;
  final DateTime? lastDate; // latest pickable day (e.g. today for things that already happened)

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return HairlineButton(
      height: 44,
      fill: p.inkA(0.02),
      onPressed: () async {
        final last = lastDate ?? DateTime(2100);
        final initial = value ?? DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: initial.isAfter(last) ? last : initial,
          firstDate: DateTime(2000),
          lastDate: last,
        );
        onPicked(d ?? value);
      },
      child: Text(value == null ? hint : fmt(value!, 'MMM d, yyyy'), style: bodyStyle(p, 13.5, color: value == null ? p.muted(0.35) : p.ink)),
    );
  }
}

/// Simple styled dropdown (bordered like inputs).
class AppDropdown extends StatelessWidget {
  const AppDropdown({super.key, required this.value, required this.items, required this.labelOf, required this.onChanged});

  final String value;
  final List<String> items;
  final String Function(String) labelOf;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line), color: p.card),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : (items.isEmpty ? null : items.first),
          isExpanded: true,
          dropdownColor: p.card,
          borderRadius: BorderRadius.circular(12),
          style: bodyStyle(p, 14),
          icon: Icon(LucideIcons.chevronDown, size: 16, color: p.muted(0.5)),
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(labelOf(i)))],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ),
    );
  }
}

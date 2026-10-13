// Dashboard charts — custom painted to match the web (Recharts) versions:
// period controls, donuts, horizontal frequency bars and the mood × money trend.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/math.dart';
import '../util/range.dart';
import 'mood_face.dart';
import 'ui.dart';

const _fallback = Color(0xFF7A746A);

/// Day / Week / Month / Year + prev / Now / next — the dashboard's single period
/// selector. [ranges] narrows the choice (the AI summaries offer Week / Month / Year).
class RangeControls extends StatelessWidget {
  const RangeControls({super.key, required this.range, required this.offset, required this.onRange, required this.onOffset, this.ranges = Range.values});

  final Range range;
  final int offset;
  final ValueChanged<Range> onRange;
  final ValueChanged<int> onOffset;
  final List<Range> ranges;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        SegTabs<Range>(
          options: ranges,
          value: range,
          compact: true,
          label: rangeName,
          onChanged: (r) {
            onRange(r);
            onOffset(0);
          },
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HairlineIconButton(icon: LucideIcons.chevronLeft, size: 34, tooltip: 'Previous period', onPressed: () => onOffset(offset - 1)),
            const SizedBox(width: 4),
            HairlineButton(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: offset == 0 ? null : () => onOffset(0),
              child: Text('NOW', style: monoStyle(p, 10.5, color: p.muted(0.6), letterSpacing: 1.2)),
            ),
            const SizedBox(width: 4),
            HairlineIconButton(
              icon: LucideIcons.chevronRight,
              size: 34,
              tooltip: 'Next period',
              onPressed: offset >= 0 ? null : () => onOffset(math.min(0, offset + 1)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- donuts

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.colors);

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    final outer = math.min(size.width, size.height) / 2;
    final inner = outer * 58 / 84;
    final mid = (outer + inner) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: mid);
    final gap = values.length > 1 ? 2 * math.pi / 180 : 0.0;
    final avail = 2 * math.pi - gap * values.length;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * avail;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = outer - inner
          ..color = colors[i],
      );
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values != values || old.colors != colors;
}

class _Slice {
  const _Slice(this.name, this.value, this.color, {this.mood});
  final String name;
  final double value;
  final Color color;
  final int? mood;
}

/// Donut with a center caption and a legend list underneath.
class _DonutBlock extends StatelessWidget {
  const _DonutBlock({required this.slices, this.legend, required this.centerLabel, required this.centerValue, this.centerColor, required this.legendValue});

  final List<_Slice> slices;
  final List<_Slice>? legend; // defaults to [slices]
  final String centerLabel;
  final String centerValue;
  final Color? centerColor;
  final String Function(_Slice) legendValue;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 176,
          height: 176,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _DonutPainter([for (final s in slices) s.value], [for (final s in slices) s.color])),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Label(centerLabel),
                  const SizedBox(height: 2),
                  Text(centerValue, style: monoStyle(p, 17, weight: FontWeight.w600, color: centerColor ?? p.ink)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final s in legend ?? slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                if (s.mood != null)
                  MoodFace(s.mood!, size: 16)
                else
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(s.name, style: bodyStyle(p, 14, color: p.muted(0.65)))),
                Text(legendValue(s), style: monoStyle(p, 13.5, color: p.muted(0.5))),
              ],
            ),
          ),
      ],
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Center(child: Text(text, textAlign: TextAlign.center, style: bodyStyle(p, 14, color: p.muted(0.35)))),
    );
  }
}

/// Spent / Earned by category.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({super.key, required this.transactions, required this.categories, required this.kind, required this.window});

  final List<Txn> transactions;
  final List<Category> categories;
  final Kind kind;
  final Window window;

  @override
  Widget build(BuildContext context) {
    final colorOf = {for (final c in categories) c.name: hexColor(c.color)};
    final totals = <String, double>{};
    for (final t in transactions) {
      if (t.kind != kind || !inRange(t.occurredOn, window.startKey, window.endKey)) continue;
      totals[t.categoryName] = (totals[t.categoryName] ?? 0) + t.amount;
    }
    final slices = [for (final e in totals.entries) _Slice(e.key, e.value, colorOf[e.key] ?? _fallback)]
      ..sort((a, b) => b.value.compareTo(a.value));
    if (slices.isEmpty) return _NoData(kind == Kind.expense ? 'No spending this period.' : 'No income this period.');
    final total = slices.fold<double>(0, (s, x) => s + x.value);
    return _DonutBlock(
      slices: slices.take(6).toList(),
      centerLabel: kind == Kind.expense ? 'Spent' : 'Earned',
      centerValue: formatCurrency(total),
      legendValue: (s) => formatCurrency(s.value),
    );
  }
}

/// Mood distribution (count of logs per mood level).
class MoodDonut extends StatelessWidget {
  const MoodDonut({super.key, required this.moods, required this.window});

  final List<MoodLog> moods;
  final Window window;

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{};
    for (final m in moods) {
      if (!inRange(m.loggedOn, window.startKey, window.endKey)) continue;
      counts[m.mood] = (counts[m.mood] ?? 0) + 1;
    }
    final slices = [
      for (final p in moodPresets)
        if ((counts[p.value] ?? 0) > 0) _Slice(p.label, (counts[p.value] ?? 0).toDouble(), p.color, mood: p.value),
    ];
    if (slices.isEmpty) return const _NoData('No moods logged this period.');
    final total = slices.fold<double>(0, (s, x) => s + x.value);
    return _DonutBlock(
      slices: slices,
      centerLabel: 'Logs',
      centerValue: total.toInt().toString(),
      legendValue: (s) => '${s.value.toInt()} ${s.value == 1 ? 'log' : 'logs'}',
    );
  }
}

/// Savings: added (saving entries) vs broken (Break-saving expenses); Vault Mode folds in all flow.
class SavingsDonut extends StatelessWidget {
  const SavingsDonut({super.key, required this.transactions, required this.window, required this.vaultMode});

  final List<Txn> transactions;
  final Window window;
  final bool vaultMode;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    double added = 0, broken = 0;
    for (final t in transactions) {
      if (!inRange(t.occurredOn, window.startKey, window.endKey)) continue;
      if (t.kind == Kind.saving) {
        added += t.amount;
      } else if (t.kind == Kind.expense && t.categoryName == breakSaving) {
        broken += t.amount;
      } else if (vaultMode && t.kind == Kind.income) {
        added += t.amount;
      } else if (vaultMode && t.kind == Kind.expense) {
        broken += t.amount;
      }
    }
    const addedColor = Color(0xFF3D80BC), brokenColor = Color(0xFFCB453B);
    final slices = [
      if (added > 0) _Slice('Added', added, addedColor),
      if (broken > 0) _Slice('Broken', broken, brokenColor),
    ];
    if (slices.isEmpty) return const _NoData('No saving activity this period.');
    final net = added - broken;
    return _DonutBlock(
      slices: slices,
      legend: const [_Slice('Added', 0, addedColor), _Slice('Broken', 0, brokenColor)]
          .map((s) => _Slice(s.name, s.name == 'Added' ? added : broken, s.color))
          .toList(),
      centerLabel: 'Net',
      centerValue: formatCurrency(net, sign: true),
      centerColor: net >= 0 ? p.saving : p.expense,
      legendValue: (s) => formatCurrency(s.value),
    );
  }
}

// ---------------------------------------------------------------- bars

/// Horizontal frequency bars with a small count axis (mood tags / categories).
class HBars extends StatelessWidget {
  const HBars({super.key, required this.bars, this.labelWidth = 104});

  final List<(String, int, Color)> bars;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final maxCount = bars.fold<int>(1, (m, b) => math.max(m, b.$2));
    final step = maxCount <= 4 ? 1 : maxCount <= 8 ? 2 : maxCount <= 20 ? 5 : (maxCount / 4).ceil();
    final top = math.max(4, (maxCount / step).ceil() * step);
    final ticks = [for (var t = 0; t <= top; t += step) t];
    return Column(
      children: [
        for (final b in bars)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(b.$1,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: bodyStyle(p, 12, color: p.muted(0.7))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth * b.$2 / top;
                      return Row(
                        children: [
                          Container(
                            width: math.max(4, w - 26),
                            height: 18,
                            decoration: BoxDecoration(color: b.$3, borderRadius: BorderRadius.circular(3)),
                          ),
                          const SizedBox(width: 6),
                          Text('${b.$2}', style: monoStyle(p, 11, color: p.muted(0.5))),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(width: labelWidth + 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => SizedBox(
                  height: 14,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final t in ticks)
                        Positioned(
                          left: (c.maxWidth - 26) * t / top - 4,
                          child: Text('$t', style: monoStyle(p, 10.5, color: p.muted(0.5))),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

const _tagColors = [
  Color(0xFF3D80BC), Color(0xFF7A4E86), Color(0xFFC06A33), Color(0xFF2E8159), Color(0xFFCB453B),
  Color(0xFF3D80BC), Color(0xFFA6694A), Color(0xFF7A4E86), Color(0xFF6E8C46), Color(0xFF8E5B6E),
  Color(0xFFB59A3C), Color(0xFF2F6F6B),
];

class MoodTagBars extends StatelessWidget {
  const MoodTagBars({super.key, required this.moods, required this.window});

  final List<MoodLog> moods;
  final Window window;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final m in moods) {
      if (!inRange(m.loggedOn, window.startKey, window.endKey)) continue;
      for (final tag in m.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList();
    final bars = [for (final (i, e) in entries.indexed) (e.key, e.value, _tagColors[i % _tagColors.length])]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (bars.isEmpty) return const _NoData('No mood tags logged this period.');
    return HBars(bars: bars.take(10).toList());
  }
}

class CategoryBars extends StatelessWidget {
  const CategoryBars({super.key, required this.transactions, required this.categories, required this.window});

  final List<Txn> transactions;
  final List<Category> categories;
  final Window window;

  @override
  Widget build(BuildContext context) {
    final colorOf = {for (final c in categories) c.name: hexColor(c.color)};
    final counts = <String, int>{};
    for (final t in transactions) {
      if (t.kind == Kind.saving || !inRange(t.occurredOn, window.startKey, window.endKey)) continue;
      counts[t.categoryName] = (counts[t.categoryName] ?? 0) + 1;
    }
    final bars = [for (final e in counts.entries) (e.key, e.value, colorOf[e.key] ?? _fallback)]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (bars.isEmpty) return const _NoData('No transactions this period.');
    return HBars(bars: bars.take(10).toList());
  }
}

// ---------------------------------------------------------------- trend

class TrendPoint {
  const TrendPoint(this.key, this.label, this.net, this.saving, this.mood);
  final String key;
  final String label;
  final double net; // income - expense
  final double saving; // positive saving contribution
  final double? mood;
}

double? _avg(List<int> xs) =>
    xs.isEmpty ? null : (xs.fold<int>(0, (a, b) => a + b) / xs.length * 10).round() / 10;

/// Buckets for the trend chart (port of the web's buildPoints).
(List<TrendPoint>, String) buildTrendPoints(List<Txn> transactions, List<MoodLog> moods, Range range, int offset) {
  final now = DateTime.now();
  double delta(Txn t) => t.kind == Kind.income ? t.amount : t.kind == Kind.expense ? -t.amount : 0;
  double r2(double v) => (v * 100).round() / 100;

  if (range == Range.day) {
    final day = DateTime(now.year, now.month, now.day + offset);
    final key = toDateKey(day);
    final net = List<double>.filled(24, 0), sav = List<double>.filled(24, 0);
    final md = List.generate(24, (_) => <int>[]);
    for (final t in transactions) {
      if (t.occurredOn != key) continue;
      final h = parseTs(t.occurredAt).hour;
      if (t.kind == Kind.saving) {
        sav[h] += t.amount;
      } else {
        net[h] += delta(t);
      }
    }
    for (final m in moods) {
      if (m.loggedOn != key) continue;
      md[parseTs(m.loggedAt).hour].add(m.mood);
    }
    final pts = [
      for (var h = 0; h < 24; h++)
        TrendPoint('h$h', fmt(DateTime(2000, 1, 1, h), 'ha'), r2(net[h]), r2(sav[h]), _avg(md[h])),
    ];
    return (pts, fmt(day, 'EEE, MMM d, yyyy'));
  }

  final netBy = <String, double>{}, savBy = <String, double>{};
  for (final t in transactions) {
    if (t.kind == Kind.saving) {
      savBy[t.occurredOn] = (savBy[t.occurredOn] ?? 0) + t.amount;
    } else {
      netBy[t.occurredOn] = (netBy[t.occurredOn] ?? 0) + delta(t);
    }
  }
  final moodBy = <String, List<int>>{};
  for (final m in moods) {
    (moodBy[m.loggedOn] ??= []).add(m.mood);
  }

  if (range == Range.year) {
    final y = now.year + offset;
    final pts = <TrendPoint>[];
    for (var mo = 1; mo <= 12; mo++) {
      final ym = '$y-${mo.toString().padLeft(2, '0')}';
      double n = 0, s = 0;
      final mv = <int>[];
      netBy.forEach((k, v) {
        if (k.startsWith(ym)) n += v;
      });
      savBy.forEach((k, v) {
        if (k.startsWith(ym)) s += v;
      });
      moodBy.forEach((k, v) {
        if (k.startsWith(ym)) mv.addAll(v);
      });
      pts.add(TrendPoint(ym, fmt(DateTime(y, mo), 'MMM'), r2(n), r2(s), _avg(mv)));
    }
    return (pts, '$y');
  }

  late DateTime start, end;
  late String label;
  if (range == Range.week) {
    final a = DateTime(now.year, now.month, now.day + offset * 7);
    start = startOfWeek(a);
    end = endOfWeek(a);
    label = '${fmt(start, 'MMM d')} – ${fmt(end, 'MMM d')}';
  } else {
    final a = DateTime(now.year, now.month + offset, 1);
    start = startOfMonth(a);
    end = endOfMonth(a);
    label = fmt(a, 'MMMM yyyy');
  }
  final pts = [
    for (final d in daysBetween(start, end))
      TrendPoint(toDateKey(d), fmt(d, range == Range.week ? 'EEE' : 'MMM d'), r2(netBy[toDateKey(d)] ?? 0),
          r2(savBy[toDateKey(d)] ?? 0), _avg(moodBy[toDateKey(d)] ?? const [])),
  ];
  return (pts, label);
}

/// Mood × money card: header, correlation, period controls, dual-axis plot.
class TrendCard extends StatefulWidget {
  const TrendCard({
    super.key,
    required this.transactions,
    required this.moods,
    required this.range,
    required this.offset,
    required this.onRange,
    required this.onOffset,
    required this.plotHeight,
  });

  final List<Txn> transactions;
  final List<MoodLog> moods;
  final Range range;
  final int offset;
  final ValueChanged<Range> onRange;
  final ValueChanged<int> onOffset;
  final double plotHeight;

  @override
  State<TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<TrendCard> {
  int? _sel;

  @override
  void didUpdateWidget(TrendCard old) {
    super.didUpdateWidget(old);
    if (old.range != widget.range || old.offset != widget.offset) _sel = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (points, periodLabel) = buildTrendPoints(widget.transactions, widget.moods, widget.range, widget.offset);
    final paired = points.where((x) => x.mood != null).toList();
    final r = pearson([for (final x in paired) x.mood!], [for (final x in paired) x.net]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Label('Trend · $periodLabel')),
            Text('r = ${r.toStringAsFixed(2)}', style: monoStyle(p, 11, color: p.muted(0.4))),
          ],
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Mood '),
            TextSpan(text: '×', style: accentItalic(p, 20).copyWith(color: p.muted(0.5))),
            const TextSpan(text: ' money'),
          ]),
          style: displayStyle(p, 20),
        ),
        Text(correlationLabel(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle(p, 11, color: p.muted(0.4))),
        const SizedBox(height: 12),
        RangeControls(range: widget.range, offset: widget.offset, onRange: widget.onRange, onOffset: widget.onOffset),
        const SizedBox(height: 12),
        SizedBox(
          height: widget.plotHeight,
          child: LayoutBuilder(
            builder: (context, c) {
              final geo = _TrendGeometry(Size(c.maxWidth, widget.plotHeight), points.length);
              int indexAt(Offset o) => geo.indexAt(o.dx).clamp(0, points.length - 1);
              final sel = _sel;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => setState(() => _sel = _sel == indexAt(d.localPosition) ? null : indexAt(d.localPosition)),
                onHorizontalDragUpdate: (d) => setState(() => _sel = indexAt(d.localPosition)),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TrendPainter(
                          points: points,
                          palette: p,
                          byMonth: widget.range == Range.year,
                          dots: widget.range == Range.day || widget.range == Range.week,
                          selected: sel,
                        ),
                      ),
                    ),
                    if (sel != null && sel < points.length)
                      Positioned(
                        top: 0,
                        left: (geo.bandCenter(sel) - 70).clamp(0, math.max(0, c.maxWidth - 140)).toDouble(),
                        child: IgnorePointer(child: _TrendTip(point: points[sel])),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrendTip extends StatelessWidget {
  const _TrendTip({required this.point});
  final TrendPoint point;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.line),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(point.label, style: monoStyle(p, 11, color: p.muted(0.5))),
          Text('Net ${formatCurrency(point.net, sign: true)}',
              style: bodyStyle(p, 12, color: point.net >= 0 ? p.income : p.expense)),
          if (point.saving > 0) Text('Saving +${formatCurrency(point.saving)}', style: bodyStyle(p, 12, color: p.saving)),
          Text('Mood ${point.mood?.toString() ?? '—'}${point.mood != null ? ' / 5' : ''}',
              style: bodyStyle(p, 12, color: const Color(0xFF9268A0))),
        ],
      ),
    );
  }
}

class _TrendGeometry {
  _TrendGeometry(this.size, this.n);
  final Size size;
  final int n;
  final double left = 46, right = 22, top = 8, bottom = 22;

  double get plotW => math.max(1, size.width - left - right);
  double get plotH => math.max(1, size.height - top - bottom);
  double get band => plotW / math.max(1, n);
  double bandCenter(int i) => left + band * (i + 0.5);
  int indexAt(double x) => ((x - left) / band).floor();
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.palette, required this.byMonth, required this.dots, required this.selected});

  final List<TrendPoint> points;
  final Palette palette;
  final bool byMonth;
  final bool dots;
  final int? selected;

  static const _moodColor = Color(0xFF7A4E86);

  void _text(Canvas canvas, String s, Offset at, Color color, {TextAlign align = TextAlign.left, double size = 10.5}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: Fonts.body, fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final g = _TrendGeometry(size, points.length);
    final p = palette;

    // Money axis: nice ticks over [min(0, nets), max(0, nets, savings)].
    var lo = 0.0, hi = 0.0;
    for (final x in points) {
      lo = math.min(lo, x.net);
      hi = math.max(hi, math.max(x.net, x.saving));
    }
    if (hi == lo) hi = lo + 1;
    final rough = (hi - lo) / 4;
    final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final norm = rough / mag;
    final step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag;
    final nMin = (lo / step).floor() * step, nMax = (hi / step).ceil() * step;
    double y(double v) => g.top + (nMax - v) / (nMax - nMin) * g.plotH;
    double ym(double m) => g.top + (5 - m) / 5 * g.plotH;

    final grid = Paint()
      ..color = p.inkA(0.08)
      ..strokeWidth = 1;
    final axisText = p.inkA(0.55);
    for (var t = nMin; t <= nMax + step / 2; t += step) {
      canvas.drawLine(Offset(g.left, y(t)), Offset(size.width - g.right, y(t)), grid);
      _text(canvas, compactCurrency(t), Offset(g.left - 6, y(t)), axisText, align: TextAlign.right);
    }
    for (var m = 1; m <= 5; m++) {
      _text(canvas, '$m', Offset(size.width - g.right + 7, ym(m.toDouble())), const Color(0xFF9268A0));
    }

    // Selected band highlight.
    if (selected != null && selected! >= 0 && selected! < points.length) {
      canvas.drawRect(
        Rect.fromLTWH(g.left + g.band * selected!, g.top, g.band, g.plotH),
        Paint()..color = p.inkA(0.06),
      );
    }

    // Zero line.
    canvas.drawLine(Offset(g.left, y(0)), Offset(size.width - g.right, y(0)), Paint()..color = p.inkA(0.18));

    // Bars: net (green / red) + saving (blue), side by side within each band.
    final maxBar = byMonth ? 24.0 : 14.0;
    final barW = math.min(maxBar, math.max(1.0, (g.band * 0.8 - 2) / 2));
    for (var i = 0; i < points.length; i++) {
      final c = g.bandCenter(i);
      void bar(double x0, double v, Color color) {
        if (v == 0) return;
        final top = math.min(y(v), y(0)), bot = math.max(y(v), y(0));
        final rr = RRect.fromRectAndCorners(
          Rect.fromLTRB(x0, top, x0 + barW, bot),
          topLeft: v > 0 ? const Radius.circular(3) : Radius.zero,
          topRight: v > 0 ? const Radius.circular(3) : Radius.zero,
          bottomLeft: v < 0 ? const Radius.circular(3) : Radius.zero,
          bottomRight: v < 0 ? const Radius.circular(3) : Radius.zero,
        );
        canvas.drawRRect(rr, Paint()..color = color);
      }

      bar(c - barW - 1, points[i].net, points[i].net >= 0 ? const Color(0xFF2E8159) : const Color(0xFFCB453B));
      bar(c + 1, points[i].saving, const Color(0xFF3D80BC));
    }

    // Mood line (monotone cubic through logged buckets, gaps connected).
    final pts = [
      for (var i = 0; i < points.length; i++)
        if (points[i].mood != null) Offset(g.bandCenter(i), ym(points[i].mood!)),
    ];
    if (pts.length >= 2) {
      canvas.drawPath(
        _monotone(pts),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _moodColor,
      );
    }
    if (dots || pts.length == 1) {
      for (final o in pts) {
        canvas.drawCircle(o, 3, Paint()..color = _moodColor);
      }
    }

    // X labels: first, last and evenly spaced ones that fit.
    final maxChars = points.fold<int>(1, (m, x) => math.max(m, x.label.length));
    final labelW = maxChars * 6.0 + 14;
    final every = math.max(1, (labelW / g.band).ceil());
    final shown = <int>[for (var i = 0; i < points.length; i += every) i];
    final last = points.length - 1;
    if (shown.last != last) {
      if ((last - shown.last) * g.band < labelW) shown.removeLast();
      shown.add(last);
    }
    for (final i in shown) {
      _text(canvas, points[i].label, Offset(g.bandCenter(i), size.height - g.bottom / 2 + 2), axisText, align: TextAlign.center);
    }
  }

  Path _monotone(List<Offset> pts) {
    final n = pts.length;
    final dx = [for (var i = 0; i < n - 1; i++) pts[i + 1].dx - pts[i].dx];
    final m = [for (var i = 0; i < n - 1; i++) dx[i] == 0 ? 0.0 : (pts[i + 1].dy - pts[i].dy) / dx[i]];
    final t = List<double>.filled(n, 0);
    t[0] = m[0];
    t[n - 1] = m[n - 2];
    for (var i = 1; i < n - 1; i++) {
      t[i] = m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2;
    }
    for (var i = 0; i < n - 1; i++) {
      if (m[i] == 0) {
        t[i] = 0;
        t[i + 1] = 0;
        continue;
      }
      final a = t[i] / m[i], b = t[i + 1] / m[i];
      final h = a * a + b * b;
      if (h > 9) {
        final s = 3 / math.sqrt(h);
        t[i] = s * a * m[i];
        t[i + 1] = s * b * m[i];
      }
    }
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < n - 1; i++) {
      final d = dx[i] / 3;
      path.cubicTo(pts[i].dx + d, pts[i].dy + t[i] * d, pts[i + 1].dx - d, pts[i + 1].dy - t[i + 1] * d, pts[i + 1].dx, pts[i + 1].dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.palette != palette || old.selected != selected || old.byMonth != byMonth;
}

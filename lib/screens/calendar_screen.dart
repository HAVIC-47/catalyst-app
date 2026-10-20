// Calendar — port of the web's /app page: Week / Month fill the screen exactly,
// Year is a scrolling 12-month heatmap. Tap any day to log money or mood.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/mood_face.dart';
import '../widgets/ui.dart';
import 'entry_sheet.dart';

enum CalRange { week, month, year }

const _weekdayKeys = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
List<String> get _weekdays => [for (final d in _weekdayKeys) tr(d)];

class _Cell {
  double income = 0, expense = 0, net = 0;
  int moodSum = 0, moodN = 0;
  int? get mood => moodN == 0 ? null : (moodSum / moodN).round();
}

/// Month / week tint: mood base, then income and spend washes on top (theme-tuned).
Color _dayColor(_Cell? d, double maxFlow, Palette p) {
  if (d == null || (d.income + d.expense == 0 && d.mood == null)) return p.card;
  var c = p.card;
  final mood = d.mood;
  c = Color.alphaBlend(
    (mood != null ? p.mood(moodPreset(mood).value) : const Color(0xFF7A746A)).withValues(alpha: (mood != null ? 0.2 : 0.05) * p.tintMoodK),
    c,
  );
  final spendA = maxFlow > 0 ? math.min(0.42, d.expense / maxFlow * 0.48) : 0.0;
  final incomeA = maxFlow > 0 ? math.min(0.42, d.income / maxFlow * 0.48) : 0.0;
  if (incomeA > 0) c = Color.alphaBlend(p.tintIncome.withValues(alpha: incomeA * p.tintK), c);
  if (spendA > 0) c = Color.alphaBlend(p.tintSpend.withValues(alpha: spendA * p.tintK), c);
  return c;
}

/// Year heatmap tint: much stronger — the color is the only signal in tiny cells.
Color _yearColor(_Cell? d, double maxFlow, Palette p) {
  if (d == null || (d.income + d.expense == 0 && d.mood == null)) return p.inkA(0.04);
  var c = p.card;
  if (d.mood != null) c = Color.alphaBlend(p.mood(moodPreset(d.mood!).value).withValues(alpha: p.yrMood), c);
  final spendHeavier = d.expense >= d.income;
  final flow = spendHeavier ? d.expense : d.income;
  if (flow > 0) {
    final level = maxFlow > 0 ? math.sqrt(math.min(1, flow / maxFlow)) : 1.0;
    c = Color.alphaBlend((spendHeavier ? p.expense : p.saving).withValues(alpha: p.yrFloor + p.yrSpan * level), c);
  }
  return c;
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalRange _range = CalRange.month;
  DateTime _cursor = DateTime.now();

  Map<String, _Cell> _index(AppState app) {
    final map = <String, _Cell>{};
    for (final t in app.transactions) {
      final e = map.putIfAbsent(t.occurredOn, _Cell.new);
      if (t.kind == Kind.income) {
        e.income += t.amount;
        e.net += t.amount;
      } else {
        e.expense += t.amount;
        e.net -= t.amount;
      }
    }
    for (final m in app.moods) {
      final e = map.putIfAbsent(m.loggedOn, _Cell.new);
      e.moodSum += m.mood;
      e.moodN += 1;
    }
    return map;
  }

  void _step(int dir) => setState(() {
        final c = _cursor;
        _cursor = switch (_range) {
          CalRange.week => DateTime(c.year, c.month, c.day + 7 * dir),
          CalRange.month => DateTime(c.year, c.month + dir, 1),
          CalRange.year => DateTime(c.year + dir, c.month, 1),
        };
      });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final byDay = _index(app);

    late DateTime start, end;
    late String label;
    switch (_range) {
      case CalRange.week:
        start = startOfWeek(_cursor);
        end = endOfWeek(_cursor);
        label = '${fmt(start, 'MMM d')} – ${fmt(end, 'MMM d, yyyy')}';
      case CalRange.month:
        start = startOfMonth(_cursor);
        end = endOfMonth(_cursor);
        label = fmt(_cursor, 'MMMM yyyy');
      case CalRange.year:
        start = DateTime(_cursor.year, 1, 1);
        end = DateTime(_cursor.year, 12, 31);
        label = '${_cursor.year}';
    }
    final sk = toDateKey(start), ek = toDateKey(end);
    double income = 0, expense = 0, maxFlow = 0;
    var count = 0;
    byDay.forEach((k, v) {
      if (k.compareTo(sk) < 0 || k.compareTo(ek) > 0) return;
      income += v.income;
      expense += v.expense;
      if (v.income > 0 || v.expense > 0 || v.mood != null) count++;
      maxFlow = math.max(maxFlow, v.income + v.expense);
    });
    final net = income - expense;
    final screen = MediaQuery.of(context).size;
    // Scales with screen height (and width) so short phones keep room for the grid
    // and the active-days count still fits beside the title.
    final titleSize = math.min(screen.height * 0.044, screen.width * 0.084).clamp(26.0, 36.0);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title with the active-days count on its baseline; the count wraps below
        // only when the screen is too narrow for both.
        Text.rich(
          TextSpan(children: [
            TextSpan(text: label, style: displayStyle(p, titleSize).copyWith(height: 1.0)),
            // ~12px en space: a wrapped count then starts flush left, not indented.
            TextSpan(text: '\u2002', style: displayStyle(p, titleSize * 0.75).copyWith(height: 1.0)),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Label(app.loading ? tr('loading…') : trn(count, '{n} active day', '{n} active days')),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: tr('NET\u00A0')),
            TextSpan(text: formatCurrency(net, sign: true), style: TextStyle(color: net >= 0 ? p.income : p.expense)),
            TextSpan(text: '  ·  ', style: TextStyle(color: p.muted(0.3))),
            TextSpan(text: tr('IN\u00A0')),
            TextSpan(text: compactCurrency(income), style: TextStyle(color: p.income)),
            TextSpan(text: tr('  OUT\u00A0')),
            TextSpan(text: compactCurrency(expense), style: TextStyle(color: p.expense)),
          ]),
          style: monoStyle(p, 14, color: p.muted(0.45)),
        ),
        const SizedBox(height: 12),
        // Range tabs left, prev / today / next right. Narrow phones (or a large
        // display-size setting) get a tighter nav, and the tabs shrink a little
        // rather than push "next" off the screen.
        LayoutBuilder(builder: (context, box) {
          final tight = box.maxWidth < 340;
          final btn = tight ? 34.0 : 38.0;
          final gap = SizedBox(width: tight ? 4 : 6);
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SegTabs<CalRange>(
                    options: CalRange.values,
                    value: _range,
                    label: (r) => tr('${r.name[0].toUpperCase()}${r.name.substring(1)}'),
                    onChanged: (r) => setState(() {
                      _range = r;
                      _cursor = DateTime.now();
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                HairlineIconButton(icon: LucideIcons.chevronLeft, size: btn, tooltip: tr('Previous'), onPressed: () => _step(-1)),
                gap,
                HairlineButton(
                  height: btn,
                  padding: EdgeInsets.symmetric(horizontal: tight ? 8 : 12),
                  onPressed: () => setState(() => _cursor = DateTime.now()),
                  child: Text(tr('TODAY'), style: monoStyle(p, 11.5, color: p.muted(0.7), letterSpacing: 1.6)),
                ),
                gap,
                HairlineIconButton(icon: LucideIcons.chevronRight, size: btn, tooltip: tr('Next'), onPressed: () => _step(1)),
              ]),
            ],
          );
        }),
        const SizedBox(height: 12),
        _Legend(palette: p),
        const SizedBox(height: 10),
      ],
    );

    void open(DateTime d) => openEntry(context, date: toDateKey(d));

    if (_range == CalRange.year) {
      return RefreshIndicator(
        onRefresh: app.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [header, _YearView(year: _cursor.year, byDay: byDay, onTap: open)],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, cons) {
        final h = math.max(cons.maxHeight, 460.0);
        return RefreshIndicator(
          onRefresh: app.load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: h,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: _range == CalRange.month
                          ? _MonthGrid(cursor: _cursor, byDay: byDay, maxFlow: maxFlow, onTap: open)
                          : _WeekView(cursor: _cursor, byDay: byDay, maxFlow: maxFlow, onTap: open),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.palette});
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final style = monoStyle(p, 10, color: p.muted(0.4), letterSpacing: 1.4);
    Widget swatch(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));
    return Row(
      children: [
        Text(tr('MOOD'), style: style.copyWith(color: p.muted(0.55))),
        const SizedBox(width: 8),
        Container(
          width: 56,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(colors: [p.mood(1), p.mood(3), p.mood(5)]),
          ),
        ),
        const SizedBox(width: 16),
        swatch(p.tintSpend),
        const SizedBox(width: 6),
        Text(tr('SPEND'), style: style),
        const SizedBox(width: 16),
        swatch(p.tintIncome),
        const SizedBox(width: 6),
        Text(tr('INCOME'), style: style),
      ],
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      child: Row(
        children: [
          for (final d in _weekdays)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 2, 8),
                child: Text(d, style: monoStyle(p, 10, color: p.muted(0.35), letterSpacing: 1.2)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({required this.day, required this.today, this.size = 11});
  final DateTime day;
  final bool today;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final txt = day.day.toString().padLeft(2, '0');
    if (!today) return Text(txt, style: monoStyle(p, size, color: p.muted(0.7)));
    return Container(
      width: size * 1.9,
      height: size * 1.9,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
      child: Text(txt, style: monoStyle(p, size, weight: FontWeight.w600, color: p.paper)),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.cursor, required this.byDay, required this.maxFlow, required this.onTap});

  final DateTime cursor;
  final Map<String, _Cell> byDay;
  final double maxFlow;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ms = startOfMonth(cursor), me = endOfMonth(cursor);
    final days = daysBetween(startOfWeek(ms), endOfWeek(me));
    final weeks = [for (var i = 0; i < days.length; i += 7) days.sublist(i, i + 7)];
    final now = DateTime.now();
    return CardBox(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const _WeekdayRow(),
          Expanded(
            child: Column(
              children: [
                for (final (wi, w) in weeks.indexed)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (di, d) in w.indexed)
                          Expanded(
                            child: _MonthCell(
                              day: d,
                              data: byDay[toDateKey(d)],
                              color: _dayColor(byDay[toDateKey(d)], maxFlow, p),
                              inMonth: sameMonth(d, cursor),
                              today: sameDay(d, now),
                              lastCol: di == 6,
                              lastRow: wi == weeks.length - 1,
                              onTap: () => onTap(d),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.data,
    required this.color,
    required this.inMonth,
    required this.today,
    required this.lastCol,
    required this.lastRow,
    required this.onTap,
  });

  final DateTime day;
  final _Cell? data;
  final Color color;
  final bool inMonth, today, lastCol, lastRow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final d = data;
    final hasFlow = d != null && (d.income > 0 || d.expense > 0);
    final amountStyle = monoStyle(p, 10, letterSpacing: -0.2);
    return Opacity(
      opacity: inMonth ? 1 : 0.35,
      child: Semantics(
        button: true,
        label: fmt(day, 'MMMM d'),
        child: Material(
          color: color,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: lastCol ? BorderSide.none : BorderSide(color: p.line),
                  bottom: lastRow ? BorderSide.none : BorderSide(color: p.line),
                ),
              ),
              padding: const EdgeInsets.all(4),
              child: LayoutBuilder(
                builder: (context, c) {
                  final room = c.maxHeight;
                  return ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DayNumber(day: day, today: today),
                            const Spacer(),
                            if (d?.mood != null) MoodFace(d!.mood!, size: 14),
                          ],
                        ),
                        const Spacer(),
                        // Roomy cells: separate out / in lines; short ones: one net line.
                        if (hasFlow && room >= 48) ...[
                          if (d.expense > 0)
                            _Amount('−${compactCurrency(d.expense)}', amountStyle.copyWith(color: p.expense)),
                          if (d.income > 0)
                            _Amount('+${compactCurrency(d.income)}', amountStyle.copyWith(color: p.income)),
                        ] else if (hasFlow && room >= 30)
                          _Amount(
                            '${d.net >= 0 ? '+' : ''}${compactCurrency(d.net)}',
                            amountStyle.copyWith(color: d.net >= 0 ? p.income : p.expense),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line in a day cell. Never wraps (a wrapped "−৳13.3K" would show only the
/// sign); shrinks to fit a narrow cell instead.
class _Amount extends StatelessWidget {
  const _Amount(this.text, this.style);

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, softWrap: false, style: style),
      );
}

class _WeekView extends StatelessWidget {
  const _WeekView({required this.cursor, required this.byDay, required this.maxFlow, required this.onTap});

  final DateTime cursor;
  final Map<String, _Cell> byDay;
  final double maxFlow;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final days = daysBetween(startOfWeek(cursor), endOfWeek(cursor));
    final now = DateTime.now();
    return CardBox(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const _WeekdayRow(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, d) in days.indexed)
                  Expanded(
                    child: Material(
                      color: _dayColor(byDay[toDateKey(d)], maxFlow, p),
                      child: InkWell(
                        onTap: () => onTap(d),
                        child: Container(
                          decoration: BoxDecoration(border: Border(right: i == 6 ? BorderSide.none : BorderSide(color: p.line))),
                          padding: const EdgeInsets.all(6),
                          child: Builder(builder: (context) {
                            final c = byDay[toDateKey(d)];
                            final style = monoStyle(p, 10, letterSpacing: -0.2);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _DayNumber(day: d, today: sameDay(d, now), size: 12),
                                const SizedBox(height: 6),
                                if (c?.mood != null) MoodFace(c!.mood!, size: 20),
                                const Spacer(),
                                if ((c?.expense ?? 0) > 0)
                                  _Amount('−${compactCurrency(c!.expense)}', style.copyWith(color: p.expense)),
                                if ((c?.income ?? 0) > 0)
                                  _Amount('+${compactCurrency(c!.income)}', style.copyWith(color: p.income)),
                                if (c?.mood != null)
                                  _Amount(moodPreset(c!.mood!).label, style.copyWith(color: p.muted(0.45))),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _YearView extends StatelessWidget {
  const _YearView({required this.year, required this.byDay, required this.onTap});

  final int year;
  final Map<String, _Cell> byDay;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 4 : c.maxWidth >= 600 ? 3 : 2;
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var m = 1; m <= 12; m++) SizedBox(width: w, child: _MiniMonth(month: DateTime(year, m, 1), byDay: byDay, onTap: onTap)),
        ],
      );
    });
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({required this.month, required this.byDay, required this.onTap});

  final DateTime month;
  final Map<String, _Cell> byDay;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final days = daysBetween(startOfWeek(startOfMonth(month)), endOfWeek(endOfMonth(month)));
    var maxFlow = 0.0;
    for (final d in days) {
      final c = byDay[toDateKey(d)];
      if (c != null) maxFlow = math.max(maxFlow, c.income + c.expense);
    }
    final now = DateTime.now();
    return CardBox(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmt(month, 'MMM'), style: displayStyle(p, 18)),
                const Spacer(),
                Text('${month.year}', style: monoStyle(p, 10, color: p.muted(0.3), letterSpacing: 1.2)),
              ],
            ),
          ),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            children: [
              for (final d in _weekdays)
                Center(child: Text(d[0], style: monoStyle(p, 8, color: p.muted(0.25)))),
              for (final d in days)
                _YearCell(
                  day: d,
                  data: byDay[toDateKey(d)],
                  color: _yearColor(byDay[toDateKey(d)], maxFlow, p),
                  inMonth: sameMonth(d, month),
                  today: sameDay(d, now),
                  onTap: () => onTap(d),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YearCell extends StatelessWidget {
  const _YearCell({required this.day, required this.data, required this.color, required this.inMonth, required this.today, required this.onTap});

  final DateTime day;
  final _Cell? data;
  final Color color;
  final bool inMonth, today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final active = data != null && (data!.income + data!.expense > 0 || data!.mood != null);
    return Opacity(
      opacity: inMonth ? 1 : 0.25,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: today ? BorderSide(color: p.accent, width: 2) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          child: Center(
            child: Text(
              '${day.day}',
              style: monoStyle(p, 9, weight: active ? FontWeight.w500 : FontWeight.w400, color: active ? p.ink : p.muted(0.45)),
            ),
          ),
        ),
      ),
    );
  }
}

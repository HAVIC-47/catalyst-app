// Two dashboard sections: net worth over time (wallets plus dhar owed to you,
// minus dhar you owe, at the end of each month and today) and the streak with
// the challenges going. The web's components/dashboard/net-worth.tsx and
// habits-strip.tsx.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/habits.dart';
import '../util/i18n.dart';
import '../util/networth.dart';
import 'ui.dart';

class NetWorthCard extends StatelessWidget {
  const NetWorthCard({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    if (!app.walletsReady || app.wallets.isEmpty) return const SizedBox.shrink();
    final series = netWorthSeries(toDateKey(DateTime.now()), 12, app.wallets, app.transactions, app.debts, app.debtPayments);
    final now = series.last;
    final before = series.length > 1 ? series[series.length - 2] : null;
    final change = before == null ? 0.0 : now.total - before.total;
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardTitle(tr('Net worth'), tr('over time')),
          const SizedBox(height: 6),
          Text(formatCurrency(now.total), style: monoStyle(p, 24, weight: FontWeight.w600, color: now.total < 0 ? p.expense : p.ink)),
          if (before != null)
            Text(
              tr('{amount} since the end of {month}', {'amount': formatCurrency(change, sign: true), 'month': fmt(fromDateKey(before.date), 'MMMM')}),
              style: monoStyle(p, 11, color: change >= 0 ? p.income : p.expense),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 2, children: [
            Text(tr('Wallets {amount}', {'amount': formatCurrency(now.cash)}), style: monoStyle(p, 11, color: p.muted(0.45))),
            if (now.owedToYou > 0) Text(tr('Owed to you {amount}', {'amount': formatCurrency(now.owedToYou)}), style: monoStyle(p, 11, color: p.muted(0.45))),
            if (now.youOwe > 0) Text(tr('You owe {amount}', {'amount': formatCurrency(now.youOwe)}), style: monoStyle(p, 11, color: p.muted(0.45))),
          ]),
          const SizedBox(height: 12),
          if (series.length > 1) ...[
            SizedBox(
              height: 120,
              child: Semantics(
                label: tr('Net worth'),
                value: [for (final s in series) formatCurrency(s.total)].join(', '),
                child: CustomPaint(painter: _AreaPainter([for (final s in series) s.total], line: p.line, color: p.saving), size: Size.infinite),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text(fmt(fromDateKey(series.first.date), 'MMM'), style: monoStyle(p, 10, color: p.muted(0.4))),
              const Spacer(),
              Text(tr('Now'), style: monoStyle(p, 10, color: p.muted(0.4))),
            ]),
          ] else
            Text(tr('The chart fills in month by month.'), style: bodyStyle(p, 13, color: p.muted(0.4))),
        ]),
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter(this.values, {required this.line, required this.color});

  final List<double> values;
  final Color line;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    Offset at(int i) => Offset(size.width * i / (values.length - 1), size.height * (1 - (values[i] - lo) / (hi - lo)));
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final f in [0.25, 0.5, 0.75]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), grid);
    }
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(values.length - 1), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AreaPainter old) => old.values.join(',') != values.join(',') || old.line != line || old.color != color;
}

/// The streak and the challenges going (opens Streaks & challenges).
class HabitsStrip extends StatelessWidget {
  const HabitsStrip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final today = toDateKey(DateTime.now());
    final streak = streakOf(loggedDays(app.transactions, app.moods), today);
    final going = [
      for (final c in app.challenges)
        if (challengeProgress(c, app.transactions, app.moods, today) case final pr when pr.status == ChallengeStatus.active) (c, pr),
    ]..sort((a, b) => a.$2.daysLeft.compareTo(b.$2.daysLeft));
    final first = going.firstOrNull;
    return Semantics(
      button: true,
      label: tr('Streaks & challenges'),
      child: CardBox(
        margin: const EdgeInsets.only(bottom: 14),
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(LucideIcons.flame, size: 20, color: streak.current > 0 ? p.accent : p.muted(0.3)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(trn(streak.current, '{n}-day streak', '{n}-day streak'), style: monoStyle(p, 15, weight: FontWeight.w600)),
                    Text(
                      streak.todayDone || streak.current == 0 ? tr('Best: {n} days', {'n': streak.best}) : tr('Log something today to keep it.'),
                      style: bodyStyle(p, 11.5, color: p.muted(0.45)),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Icon(LucideIcons.trophy, size: 20, color: first != null ? p.income : p.muted(0.3)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      first != null ? challengeTitle(first.$1, tr, formatCurrency) : tr('No challenge going'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: bodyStyle(p, 13.5, color: p.muted(0.8)),
                    ),
                    Text(
                      first == null
                          ? tr('Start one — a week of no-spend days?')
                          : going.length > 1
                              ? tr('{n} days left · {more} more going', {'n': first.$2.daysLeft, 'more': going.length - 1})
                              : first.$2.daysLeft == 1
                                  ? tr('Last day')
                                  : tr('{n} days left', {'n': first.$2.daysLeft}),
                      style: bodyStyle(p, 11.5, color: p.muted(0.45)),
                    ),
                  ]),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

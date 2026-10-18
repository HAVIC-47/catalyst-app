// Streaks and challenges — port of the web's /app/challenges. The streak counts
// days with something logged by hand (an entry or a mood); a challenge runs for a
// few days — no-spend days, spending under an amount, skipping a category,
// saving an amount, logging every day — and its progress comes from the entries
// (util/habits.dart). Mood & money shows how a low day's spending compares.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/habits.dart';
import '../util/i18n.dart';
import '../util/recurring.dart' show addDaysKey;
import '../widgets/ui.dart';

const _kindText = {
  ChallengeKind.noSpend: ('No-spend days', 'Days with no spending at all'),
  ChallengeKind.spendUnder: ('Spend under', 'Keep spending under an amount'),
  ChallengeKind.skipCategory: ('Skip a category', 'Nothing spent on one category'),
  ChallengeKind.save: ('Save an amount', 'Savings entries add up to it'),
  ChallengeKind.logDaily: ('Log every day', 'An entry or a mood each day'),
};
const _lengths = [3, 7, 14, 21, 30];

class ChallengesScreen extends StatelessWidget {
  const ChallengesScreen({super.key, this.onNotifications});

  /// Opens Settings → Notifications.
  final VoidCallback? onNotifications;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final today = toDateKey(DateTime.now());
    final days = loggedDays(app.transactions, app.moods);
    final streak = streakOf(days, today);
    final pattern = moodSpendPattern(app.transactions, app.moods, today);
    final rows = [for (final c in app.challenges) (c, challengeProgress(c, app.transactions, app.moods, today))];
    final going = rows.where((r) => r.$2.status == ChallengeStatus.active || r.$2.status == ChallengeStatus.upcoming).toList();
    final finished = rows.where((r) => r.$2.status == ChallengeStatus.won || r.$2.status == ChallengeStatus.lost).toList();
    final wins = finished.where((r) => r.$2.status == ChallengeStatus.won).length;

    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(kicker: tr('Streaks & challenges'), title: tr('Keep it'), accent: tr('going.')),
          // ---- the streak
          CardBox(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: streak.current > 0 ? p.accentA(0.15) : p.inkA(0.05), borderRadius: BorderRadius.circular(14)),
                  child: Icon(LucideIcons.flame, size: 26, color: streak.current > 0 ? p.accent : p.muted(0.35)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(trn(streak.current, '{n}-day streak', '{n}-day streak'), style: displayStyle(p, 26)),
                    Text(
                      streak.current == 0
                          ? tr('Log an entry or a mood today to start one.')
                          : streak.todayDone
                              ? tr("Today's logged — see you tomorrow.")
                              : tr('Log something today to keep it.'),
                      style: bodyStyle(p, 13, color: p.muted(0.5)),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Semantics(
                label: tr('The last 28 days'),
                child: Row(children: [
                  for (var i = 27; i >= 0; i--)
                    Expanded(
                      child: Container(
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: days.contains(addDaysKey(today, -i)) ? p.accentA(0.7) : p.inkA(0.06),
                          borderRadius: BorderRadius.circular(3),
                          border: i == 0 ? Border.all(color: p.accentA(0.6)) : null,
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 2, children: [
                Text(tr('Best: {n} days', {'n': streak.best}), style: monoStyle(p, 11, color: p.muted(0.4))),
                Text(tr('{n} challenges won', {'n': wins}), style: monoStyle(p, 11, color: p.muted(0.4))),
              ]),
            ]),
          ),
          // ---- mood & money
          CardBox(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CardTitle(tr('Mood'), tr('& money')),
              const SizedBox(height: 10),
              if (pattern != null) ...[
                Row(children: [
                  Expanded(child: _Figure(label: tr('A low day'), value: formatCurrency(pattern.low), color: p.expense)),
                  const SizedBox(width: 10),
                  Expanded(child: _Figure(label: tr('A good day'), value: formatCurrency(pattern.good), color: p.income)),
                ]),
                const SizedBox(height: 10),
                Text(
                  pattern.low > pattern.good * 1.2
                      ? tr('You spend more on low days. The mood-spend alert tells you when a low day gets expensive.')
                      : tr("Your mood doesn't seem to drive your spending — nice."),
                  style: bodyStyle(p, 13, color: p.muted(0.5), height: 1.4),
                ),
              ] else
                Text(tr('Log your mood for a few more days to see how it and your spending go together.'), style: bodyStyle(p, 13, color: p.muted(0.5), height: 1.4)),
              const SizedBox(height: 8),
              InkWell(
                onTap: onNotifications,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${app.reminders.moodSpend ? tr('Mood-spend alerts are on.') : tr('Mood-spend alerts are off.')} ${tr('Notifications')} ›',
                    style: monoStyle(p, 11, color: p.muted(0.45)),
                  ),
                ),
              ),
            ]),
          ),
          // ---- challenges
          if (!app.recurringReady && !app.loading)
            EmptyCard(tr('Challenges need the database update — run db/supabase.sql in Supabase.'))
          else ...[
            PrimaryButton(expand: true, icon: LucideIcons.plus, label: tr('Start a challenge'), onPressed: () => openChallengeSheet(context)),
            const SizedBox(height: 14),
            if (!app.loading && app.challenges.isEmpty) EmptyCard(tr('No challenges yet. A week of no-spend days is a good start.')),
            for (final (c, pr) in going) _ChallengeCard(c: c, p: pr),
            if (finished.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Label(tr('Finished'))),
              for (final (c, pr) in finished) _ChallengeCard(c: c, p: pr, finished: true),
            ],
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Label(label, size: 10),
        const SizedBox(height: 4),
        Text(value, style: monoStyle(p, 16, weight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

String progressText(Challenge c, ChallengeProgress pr) => switch (c.kind) {
      ChallengeKind.noSpend => tr('{n} of {goal} no-spend days', {'n': pr.value.round(), 'goal': pr.goal.round()}),
      ChallengeKind.spendUnder => tr('{spent} of {goal} spent', {'spent': formatCurrency(pr.value), 'goal': formatCurrency(pr.goal)}),
      ChallengeKind.skipCategory => pr.value == 0 ? tr('None so far') : trn(pr.value.round(), 'Slipped once', 'Slipped {n} times'),
      ChallengeKind.save => tr('{saved} of {goal} saved', {'saved': formatCurrency(pr.value), 'goal': formatCurrency(pr.goal)}),
      ChallengeKind.logDaily => tr('{n} of {goal} days logged', {'n': pr.value.round(), 'goal': pr.goal.round()}),
    };

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.c, required this.p, this.finished = false});

  final Challenge c;
  final ChallengeProgress p;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final app = context.read<AppState>();
    final color = switch (p.status) {
      ChallengeStatus.won => pal.income,
      ChallengeStatus.lost => pal.expense,
      _ => c.kind == ChallengeKind.spendUnder && p.ratio > 0.8 ? const Color(0xFFC06A33) : const Color(0xFF3D80BC),
    };
    final when = switch (p.status) {
      ChallengeStatus.upcoming => tr('Starts {date}', {'date': fmt(fromDateKey(c.startOn), 'MMM d')}),
      ChallengeStatus.won => tr('Done 🎉'),
      ChallengeStatus.lost => tr('Missed'),
      ChallengeStatus.active => p.daysLeft == 1 ? tr('Last day') : tr('{n} days left', {'n': p.daysLeft}),
    };
    return CardBox(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(challengeTitle(c, tr, formatCurrency), style: displayStyle(pal, 18)),
              const SizedBox(height: 2),
              Text('${fmt(fromDateKey(c.startOn), 'MMM d')} – ${fmt(fromDateKey(p.endOn), 'MMM d')}', style: monoStyle(pal, 11, color: pal.muted(0.4))),
            ]),
          ),
          if (p.status == ChallengeStatus.won) Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.trophy, size: 18, color: pal.income)),
          TrashButton(
            tooltip: tr('Delete challenge'),
            onPressed: () => app.removeChallenge(c.id).catchError((Object e) {
              if (context.mounted) showError(context, e);
            }),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(value: p.ratio, minHeight: 8, color: color, backgroundColor: pal.inkA(0.06)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(progressText(c, p), style: monoStyle(pal, 12, color: pal.muted(0.7)))),
          Text(when, style: monoStyle(pal, 12, color: p.status == ChallengeStatus.won ? pal.income : (p.status == ChallengeStatus.lost ? pal.expense : pal.muted(0.45)))),
        ]),
        if (finished) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: HairlineButton(
              height: 36,
              onPressed: () => app
                  .createChallenge(Challenge(
                    id: '',
                    kind: c.kind,
                    target: c.target,
                    categoryId: c.categoryId,
                    categoryName: c.categoryName,
                    startOn: toDateKey(DateTime.now()),
                    days: c.days,
                  ))
                  .catchError((Object e) {
                if (context.mounted) showError(context, e);
                return c;
              }),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.rotateCcw, size: 14, color: pal.muted(0.6)),
                const SizedBox(width: 6),
                Text(tr('Try again'), style: bodyStyle(pal, 12.5, weight: FontWeight.w600, color: pal.muted(0.7))),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Start a challenge: what, for how long, from when.
Future<void> openChallengeSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const ChallengeSheet(),
    );

class ChallengeSheet extends StatefulWidget {
  const ChallengeSheet({super.key});

  @override
  State<ChallengeSheet> createState() => _ChallengeSheetState();
}

class _ChallengeSheetState extends State<ChallengeSheet> {
  ChallengeKind _kind = ChallengeKind.noSpend;
  int _days = 7;
  final _target = TextEditingController(text: '4');
  String _categoryId = '';
  DateTime _start = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _target.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final expense = app.categories.where((c) => c.kind == Kind.expense && c.name != breakSaving).toList();
    final n = _kind == ChallengeKind.noSpend ? int.tryParse(asciiDigits(_target.text.trim())) ?? 0 : parseAmount(_target.text) ?? 0;
    final valid = switch (_kind) {
      ChallengeKind.logDaily => true,
      ChallengeKind.skipCategory => _categoryId.isNotEmpty,
      ChallengeKind.noSpend => n >= 1 && n <= _days,
      _ => n > 0,
    };

    Future<void> start() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      final cat = expense.where((c) => c.id == _categoryId).firstOrNull;
      try {
        await app.createChallenge(Challenge(
          id: '',
          kind: _kind,
          target: switch (_kind) {
            ChallengeKind.logDaily || ChallengeKind.skipCategory => 0,
            ChallengeKind.noSpend => n.roundToDouble(),
            _ => (n * 100).roundToDouble() / 100,
          },
          categoryId: _kind == ChallengeKind.skipCategory ? cat?.id : null,
          categoryName: _kind == ChallengeKind.skipCategory ? cat?.name ?? '' : '',
          startOn: toDateKey(_start),
          days: _days,
        ));
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) showError(context, e);
        if (mounted) setState(() => _busy = false);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: p.line),
      ),
      padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: p.inkA(0.2), borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text(tr('Start a challenge'), style: displayStyle(p, 24))),
              IconButton(tooltip: tr('Close'), onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.45))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in ChallengeKind.values)
                OptionChip(
                  label: tr(_kindText[k]!.$1),
                  selected: _kind == k,
                  onTap: () => setState(() {
                    _kind = k;
                    _target.text = k == ChallengeKind.noSpend ? '${(_days / 2).round().clamp(1, _days)}' : '';
                  }),
                ),
            ]),
            const SizedBox(height: 8),
            Text(
              tr(_kindText[_kind]!.$2) +
                  (_kind != ChallengeKind.save && _kind != ChallengeKind.logDaily ? ' · ${tr("Automatic entries (rent, subscriptions) don't count.")}' : ''),
              style: bodyStyle(p, 12, color: p.muted(0.45), height: 1.4),
            ),
            const SizedBox(height: 14),
            if (_kind == ChallengeKind.noSpend)
              FieldBlock(
                label: tr('No-spend days'),
                child: TextField(controller: _target, keyboardType: TextInputType.number, style: monoStyle(p, 14)),
              ),
            if (_kind == ChallengeKind.spendUnder || _kind == ChallengeKind.save)
              FieldBlock(label: tr('Amount'), child: AmountField(controller: _target)),
            if (_kind == ChallengeKind.skipCategory)
              FieldBlock(
                label: tr('Category'),
                child: AppDropdown(
                  value: _categoryId,
                  items: ['', for (final c in expense) c.id],
                  labelOf: (id) => id.isEmpty ? tr('Pick a category') : tr(expense.firstWhere((c) => c.id == id).name),
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ),
            if (_kind != ChallengeKind.logDaily) const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FieldBlock(
                  label: tr('How long'),
                  child: AppDropdown(
                    value: '$_days',
                    items: [for (final d in _lengths) '$d'],
                    labelOf: (d) => trn(int.parse(d), '{n} day', '{n} days'),
                    onChanged: (d) => setState(() => _days = int.parse(d)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FieldBlock(label: tr('Starts'), child: DateButton(value: _start, hint: tr('Starts'), onPicked: (d) => setState(() => _start = d ?? _start))),
              ),
            ]),
            if (_kind == ChallengeKind.noSpend && n > _days) ...[
              const SizedBox(height: 8),
              Text(tr('At most {n} in {n} days.', {'n': _days}), style: bodyStyle(p, 12, color: p.expense)),
            ],
            const SizedBox(height: 18),
            PrimaryButton(expand: true, icon: LucideIcons.plus, label: tr('Start'), busy: _busy, onPressed: valid ? start : null),
          ],
        ),
      ),
    );
  }
}

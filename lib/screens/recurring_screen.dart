// Recurring income and expenses — port of the web's /app/recurring. A salary on
// the 1st, rent, subscriptions: each is added to the ledger by itself on its day
// and time — by this app or the web when open, or by the web's hourly reminders
// job when neither is — with a notification on the phone at that time.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/limits.dart';
import '../util/money.dart';
import '../util/recurring.dart';
import '../widgets/ui.dart';
import '../widgets/wallet_picker.dart';

/// How often, as the form offers it.
enum Repeat { week, twoWeeks, twice, month, threeMonths, year }

const _repeatLabels = {
  Repeat.week: 'Every week',
  Repeat.twoWeeks: 'Every 2 weeks',
  Repeat.twice: 'Twice a month',
  Repeat.month: 'Every month',
  Repeat.threeMonths: 'Every 3 months',
  Repeat.year: 'Every year',
};
const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

Repeat repeatOf(Schedule s) => switch (s.frequency) {
      Frequency.weekly => s.every >= 2 ? Repeat.twoWeeks : Repeat.week,
      Frequency.twiceMonthly => Repeat.twice,
      Frequency.monthly => s.every >= 12 ? Repeat.year : (s.every >= 3 ? Repeat.threeMonths : Repeat.month),
    };

String timeText(String hhmm) {
  final parts = hhmm.split(':');
  return fmt(DateTime(2000, 1, 1, int.tryParse(parts[0]) ?? 0, int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0), 'h:mm a');
}

/// "Every month on day 1 · 9:00 AM" and the like.
String scheduleText(Schedule s) {
  final day1 = s.day1, day2 = s.day2 ?? s.day1;
  final weekday = tr(weekdayNames[(s.day1 - 1).clamp(0, 6)]);
  final when = switch (repeatOf(s)) {
    Repeat.week => tr('Every {weekday}', {'weekday': weekday}),
    Repeat.twoWeeks => tr('Every other {weekday}', {'weekday': weekday}),
    Repeat.twice => tr('Twice a month, on days {a} and {b}', {'a': day1 < day2 ? day1 : day2, 'b': day1 < day2 ? day2 : day1}),
    Repeat.month => tr('Every month on day {day}', {'day': day1}),
    Repeat.threeMonths => tr('Every 3 months on day {day}', {'day': day1}),
    Repeat.year => tr('Every year on {date}', {'date': fmt(fromDateKey(s.startOn), 'MMM d')}),
  };
  return '$when · ${timeText(s.time)}';
}

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final live = app.recurring.where((r) => !r.paused && !r.ended).toList();
    // A rough month: whole units are enough for "about".
    double monthly(Kind kind) => live.where((r) => r.kind == kind).fold<double>(0, (s, r) {
          final per = switch (r.schedule.frequency) {
            Frequency.weekly => 52 / 12 / r.schedule.every,
            Frequency.twiceMonthly => 2.0,
            Frequency.monthly => 1 / r.schedule.every,
          };
          return s + r.amount * per;
        }).roundToDouble();
    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(
            kicker: tr('Recurring · {n} on', {'n': live.length}),
            title: tr('Money on'),
            accent: tr('repeat.'),
            below: live.isEmpty
                ? null
                : Text(
                    tr('About {income} in and {expense} out a month', {'income': formatCurrency(monthly(Kind.income)), 'expense': formatCurrency(monthly(Kind.expense))}),
                    style: monoStyle(p, 12.5, color: p.muted(0.45)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr("Salary, rent, subscriptions: set one up once and it's added to your ledger by itself on its day and time — even while the app is closed. You get a notification each time it's added."),
              style: bodyStyle(p, 12.5, color: p.muted(0.45), height: 1.45),
            ),
          ),
          if (!app.recurringReady && !app.loading)
            EmptyCard(tr('Recurring entries need the database update — run db/supabase.sql in Supabase.'))
          else ...[
            PrimaryButton(expand: true, icon: LucideIcons.plus, label: tr('Add a recurring entry'), onPressed: () => openRecurringSheet(context)),
            const SizedBox(height: 14),
            if (!app.loading && app.recurring.isEmpty) EmptyCard(tr('Nothing recurring yet. Add your salary or rent above.')),
            if (app.recurring.isNotEmpty)
              CardBox(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, r) in app.recurring.indexed)
                    Container(
                      decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
                      child: _RuleRow(rule: r),
                    ),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}

/// Name, amount and the buttons on top; the schedule gets the whole width below
/// (a narrow column would wrap it word by word on a phone). A tap edits it.
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule});

  final RecurringRule rule;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.read<AppState>();
    final r = rule;
    final income = r.kind == Kind.income;
    final cat = ruleCategory(r, app.categories);
    final wallet = app.walletsReady ? (app.wallets.where((w) => w.id == r.walletId).firstOrNull ?? defaultWallet(app.wallets)) : null;
    final next = occurrenceOnOrAfter(r.schedule, r.nextOn) ?? r.nextOn;
    final status = r.paused ? tr('paused') : (r.ended ? tr('ended') : tr('next {date}', {'date': fmt(fromDateKey(next), 'EEE, MMM d')}));
    return InkWell(
      onTap: () => openRecurringSheet(context, rule: r),
      child: Opacity(
        opacity: r.paused || r.ended ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: (income ? p.income : p.expense).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(income ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight, size: 16, color: income ? p.income : p.expense),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 14, color: p.muted(0.85)))),
              const SizedBox(width: 6),
              Text(formatCurrency(income ? r.amount : -r.amount, sign: true), style: monoStyle(p, 13.5, color: income ? p.income : p.muted(0.8))),
              if (!r.ended)
                IconButton(
                  tooltip: r.paused ? tr('Resume {name}', {'name': r.name}) : tr('Pause {name}', {'name': r.name}),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(r.paused ? LucideIcons.play : LucideIcons.pause, size: 16, color: p.muted(0.45)),
                  onPressed: () => app.pauseRecurring(r.id, !r.paused).catchError((Object e) {
                    if (context.mounted) showError(context, e);
                  }),
                ),
              TrashButton(
                tooltip: tr('Delete {name}', {'name': r.name}),
                onPressed: () async {
                  if (!await confirm(context, tr('Delete "{name}"? Entries it already added stay in the ledger.', {'name': r.name}))) return;
                  try {
                    await app.removeRecurring(r.id);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 44, right: 10),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${scheduleText(r.schedule)} · '),
                  TextSpan(text: status, style: TextStyle(color: r.paused || r.ended ? null : p.accent)),
                  if (cat != null) TextSpan(text: ' · ${tr(cat.name)}'),
                  if (wallet != null) TextSpan(text: ' · ${tr(wallet.name)}'),
                ]),
                style: monoStyle(p, 11, color: p.muted(0.4)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Add a recurring entry, or change one ([rule]).
Future<void> openRecurringSheet(BuildContext context, {RecurringRule? rule}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => RecurringSheet(rule: rule),
    );

class RecurringSheet extends StatefulWidget {
  const RecurringSheet({super.key, this.rule});

  final RecurringRule? rule;

  @override
  State<RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends State<RecurringSheet> {
  late final RecurringRule? _rule = widget.rule;
  late Kind _kind = _rule?.kind ?? Kind.income;
  late final _name = TextEditingController(text: _rule?.name ?? '');
  late final _amount = TextEditingController(text: _rule == null ? '' : groupNumber(_rule.amount));
  late Repeat _repeat = _rule == null ? Repeat.month : repeatOf(_rule.schedule);
  late int _weekday = _rule?.schedule.frequency == Frequency.weekly ? _rule!.schedule.day1 : 5;
  late int _day1 = _rule != null && _rule.schedule.frequency != Frequency.weekly ? _rule.schedule.day1 : 1;
  late int _day2 = _rule?.schedule.day2 ?? 15;
  late String _time = _rule?.schedule.time ?? '09:00';
  late DateTime _start = _rule == null ? DateTime.now() : fromDateKey(_rule.schedule.startOn);
  late DateTime? _end = _rule?.schedule.endOn == null ? null : fromDateKey(_rule!.schedule.endOn!);
  late String _categoryId = _rule?.categoryId ?? '';
  late String? _walletId = _rule?.walletId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool get _fromStart => _repeat == Repeat.threeMonths || _repeat == Repeat.year; // the first date sets the day

  Schedule get _schedule {
    final frequency = switch (_repeat) {
      Repeat.week || Repeat.twoWeeks => Frequency.weekly,
      Repeat.twice => Frequency.twiceMonthly,
      _ => Frequency.monthly,
    };
    final every = switch (_repeat) {
      Repeat.twoWeeks => 2,
      Repeat.threeMonths => 3,
      Repeat.year => 12,
      _ => 1,
    };
    return Schedule(
      frequency: frequency,
      every: every,
      day1: frequency == Frequency.weekly ? _weekday : (_fromStart ? _start.day : _day1),
      day2: frequency == Frequency.twiceMonthly ? _day2 : null,
      time: _time,
      startOn: toDateKey(_start),
      endOn: _end == null ? null : toDateKey(_end!),
    );
  }

  String? get _problem {
    if (_repeat == Repeat.twice && _day1 == _day2) return tr('Pick two different days.');
    if (_end != null && toDateKey(_end!).compareTo(toDateKey(_start)) < 0) return tr("It can't end before it starts.");
    return null;
  }

  /// When the next one will be added (and how many are due already).
  String _preview() {
    final s = _schedule;
    final now = DateTime.now();
    final today = toDateKey(now);
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final rule = _rule;
    final next = rule != null && s.sameAs(rule.schedule)
        ? rule.nextOn
        : firstNextOn(s, rule != null && today.compareTo(s.startOn) > 0 ? today : s.startOn);
    if (s.endOn != null && next.compareTo(s.endOn!) > 0) return tr('No dates left before it ends.');
    final due = dueDates(s, nextOn: next, paused: false, today: today, now: hhmm).length;
    if (due > 0) {
      return trn(due, "1 date is due already — it's added as soon as you save.", "{n} dates are due already — they're added as soon as you save.");
    }
    return tr('Next: {date} at {time}', {'date': fmt(fromDateKey(occurrenceOnOrAfter(s, next) ?? next), 'EEE, MMM d'), 'time': timeText(_time)});
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])));
    if (picked == null) return;
    setState(() => _time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final amt = parseAmount(_amount.text);
    final valid = _name.text.trim().isNotEmpty && amt != null && _problem == null;
    final cats = app.categories.where((c) => c.kind == _kind).toList();
    final autoCat = ruleCategory(
      RecurringRule(id: '', name: _name.text.isEmpty ? '—' : _name.text, kind: _kind, amount: 0, schedule: _schedule, nextOn: ''),
      app.categories,
    );
    final days = [for (var d = 1; d <= 31; d++) '$d'];
    String dayLabel(String d) => int.parse(d) >= 29 ? tr('Day {n} (or the last day)', {'n': int.parse(d)}) : tr('Day {n}', {'n': int.parse(d)});

    Future<void> save() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      final input = (
        name: _name.text.trim(),
        kind: _kind,
        amount: (amt * 100).roundToDouble() / 100,
        categoryId: _categoryId.isEmpty ? null : _categoryId,
        walletId: _walletId,
        schedule: _schedule,
      );
      try {
        if (_rule != null) {
          await app.editRecurring(_rule.id, input);
        } else {
          await app.createRecurring(input);
        }
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
              Expanded(
                child: Text(_rule == null ? tr('New recurring entry') : tr('Edit {name}', {'name': _rule.name}), maxLines: 1, overflow: TextOverflow.ellipsis, style: displayStyle(p, 24)),
              ),
              IconButton(tooltip: tr('Close'), onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.45))),
            ]),
            const SizedBox(height: 10),
            SegTabs<Kind>(
              options: const [Kind.income, Kind.expense],
              value: _kind,
              expand: true,
              label: (k) => k == Kind.income ? tr('Income') : tr('Expense'),
              onChanged: (k) => setState(() {
                _kind = k;
                _categoryId = '';
              }),
            ),
            const SizedBox(height: 14),
            FieldBlock(
              label: tr('Name'),
              child: TextField(
                controller: _name,
                inputFormatters: maxChars(Limits.name),
                decoration: InputDecoration(hintText: _kind == Kind.income ? tr('Name (e.g. Salary)') : tr('Name (e.g. Rent, Netflix)')),
              ),
            ),
            const SizedBox(height: 14),
            FieldBlock(label: tr('Amount'), child: AmountField(controller: _amount)),
            const SizedBox(height: 14),
            FieldBlock(
              label: tr('How often'),
              child: AppDropdown(
                value: _repeat.name,
                items: [for (final r in Repeat.values) r.name],
                labelOf: (n) => tr(_repeatLabels[Repeat.values.byName(n)]!),
                onChanged: (n) => setState(() => _repeat = Repeat.values.byName(n)),
              ),
            ),
            const SizedBox(height: 14),
            if (_repeat == Repeat.week || _repeat == Repeat.twoWeeks)
              FieldBlock(
                label: tr('Day of the week'),
                child: AppDropdown(
                  value: '$_weekday',
                  items: const ['1', '2', '3', '4', '5', '6', '7'],
                  labelOf: (d) => tr(weekdayNames[int.parse(d) - 1]),
                  onChanged: (d) => setState(() => _weekday = int.parse(d)),
                ),
              ),
            if (_repeat == Repeat.month || _repeat == Repeat.twice)
              Row(children: [
                Expanded(
                  child: FieldBlock(
                    label: _repeat == Repeat.twice ? tr('First day') : tr('Day of the month'),
                    child: AppDropdown(value: '$_day1', items: days, labelOf: dayLabel, onChanged: (d) => setState(() => _day1 = int.parse(d))),
                  ),
                ),
                if (_repeat == Repeat.twice) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FieldBlock(
                      label: tr('Second day'),
                      child: AppDropdown(value: '$_day2', items: days, labelOf: dayLabel, onChanged: (d) => setState(() => _day2 = int.parse(d))),
                    ),
                  ),
                ],
              ]),
            if (!_fromStart) const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FieldBlock(
                  label: _fromStart ? tr('First date') : tr('Starts'),
                  child: DateButton(value: _start, hint: tr('Starts'), onPicked: (d) => setState(() => _start = d ?? _start)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FieldBlock(
                  label: tr('Time'),
                  child: HairlineButton(
                    height: 44,
                    fill: p.inkA(0.02),
                    onPressed: _pickTime,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(timeText(_time), style: bodyStyle(p, 13.5)),
                      const SizedBox(width: 8),
                      Icon(LucideIcons.clock, size: 14, color: p.muted(0.5)),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            FieldBlock(
              label: tr('Ends (optional)'),
              child: Row(children: [
                Expanded(child: DateButton(value: _end, hint: tr('No end'), onPicked: (d) => setState(() => _end = d))),
                if (_end != null)
                  IconButton(tooltip: tr('No end'), onPressed: () => setState(() => _end = null), icon: Icon(LucideIcons.x, size: 16, color: p.muted(0.5))),
              ]),
            ),
            const SizedBox(height: 14),
            FieldBlock(
              label: tr('Category'),
              child: AppDropdown(
                value: _categoryId,
                items: ['', for (final c in cats) c.id],
                labelOf: (id) => id.isEmpty ? tr('Category: {name} (auto)', {'name': tr(autoCat?.name ?? 'Other')}) : tr(cats.firstWhere((c) => c.id == id).name),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ),
            if (app.walletsReady) ...[
              const SizedBox(height: 14),
              WalletPicker(value: _walletId ?? defaultWallet(app.wallets)?.id, onChanged: (id) => setState(() => _walletId = id), label: 'Wallet'),
            ],
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.repeat, size: 13, color: p.muted(0.45))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _problem ?? (valid ? _preview() : ''),
                  style: monoStyle(p, 11.5, color: _problem != null ? p.expense : p.muted(0.5)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            PrimaryButton(expand: true, label: _rule == null ? tr('Add') : tr('Save'), icon: _rule == null ? LucideIcons.plus : null, busy: _busy, onPressed: valid ? save : null),
          ],
        ),
      ),
    );
  }
}

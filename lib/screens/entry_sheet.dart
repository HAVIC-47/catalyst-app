// New-entry sheet — port of the web's EntryModal: Money (expense + income kept
// separately, saved together), Mood (5 moods, tags, time, note) and Saving. Also
// the editor behind the ledger's pen (TxnEditSheet): every total in the app is
// computed from AppState.transactions, so they all follow an edit straight away.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/limits.dart';
import '../util/money.dart';
import '../widgets/mood_face.dart';
import '../widgets/ui.dart';
import '../widgets/wallet_picker.dart';

enum EntryTab { money, mood, saving }

/// A new entry. [mood] (1-5) starts the mood tab on that face (the mood widget).
Future<void> openEntry(BuildContext context, {EntryTab tab = EntryTab.money, String? date, int? mood}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => EntrySheet(initialTab: tab, dateKey: date ?? toDateKey(DateTime.now()), initialMood: mood),
  );
}

/// The ledger's pen: edit (or delete) an existing transaction.
Future<void> openTxnEditor(BuildContext context, Txn txn) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => TxnEditSheet(txn: txn),
  );
}

class EntrySheet extends StatefulWidget {
  const EntrySheet({super.key, required this.initialTab, required this.dateKey, this.initialMood});

  final EntryTab initialTab;
  final String dateKey;
  final int? initialMood;

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  late EntryTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final date = fromDateKey(widget.dateKey);
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: p.line),
          ),
          child: Column(
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
                          Label(fmt(date, 'EEEE')),
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: '${fmt(date, 'MMM d')} '),
                              TextSpan(text: fmt(date, 'yyyy'), style: TextStyle(color: p.muted(0.35))),
                            ]),
                            style: displayStyle(p, 30),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Close'),
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, color: p.muted(0.4)),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line), bottom: BorderSide(color: p.line))),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final t in EntryTab.values)
                      InkWell(
                        onTap: () => setState(() => _tab = t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: _tab == t ? p.accent : Colors.transparent, width: 2)),
                          ),
                          child: Text(
                            tr('${t.name[0].toUpperCase()}${t.name.substring(1)}'),
                            style: bodyStyle(p, 14.5, weight: FontWeight.w500, color: _tab == t ? p.ink : p.muted(0.4)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: switch (_tab) {
                    EntryTab.money => _MoneyForm(dateKey: widget.dateKey),
                    EntryTab.mood => _MoodForm(dateKey: widget.dateKey, initialMood: widget.initialMood),
                    EntryTab.saving => _SavingForm(dateKey: widget.dateKey),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Time chip that opens the system time picker ("HH:mm" in/out).
class _TimeField extends StatelessWidget {
  const _TimeField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final parts = value.split(':');
    final t = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    return FieldBlock(
      label: tr('Time'),
      child: Align(
        alignment: Alignment.centerLeft,
        child: IntrinsicWidth(
          child: HairlineButton(
          height: 46,
          fill: p.inkA(0.02),
          onPressed: () async {
            final picked = await showTimePicker(context: context, initialTime: t);
            if (picked != null) {
              onChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.format(context), style: bodyStyle(p, 14, color: p.muted(0.8))),
              const SizedBox(width: 14),
              Icon(LucideIcons.clock, size: 16, color: p.muted(0.6)),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

String _friendly(Object e) {
  final msg = e.toString();
  if (msg.toLowerCase().contains('column') || msg.contains('PGRST')) {
    return tr('Database missing a column — run the migration in db/supabase.sql, then retry.');
  }
  return msg.replaceFirst('Exception: ', '');
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: p.expense.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.expense.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: bodyStyle(p, 12, color: p.expense)),
    );
  }
}

// ---------------------------------------------------------------- money

class _MoneyFields {
  final amount = TextEditingController();
  final place = TextEditingController();
  final note = TextEditingController();
  String? categoryId;
  String? walletId; // null = the one used last
  String time = nowTime();

  void dispose() {
    amount.dispose();
    place.dispose();
    note.dispose();
  }
}

class _MoneyForm extends StatefulWidget {
  const _MoneyForm({required this.dateKey});
  final String dateKey;

  @override
  State<_MoneyForm> createState() => _MoneyFormState();
}

class _MoneyFormState extends State<_MoneyForm> {
  Kind _kind = Kind.expense;
  // Expense and income keep their OWN fields; both are saved together on submit.
  final _forms = {Kind.expense: _MoneyFields(), Kind.income: _MoneyFields()};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in _forms.values) {
      f.amount.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final f in _forms.values) {
      f.dispose();
    }
    super.dispose();
  }

  NewTxn? _build(AppState app, Kind k) {
    final f = _forms[k]!;
    final v = parseAmount(f.amount.text);
    if (v == null) return null;
    final cats = app.categories.where((c) => c.kind == k).toList();
    if (cats.isEmpty) return null;
    final cat = cats.where((c) => c.id == f.categoryId).firstOrNull ?? cats.first;
    return NewTxn(
      kind: k,
      amount: (v * 100).round() / 100,
      categoryId: cat.id,
      categoryName: cat.name,
      place: f.place.text.trim(),
      note: f.note.text.trim(),
      occurredOn: widget.dateKey,
      occurredAt: combineDateTime(widget.dateKey, f.time),
      walletId: app.walletsReady ? f.walletId ?? startWallet(app.wallets) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final f = _forms[_kind]!;
    final list = app.categories.where((c) => c.kind == _kind).toList();
    final selected = list.where((c) => c.id == f.categoryId).firstOrNull ?? (list.isEmpty ? null : list.first);
    final pending = [_build(app, Kind.expense), _build(app, Kind.income)].whereType<NewTxn>().toList();

    Future<void> submit() async {
      if (pending.isEmpty || _saving) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        for (final e in pending) {
          await app.addMoney(e);
          rememberWallet(e.walletId);
        }
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        setState(() => _error = _friendly(e));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    Widget kindTab(Kind k, String label, IconData icon, Color color) {
      final on = _kind == k;
      final filled = parseAmount(_forms[k]!.amount.text) != null;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _kind = k),
          child: Container(
            height: 44,
            decoration: BoxDecoration(color: on ? p.inkA(0.06) : Colors.transparent, borderRadius: BorderRadius.circular(9)),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: on ? color : p.muted(0.45)),
                    const SizedBox(width: 8),
                    Text(label, style: bodyStyle(p, 14, weight: FontWeight.w500, color: on ? color : p.muted(0.45))),
                  ],
                ),
                if (filled)
                  Positioned(
                    right: 10,
                    child: Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line),
            color: p.inkA(0.02),
          ),
          child: Row(children: [
            kindTab(Kind.expense, tr('Expense'), LucideIcons.arrowUpRight, p.expense),
            const SizedBox(width: 6),
            kindTab(Kind.income, tr('Income'), LucideIcons.arrowDownLeft, p.income),
          ]),
        ),
        const SizedBox(height: 22),
        FieldBlock(label: tr('Amount'), child: AmountField(controller: f.amount, large: true, semanticLabel: tr('Amount'))),
        const SizedBox(height: 22),
        FieldBlock(
          label: tr('Category'),
          child: list.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.line),
                  ),
                  child: Text(tr('No {name} categories yet. Add them in Settings.', {'name': tr(_kind.name)}),
                      textAlign: TextAlign.center, style: bodyStyle(p, 12, color: p.muted(0.45))),
                )
              : GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.3,
                  children: [
                    for (final c in list)
                      _CategoryTile(cat: c, active: selected?.id == c.id, onTap: () => setState(() => f.categoryId = c.id)),
                  ],
                ),
        ),
        if (app.walletsReady && app.wallets.isNotEmpty) ...[
          const SizedBox(height: 22),
          WalletPicker(
            value: f.walletId ?? startWallet(app.wallets),
            onChanged: (id) => setState(() => f.walletId = id),
            label: _kind == Kind.expense ? tr('Paid from') : tr('Received in'),
          ),
        ],
        const SizedBox(height: 22),
        _TimeField(value: f.time, onChanged: (v) => setState(() => f.time = v)),
        const SizedBox(height: 22),
        FieldBlock(
          label: tr('Place'),
          child: TextField(
            controller: f.place,
            inputFormatters: maxChars(Limits.place),
            decoration: InputDecoration(
              hintText: tr('Star Kabab, Aarong, Pathao…'),
              prefixIcon: Icon(LucideIcons.mapPin, size: 16, color: p.muted(0.35)),
            ),
          ),
        ),
        const SizedBox(height: 22),
        FieldBlock(label: tr('Note · optional'), child: TextField(controller: f.note, inputFormatters: maxChars(Limits.note), decoration: InputDecoration(hintText: tr('What was it for?')))),
        if (_error != null) ...[const SizedBox(height: 16), _ErrorText(_error!)],
        const SizedBox(height: 22),
        PrimaryButton(
          expand: true,
          height: 50,
          busy: _saving,
          label: pending.length == 2 ? tr('Save expense + income') : pending.length == 1 ? tr('Save entry') : tr('Save'),
          onPressed: pending.isEmpty ? null : submit,
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.cat, required this.active, required this.onTap});

  final Category cat;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: tr(cat.name),
      child: Material(
        color: active ? p.inkA(0.06) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: active ? p.inkA(0.3) : p.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CategoryBadge(name: cat.name, icon: cat.icon, color: hexColor(cat.color), size: 32),
                  const SizedBox(height: 7),
                  Text(tr(cat.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 12, color: p.muted(0.7))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- mood

class _MoodForm extends StatefulWidget {
  const _MoodForm({required this.dateKey, this.initialMood});
  final String dateKey;
  final int? initialMood;

  @override
  State<_MoodForm> createState() => _MoodFormState();
}

class _MoodFormState extends State<_MoodForm> {
  late int _mood = (widget.initialMood ?? 3).clamp(1, 5);
  final _note = TextEditingController();
  final _tags = <String>[];
  String _time = nowTime();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final dayMoods = app.moodsForDate(widget.dateKey);
    final active = moodPreset(_mood);

    Future<void> submit() async {
      if (_saving) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        await app.saveMood(
          mood: _mood,
          note: _note.text.trim(),
          tags: List.of(_tags),
          loggedOn: widget.dateKey,
          loggedAt: combineDateTime(widget.dateKey, _time),
        );
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        setState(() => _error = _friendly(e));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Label(tr('How was the day?')),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final m in moodPresets) ...[
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _mood == m.value,
                  label: m.label,
                  child: GestureDetector(
                    onTap: () => setState(() => _mood = m.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: _mood == m.value ? p.mood(m.value).withValues(alpha: 0.1) : Colors.transparent,
                        border: Border.all(color: _mood == m.value ? p.mood(m.value).withValues(alpha: 0.5) : p.line),
                        boxShadow: _mood == m.value
                            ? [BoxShadow(color: p.mood(m.value).withValues(alpha: 0.35), blurRadius: 24, spreadRadius: -10)]
                            : null,
                      ),
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MoodFace(m.value, size: 28, muted: _mood != m.value, color: p.muted(0.4)),
                            const SizedBox(height: 6),
                            Text(
                              m.label,
                              style: bodyStyle(
                                p,
                                10.5,
                                weight: _mood == m.value ? FontWeight.w600 : FontWeight.w500,
                                color: _mood == m.value ? p.tintText(p.mood(m.value)) : p.muted(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (m.value != 5) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 22),
        Label(tr('What was it about? · optional')),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in moodTags)
              OptionChip(
                label: tr('$t|tag'),
                round: true,
                selected: _tags.contains(t),
                onTap: () => setState(() => _tags.contains(t) ? _tags.remove(t) : _tags.add(t)),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _TimeField(value: _time, onChanged: (v) => setState(() => _time = v)),
        const SizedBox(height: 22),
        FieldBlock(
          label: tr('Note · optional'),
          child: TextField(controller: _note, minLines: 3, maxLines: 5, inputFormatters: maxChars(Limits.note), decoration: InputDecoration(hintText: tr('What shaped the mood right now?'))),
        ),
        if (dayMoods.isNotEmpty) ...[
          const SizedBox(height: 22),
          Label(tr('Already logged today · {n}', {'n': dayMoods.length})),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in dayMoods)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.line),
                    color: p.inkA(0.02),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    MoodFace(m.mood, size: 14),
                    const SizedBox(width: 6),
                    Text(TimeOfDay.fromDateTime(parseTs(m.loggedAt)).format(context), style: bodyStyle(p, 12, color: p.muted(0.6))),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(tr('Multiple moods per day are kept — the day shows their average.'), style: bodyStyle(p, 11, color: p.muted(0.35))),
        ],
        if (_error != null) ...[const SizedBox(height: 16), _ErrorText(_error!)],
        const SizedBox(height: 22),
        _TintButton(label: tr('Save mood'), color: p.mood(active.value), busy: _saving, onPressed: submit),
      ],
    );
  }
}

/// Outlined tinted button (Save mood in the mood color, Save saving in blue).
class _TintButton extends StatelessWidget {
  const _TintButton({required this.label, required this.color, required this.onPressed, this.busy = false});

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = p.tintText(color);
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withValues(alpha: 0.4))),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: 50,
            child: Center(
              child: busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: text))
                  : Text(label, style: bodyStyle(p, 14, weight: FontWeight.w600, color: text)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- saving

class _SavingForm extends StatefulWidget {
  const _SavingForm({required this.dateKey});
  final String dateKey;

  @override
  State<_SavingForm> createState() => _SavingFormState();
}

class _SavingFormState extends State<_SavingForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _time = nowTime();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    // Vault Mode folds all income/expense into the savings pool.
    final added = app.transactions
        .where((t) => t.kind == Kind.saving || (app.vaultMode && t.kind == Kind.income))
        .fold<double>(0, (s, t) => s + t.amount);
    final broken = app.transactions
        .where((t) =>
            (t.kind == Kind.expense && t.categoryName == breakSaving) ||
            (app.vaultMode && t.kind == Kind.expense && t.categoryName != breakSaving))
        .fold<double>(0, (s, t) => s + t.amount);
    final value = parseAmount(_amount.text);

    Future<void> submit() async {
      if (value == null || _saving) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        await app.addMoney(NewTxn(
          kind: Kind.saving,
          amount: (value * 100).round() / 100,
          categoryId: null,
          categoryName: 'Saving',
          note: _note.text.trim(),
          occurredOn: widget.dateKey,
          occurredAt: combineDateTime(widget.dateKey, _time),
        ));
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        final m = e.toString().toLowerCase();
        setState(() => _error = m.contains('constraint') || m.contains('column') || m.contains('pgrst')
            ? tr("Database hasn't been migrated for savings yet — run the latest db/supabase.sql, then retry.")
            : _friendly(e));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.line),
            color: p.inkA(0.02),
          ),
          child: Column(
            children: [
              Label(tr('Total savings')),
              const SizedBox(height: 4),
              Text(formatCurrency(added - broken), style: monoStyle(p, 28, weight: FontWeight.w600, color: p.saving)),
              const SizedBox(height: 6),
              Text(tr('{amount} added · {amount2} broken', {'amount': formatCurrency(added), 'amount2': formatCurrency(broken)}),
                  style: monoStyle(p, 11, color: p.muted(0.4))),
            ],
          ),
        ),
        const SizedBox(height: 22),
        FieldBlock(label: tr('Add to savings'), child: AmountField(controller: _amount, large: true)),
        const SizedBox(height: 22),
        _TimeField(value: _time, onChanged: (v) => setState(() => _time = v)),
        const SizedBox(height: 22),
        FieldBlock(label: tr('Note · optional'), child: TextField(controller: _note, inputFormatters: maxChars(Limits.note), decoration: InputDecoration(hintText: tr('What is this saving for?')))),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line),
            color: p.inkA(0.02),
          ),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: tr('Tip: pick the ')),
              TextSpan(text: breakSaving, style: TextStyle(color: p.saving)),
              TextSpan(text: tr(' category on the Money tab to pull from this pool.')),
            ]),
            style: bodyStyle(p, 11.5, color: p.muted(0.45)),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 16), _ErrorText(_error!)],
        const SizedBox(height: 22),
        _TintButton(label: tr('Save saving'), color: p.saving, busy: _saving, onPressed: value == null ? null : submit),
      ],
    );
  }
}

// ---------------------------------------------------------------- edit a transaction

/// Edit an existing transaction (the ledger's pen): type, amount, category, date,
/// time, place and note — or delete it.
class TxnEditSheet extends StatefulWidget {
  const TxnEditSheet({super.key, required this.txn});

  final Txn txn;

  @override
  State<TxnEditSheet> createState() => _TxnEditSheetState();
}

class _TxnEditSheetState extends State<TxnEditSheet> {
  late Kind _kind = widget.txn.kind;
  late final _amount = TextEditingController(text: groupNumber(widget.txn.amount));
  late final _place = TextEditingController(text: widget.txn.place);
  late final _note = TextEditingController(text: widget.txn.note);
  String? _pick; // category id chosen here; null = the entry's own
  late String _date = widget.txn.occurredOn;
  late String? _wallet = widget.txn.walletId; // null = the default wallet (older entries)
  late final String _savedTime = _hhmm(widget.txn.occurredAt);
  late String _time = _savedTime;
  String? _busy; // 'save' or 'delete'
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_amount, _place, _note]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _hhmm(String iso) {
    final d = parseTs(iso);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static bool _same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  static String _message(Object e) => e is PostgrestException ? e.message : _friendly(e);

  Future<void> _save(NewTxn next) async {
    setState(() {
      _busy = 'save';
      _error = null;
    });
    try {
      await context.read<AppState>().editMoney(widget.txn.id, next);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_busy != null || !await confirm(context, tr('Delete this transaction?'))) return;
    if (!mounted) return;
    setState(() {
      _busy = 'delete';
      _error = null;
    });
    try {
      await context.read<AppState>().removeMoney(widget.txn.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = _message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final t = widget.txn;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    final list = app.categories.where((c) => c.kind == _kind).toList();
    final picked = _kind != Kind.saving && _pick != null ? list.where((c) => c.id == _pick).firstOrNull : null;
    // Its own category's tile: by id, or by name for older rows. One deleted since
    // shows as its saved name ("kept") until another is picked.
    final own = _kind == t.kind
        ? list.where((c) => c.id == t.categoryId).firstOrNull ?? list.where((c) => _same(c.name, t.categoryName)).firstOrNull
        : null;
    final kept = _kind == t.kind && _kind != Kind.saving && own == null;
    // Another type: the same name there, else Other, else the first.
    final near = _kind == t.kind
        ? null
        : list.where((c) => _same(c.name, t.categoryName)).firstOrNull ??
            list.where((c) => _same(c.name, 'Other')).firstOrNull ??
            list.firstOrNull;
    final activeId = picked?.id ?? own?.id ?? near?.id;
    // Left alone, the category stays exactly as saved.
    final (String?, String)? cat = picked != null
        ? (picked.id, picked.name)
        : _kind == t.kind
            ? (t.categoryId, t.categoryName)
            : _kind == Kind.saving
                ? (null, 'Saving')
                : near != null
                    ? (near.id, near.name)
                    : null;

    final value = parseAmount(_amount.text);
    final touchedWhen = _date != t.occurredOn || _time != _savedTime;
    final next = value == null || cat == null
        ? null
        : NewTxn(
            kind: _kind,
            amount: (value * 100).round() / 100,
            categoryId: cat.$1,
            categoryName: cat.$2,
            place: _kind == Kind.saving ? '' : _place.text.trim(),
            note: _note.text.trim(),
            occurredOn: _date,
            // Untouched, the original timestamp stays exactly as it was.
            occurredAt: touchedWhen ? combineDateTime(_date, _time) : t.occurredAt,
            walletId: app.walletsReady && _kind != Kind.saving ? _wallet : null,
          );
    final changed = next != null &&
        (next.kind != t.kind ||
            next.amount != t.amount ||
            next.categoryId != t.categoryId ||
            next.categoryName != t.categoryName ||
            next.place != t.place ||
            next.note != t.note ||
            next.occurredOn != t.occurredOn ||
            next.occurredAt != t.occurredAt ||
            (next.walletId != null && next.walletId != t.walletId));

    Widget kindTab(Kind k, String label, IconData icon, Color color) {
      final on = _kind == k;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            onTap: () => setState(() {
              _kind = k;
              _pick = null;
            }),
            child: Container(
              height: 44,
              decoration: BoxDecoration(color: on ? p.inkA(0.06) : Colors.transparent, borderRadius: BorderRadius.circular(9)),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: on ? color : p.muted(0.45)),
                    const SizedBox(width: 6),
                    Text(label, style: bodyStyle(p, 14, weight: FontWeight.w500, color: on ? color : p.muted(0.45))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: p.line),
          ),
          child: Column(
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
                          Label(fmt(fromDateKey(t.occurredOn), 'EEE · MMM d, yyyy')),
                          const SizedBox(height: 4),
                          Text(tr('Edit transaction'), style: displayStyle(p, 30)),
                        ],
                      ),
                    ),
                    IconButton(tooltip: tr('Close'), onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.4))),
                  ],
                ),
              ),
              Divider(color: p.line, height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.line),
                          color: p.inkA(0.02),
                        ),
                        child: Row(children: [
                          kindTab(Kind.expense, tr('Expense'), LucideIcons.arrowUpRight, p.expense),
                          const SizedBox(width: 4),
                          kindTab(Kind.income, tr('Income'), LucideIcons.arrowDownLeft, p.income),
                          const SizedBox(width: 4),
                          kindTab(Kind.saving, tr('Saving'), LucideIcons.piggyBank, p.saving),
                        ]),
                      ),
                      const SizedBox(height: 22),
                      FieldBlock(label: tr('Amount'), child: AmountField(controller: _amount, large: true, semanticLabel: tr('Amount'))),
                      const SizedBox(height: 22),
                      if (_kind == Kind.saving)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line), color: p.inkA(0.02)),
                          child: Text(tr("Savings go into your savings pool — they don't have a category."),
                              style: bodyStyle(p, 12, color: p.muted(0.5))),
                        )
                      else
                        FieldBlock(
                          label: tr('Category'),
                          child: list.isEmpty && !kept
                              ? Text(tr('No {name} categories yet — add them in Settings.', {'name': tr(_kind.name)}), style: bodyStyle(p, 12, color: p.muted(0.45)))
                              : GridView.count(
                                  crossAxisCount: 3,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 1.3,
                                  children: [
                                    if (kept)
                                      _CategoryTile(
                                        cat: Category(id: '', name: t.categoryName, kind: _kind, color: '#7A746A', sort: -1),
                                        active: picked == null,
                                        onTap: () => setState(() => _pick = null),
                                      ),
                                    for (final c in list) _CategoryTile(cat: c, active: activeId == c.id, onTap: () => setState(() => _pick = c.id)),
                                  ],
                                ),
                        ),
                      const SizedBox(height: 22),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: FieldBlock(
                            label: tr('Date'),
                            child: DateButton(
                              value: fromDateKey(_date),
                              hint: tr('Date'),
                              onPicked: (d) {
                                if (d != null) setState(() => _date = toDateKey(d));
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _TimeField(value: _time, onChanged: (v) => setState(() => _time = v))),
                      ]),
                      if (_kind != Kind.saving && app.walletsReady && app.wallets.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        WalletPicker(
                          value: _wallet ?? defaultWallet(app.wallets)?.id,
                          onChanged: (id) => setState(() => _wallet = id),
                          label: _kind == Kind.income ? tr('Received in') : tr('Paid from'),
                        ),
                      ],
                      if (_kind != Kind.saving) ...[
                        const SizedBox(height: 22),
                        FieldBlock(
                          label: tr('Place'),
                          child: TextField(
                            controller: _place,
                            inputFormatters: maxChars(Limits.place),
                            decoration: InputDecoration(
                              hintText: tr('Star Kabab, Aarong, Pathao…'),
                              prefixIcon: Icon(LucideIcons.mapPin, size: 16, color: p.muted(0.35)),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FieldBlock(
                        label: tr('Note · optional'),
                        child: TextField(controller: _note, inputFormatters: maxChars(Limits.note), decoration: InputDecoration(hintText: tr('What was it for?'))),
                      ),
                      if (_error != null) ...[const SizedBox(height: 16), _ErrorText(_error!)],
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
                child: Row(children: [
                  HairlineButton(
                    height: 46,
                    onPressed: _busy != null ? null : _delete,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _busy == 'delete'
                          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: p.expense))
                          : Icon(LucideIcons.trash2, size: 16, color: p.muted(0.7)),
                      const SizedBox(width: 8),
                      Text(tr('Delete'), style: bodyStyle(p, 14, color: p.muted(0.8))),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      expand: true,
                      busy: _busy == 'save',
                      label: tr('Save changes'),
                      onPressed: next != null && changed && _busy == null ? () => _save(next) : null,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

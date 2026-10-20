// Ledger — port of the web's /app/transactions: day-grouped transactions with
// search (note, category, place, wallet, amount, date words) and filters (type,
// period or custom range, category, wallet, amount range) plus totals for the
// filtered set.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../data/insights.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/money.dart';
import '../util/range.dart';
import '../widgets/ai_insights.dart';
import '../widgets/ui.dart';
import 'entry_sheet.dart';

enum _Period { all, day, week, month, year, custom }

const _periodLabels = {
  _Period.all: 'All time',
  _Period.day: 'Today',
  _Period.week: 'This week',
  _Period.month: 'This month',
  _Period.year: 'This year',
  _Period.custom: 'Custom',
}; // shown through tr()

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final _query = TextEditingController();
  bool _showFilters = false;
  Kind? _kind; // null = all
  _Period _period = _Period.all;
  DateTime? _from, _to;
  String _category = '';
  String _wallet = ''; // wallet id, '' = all
  final _min = TextEditingController(), _max = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_query, _min, _max]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int get _activeFilters =>
      (_kind != null ? 1 : 0) +
      (_period != _Period.all ? 1 : 0) +
      (_category.isNotEmpty ? 1 : 0) +
      (_wallet.isNotEmpty ? 1 : 0) +
      (_min.text.trim().isNotEmpty || _max.text.trim().isNotEmpty ? 1 : 0);

  void _resetFilters() => setState(() {
        _kind = null;
        _period = _Period.all;
        _from = _to = null;
        _category = '';
        _wallet = '';
        _min.clear();
        _max.clear();
      });

  void _clearAll() {
    _resetFilters();
    _query.clear();
  }

  // Searchable text: note, category, place, wallet, kind, amount (raw + grouped)
  // and the spelled-out date ("monday october 12 2026").
  String _hay(Txn t, String wallet) => [
        t.note,
        t.categoryName,
        t.place,
        wallet,
        t.kind.name,
        t.amount % 1 == 0 ? t.amount.toInt().toString() : t.amount.toString(),
        groupNumber(t.amount),
        fmt(fromDateKey(t.occurredOn), 'EEEE MMMM d yyyy'),
      ].join(' ').toLowerCase();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final words = _query.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    (String, String)? win;
    if (_period == _Period.custom) {
      if (_from != null || _to != null) {
        var a = _from, b = _to;
        if (a != null && b != null && a.isAfter(b)) (a, b) = (b, a);
        win = (a != null ? toDateKey(a) : '0000-01-01', b != null ? toDateKey(b) : '9999-12-31');
      }
    } else if (_period != _Period.all) {
      final w = rangeWindow(Range.values[_period.index - 1], 0);
      win = (w.startKey, w.endKey);
    }
    final min = double.tryParse(_min.text.trim());
    final max = double.tryParse(_max.text.trim());
    final wallets = app.walletsReady ? app.wallets : const <Wallet>[];
    final walletOf = walletNamer(wallets);

    final filtered = app.transactions.where((t) {
      if (_kind != null && t.kind != _kind) return false;
      if (_category.isNotEmpty && t.categoryName != _category) return false;
      if (_wallet.isNotEmpty && (t.kind == Kind.saving || walletOf(t)?.id != _wallet)) return false;
      if (win != null && !inRange(t.occurredOn, win.$1, win.$2)) return false;
      if (min != null && t.amount < min) return false;
      if (max != null && t.amount > max) return false;
      if (words.isNotEmpty) {
        final h = _hay(t, walletOf(t)?.name ?? '');
        if (!words.every(h.contains)) return false;
      }
      return true;
    }).toList();

    double tIn = 0, tOut = 0, tSave = 0;
    for (final t in filtered) {
      switch (t.kind) {
        case Kind.income:
          tIn += t.amount;
        case Kind.expense:
          tOut += t.amount;
        case Kind.saving:
          tSave += t.amount;
      }
    }
    final filtering = _activeFilters > 0 || words.isNotEmpty;

    final groups = <String, List<Txn>>{};
    for (final t in filtered) {
      (groups[t.occurredOn] ??= []).add(t);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final catOptions = <String>{
      for (final c in app.categories)
        if (_kind == null || c.kind == _kind) c.name,
      for (final t in app.transactions)
        if (_kind == null || t.kind == _kind) t.categoryName,
      if (_category.isNotEmpty) _category,
    }.toList()
      ..sort();
    // Each entry's category for its badge: by id, else by name (older entries).
    final byId = {for (final c in app.categories) c.id: c};
    final byName = {for (final c in app.categories) c.name: c};
    Category? catOf(Txn t) => byId[t.categoryId] ?? byName[t.categoryName];

    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(
            kicker: tr('Ledger · {n} total', {'n': app.transactions.length}),
            title: tr('Trans'),
            accent: tr('actions.'),
            joined: true,
            trailing: PrimaryButton(label: tr('+ Add'), height: 42, onPressed: () => openEntry(context)),
          ),
          const AiInsightsCard(topics: [InsightTopic.ledger]),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: tr('Search note, category, place, amount…'),
                    prefixIcon: Icon(LucideIcons.search, size: 16, color: p.muted(0.35)),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: tr('Clear search'),
                            icon: Icon(LucideIcons.x, size: 16, color: p.muted(0.4)),
                            onPressed: _query.clear,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              HairlineButton(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderColor: _showFilters || _activeFilters > 0 ? p.accentA(0.4) : null,
                fill: _showFilters || _activeFilters > 0 ? p.accentA(0.08) : null,
                onPressed: () => setState(() => _showFilters = !_showFilters),
                child: Semantics(
                  label: tr('Filters'),
                  child: Row(children: [
                    Icon(LucideIcons.slidersHorizontal, size: 16, color: _showFilters || _activeFilters > 0 ? p.accent : p.muted(0.6)),
                    if (_activeFilters > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(9)),
                        child: Text(digits('$_activeFilters'), style: monoStyle(p, 10, color: p.onAccent)),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showFilters) ...[
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldBlock(
                    label: tr('Type'),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      OptionChip(label: tr('All'), selected: _kind == null, onTap: () => setState(() => _kind = null)),
                      for (final k in Kind.values)
                        OptionChip(
                          label: tr('${k.name[0].toUpperCase()}${k.name.substring(1)}'),
                          selected: _kind == k,
                          onTap: () => setState(() => _kind = k),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  FieldBlock(
                    label: tr('Period'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final per in _Period.values)
                            OptionChip(label: tr(_periodLabels[per]!), selected: _period == per, onTap: () => setState(() => _period = per)),
                        ]),
                        if (_period == _Period.custom) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: DateButton(value: _from, hint: tr('From'), onPicked: (d) => setState(() => _from = d))),
                            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: TextStyle(color: p.muted(0.3)))),
                            Expanded(child: DateButton(value: _to, hint: tr('To'), onPicked: (d) => setState(() => _to = d))),
                          ]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FieldBlock(
                    label: tr('Category'),
                    child: AppDropdown(
                      value: _category,
                      items: ['', ...catOptions],
                      labelOf: (v) => v.isEmpty ? tr('All categories') : tr(v),
                      onChanged: (v) => setState(() => _category = v),
                    ),
                  ),
                  if (wallets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    FieldBlock(
                      label: tr('Wallet'),
                      child: AppDropdown(
                        value: _wallet,
                        items: ['', for (final w in wallets) w.id],
                        labelOf: (id) => id.isEmpty ? tr('All wallets') : tr(wallets.firstWhere((w) => w.id == id).name),
                        onChanged: (v) => setState(() => _wallet = v),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FieldBlock(
                    label: tr('Amount ({x0})', {'x0': currencySymbol()}),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _min,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(hintText: tr('Min')),
                        ),
                      ),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: TextStyle(color: p.muted(0.3)))),
                      Expanded(
                        child: TextField(
                          controller: _max,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(hintText: tr('Max')),
                        ),
                      ),
                    ]),
                  ),
                  if (_activeFilters > 0) ...[
                    const SizedBox(height: 12),
                    Divider(color: p.line, height: 1),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _resetFilters,
                        child: Text(tr('RESET FILTERS'), style: monoStyle(p, 11, color: p.accentA(0.85), letterSpacing: 1.4)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (filtering)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(spacing: 12, runSpacing: 4, children: [
                      Text(tr('{n} of {n2}', {'n': filtered.length, 'n2': app.transactions.length}), style: monoStyle(p, 12, color: p.muted(0.55))),
                      if (tIn > 0) Text(tr('In {amount}', {'amount': formatCurrency(tIn)}), style: monoStyle(p, 12, color: p.income)),
                      if (tOut > 0) Text(tr('Out {amount}', {'amount': formatCurrency(tOut)}), style: monoStyle(p, 12, color: p.expense)),
                      if (tSave > 0) Text(tr('Saved {amount}', {'amount': formatCurrency(tSave)}), style: monoStyle(p, 12, color: p.saving)),
                      Text(tr('Net {amount}', {'amount': formatCurrency(tIn - tOut, sign: true)}), style: monoStyle(p, 12, color: tIn - tOut >= 0 ? p.income : p.expense)),
                    ]),
                  ),
                  TextButton(
                    onPressed: _clearAll,
                    child: Text(tr('CLEAR'), style: monoStyle(p, 11, color: p.accentA(0.85), letterSpacing: 1.4)),
                  ),
                ],
              ),
            ),
          if (!app.loading && app.transactions.isEmpty)
            EmptyCard(tr('No transactions yet. Tap + Add or a calendar day.'))
          else if (!app.loading && filtered.isEmpty)
            EmptyCard(tr('Nothing matches.'), action: TextButton(onPressed: _clearAll, child: Text(tr('Clear search & filters'), style: TextStyle(color: p.accent)))),
          for (final day in days) _DayGroup(day: day, items: groups[day]!, catOf: catOf, walletOf: walletOf),
        ],
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.day, required this.items, required this.catOf, required this.walletOf});

  final String day;
  final List<Txn> items;
  final Category? Function(Txn) catOf;
  final Wallet? Function(Txn) walletOf;

  Widget _badge(Txn t) {
    final cat = catOf(t);
    return CategoryBadge(name: t.categoryName, icon: cat?.icon, color: cat != null ? hexColor(cat.color) : const Color(0xFF7A746A));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.read<AppState>();
    double sum(Kind k) => items.where((t) => t.kind == k).fold<double>(0, (s, t) => s + t.amount);
    final dIn = sum(Kind.income), dOut = sum(Kind.expense), dSave = sum(Kind.saving);
    final dNet = dIn - dOut;
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(fmt(fromDateKey(day), 'EEE · MMM d, yyyy').toUpperCase(), style: monoStyle(p, 11.5, color: p.muted(0.45), letterSpacing: 1.4)),
                Wrap(spacing: 10, children: [
                  if (dIn > 0) Text(tr('In {amount}', {'amount': formatCurrency(dIn)}), style: monoStyle(p, 11.5, color: p.income)),
                  if (dOut > 0) Text(tr('Out {amount}', {'amount': formatCurrency(dOut)}), style: monoStyle(p, 11.5, color: p.expense)),
                  if (dSave > 0) Text(tr('Saved {amount}', {'amount': formatCurrency(dSave)}), style: monoStyle(p, 11.5, color: p.saving)),
                  Text(tr('Net {amount}', {'amount': formatCurrency(dNet, sign: true)}), style: monoStyle(p, 11.5, color: dNet >= 0 ? p.income : p.expense)),
                ]),
              ],
            ),
          ),
          for (final (i, t) in items.indexed)
            Container(
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
              child: Row(
                children: [
                  _badge(t),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.note.isEmpty ? tr(t.categoryName) : t.note,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 14, color: p.muted(0.85))),
                        Row(children: [
                          // Category and wallet give way (ellipsis) before the row overflows.
                          Flexible(
                            child: Text(
                              t.kind != Kind.saving && walletOf(t) != null
                                  ? '${tr(t.categoryName)} · ${tr(walletOf(t)!.name)}'
                                  : tr(t.categoryName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: bodyStyle(p, 11.5, color: p.muted(0.4)),
                            ),
                          ),
                          if (t.place.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Icon(LucideIcons.mapPin, size: 11, color: p.muted(0.4)),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(t.place, maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 11.5, color: p.muted(0.4))),
                            ),
                          ],
                        ]),
                      ],
                    ),
                  ),
                  Icon(t.kind == Kind.income ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
                      size: 14, color: t.kind == Kind.income ? p.income : p.expense),
                  const SizedBox(width: 6),
                  Text(
                    formatCurrency(t.kind == Kind.income ? t.amount : -t.amount, sign: true),
                    style: monoStyle(p, 14, color: t.kind == Kind.income ? p.income : p.muted(0.8)),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: tr('Edit'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => openTxnEditor(context, t),
                    icon: Icon(LucideIcons.pencil, size: 16, color: p.muted(0.45)),
                  ),
                  TrashButton(onPressed: () async {
                    if (!await confirm(context, tr('Delete this transaction?'))) return;
                    try {
                      await app.removeMoney(t.id);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

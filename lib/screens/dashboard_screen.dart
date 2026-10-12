// Dashboard — port of the web's /app/dashboard: this-month KPI tiles, the
// mood × money trend (owns the single period selector) and six charts. Sections
// hidden in Settings (shared with the web via user metadata) are not rendered.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/range.dart';
import '../widgets/charts.dart';
import '../widgets/ui.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onCustomize});

  final VoidCallback onCustomize;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Range _range = Range.month;
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final hidden = app.dashboardHidden;
    bool show(String id) => hidden != null && !hidden.contains(id);

    final now = DateTime.now();
    final monthTx = app.transactions.where((t) => sameMonth(fromDateKey(t.occurredOn), now));
    final spent = monthTx.where((t) => t.kind == Kind.expense).fold<double>(0, (s, t) => s + t.amount);
    final earned = monthTx.where((t) => t.kind == Kind.income).fold<double>(0, (s, t) => s + t.amount);
    final saved = earned - spent;
    final savedRate = earned > 0 ? (saved / earned * 100).round() : 0;
    final monthMoods = app.moods.where((m) => sameMonth(fromDateKey(m.loggedOn), now)).toList();
    final avgMood = monthMoods.isEmpty
        ? 0.0
        : (monthMoods.fold<int>(0, (s, m) => s + m.mood) / monthMoods.length * 10).round() / 10;

    final window = rangeWindow(_range, _offset);
    final charts = <(String, String, String, Widget)>[
      ('spent', 'Spent', 'by category', CategoryDonut(transactions: app.transactions, categories: app.categories, kind: Kind.expense, window: window)),
      ('earned', 'Earned', 'by category', CategoryDonut(transactions: app.transactions, categories: app.categories, kind: Kind.income, window: window)),
      ('mood', 'Mood', 'distribution', MoodDonut(moods: app.moods, window: window)),
      ('savings', 'Savings', 'added vs broken', SavingsDonut(transactions: app.transactions, window: window, vaultMode: app.vaultMode)),
      ('moodTags', 'Mood was about', 'frequency', MoodTagBars(moods: app.moods, window: window)),
      ('categories', 'Category', 'frequency', CategoryBars(transactions: app.transactions, categories: app.categories, window: window)),
    ].where((c) => show(c.$1)).toList();
    final nothing = hidden != null && !show('kpis') && !show('trend') && charts.isEmpty;

    // Phones: the plot takes whatever height is left so heading, tiles and the
    // whole trend card share the first screen (same budget as the web).
    final screenH = MediaQuery.of(context).size.height - MediaQuery.of(context).padding.vertical;
    final plotH = (screenH - 470).clamp(150.0, 288.0);

    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Row(
            children: [
              const Expanded(child: Label('Dashboard · this month')),
              InkWell(
                onTap: widget.onCustomize,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(children: [
                    Icon(LucideIcons.slidersHorizontal, size: 12, color: p.muted(0.4)),
                    const SizedBox(width: 6),
                    Text('CUSTOMIZE', style: monoStyle(p, 10, color: p.muted(0.4), letterSpacing: 1.4)),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [const TextSpan(text: 'The month '), TextSpan(text: 'so far.', style: accentItalic(p, 30))]),
            style: displayStyle(p, 30),
          ),
          const SizedBox(height: 14),
          if (hidden != null) ...[
            if (show('kpis')) ...[
              _KpiGrid(tiles: [
                _Kpi('Spent', formatCurrency(spent), LucideIcons.arrowUpRight, const Color(0xFFCB453B)),
                _Kpi('Earned', formatCurrency(earned), LucideIcons.arrowDownLeft, const Color(0xFF2E8159)),
                _Kpi('Saved', formatCurrency(saved), LucideIcons.wallet, saved >= 0 ? const Color(0xFF3D80BC) : const Color(0xFFCB453B),
                    sub: '$savedRate% rate'),
                _Kpi('Avg mood', avgMood > 0 ? '$avgMood / 5' : '—', LucideIcons.smile, const Color(0xFF7A4E86)),
              ]),
              const SizedBox(height: 14),
            ],
            if (show('trend'))
              CardBox(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                child: TrendCard(
                  transactions: app.transactions,
                  moods: app.moods,
                  range: _range,
                  offset: _offset,
                  plotHeight: plotH,
                  onRange: (r) => setState(() => _range = r),
                  onOffset: (o) => setState(() => _offset = o),
                ),
              )
            else if (charts.isNotEmpty)
              // Trend hidden: the period selector still needs a home.
              CardBox(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Label('Period · ${window.label}'),
                    const SizedBox(height: 8),
                    RangeControls(
                      range: _range,
                      offset: _offset,
                      onRange: (r) => setState(() => _range = r),
                      onOffset: (o) => setState(() => _offset = o),
                    ),
                  ],
                ),
              ),
            for (final c in charts)
              CardBox(
                margin: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [CardTitle(c.$2, c.$3), const SizedBox(height: 8), c.$4],
                ),
              ),
            if (nothing)
              EmptyCard(
                'Every dashboard section is hidden — your data is all still there.',
                action: TextButton(onPressed: widget.onCustomize, child: Text('Choose what to show', style: TextStyle(color: p.accent))),
              ),
          ],
          if (app.loading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(child: Text('Loading…', style: monoStyle(p, 12, color: p.muted(0.3)))),
            ),
        ],
      ),
    );
  }
}

class _Kpi {
  const _Kpi(this.label, this.value, this.icon, this.tint, {this.sub});
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final String? sub;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.tiles});
  final List<_Kpi> tiles;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget tile(_Kpi k) => Expanded(
          child: Container(
            color: p.card,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Label(k.label, size: 10)), Icon(k.icon, size: 14, color: k.tint)]),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: k.value, style: monoStyle(p, 16, weight: FontWeight.w600)),
                    if (k.sub != null) TextSpan(text: '  ${k.sub}', style: monoStyle(p, 10, color: p.muted(0.35))),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line), color: p.line),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Row(children: [tile(tiles[0]), const SizedBox(width: 1), tile(tiles[1])]),
          const SizedBox(height: 1),
          Row(children: [tile(tiles[2]), const SizedBox(width: 1), tile(tiles[3])]),
        ],
      ),
    );
  }
}

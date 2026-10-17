// Budgets — port of the web's /app/budgets: monthly limit per expense category,
// filled by this month's spending (red when over).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/ui.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  String _catId = '';
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final now = DateTime.now();

    final spentByCat = <String, double>{};
    for (final t in app.transactions) {
      if (t.kind != Kind.expense || !sameMonth(fromDateKey(t.occurredOn), now)) continue;
      spentByCat[t.categoryName] = (spentByCat[t.categoryName] ?? 0) + t.amount;
    }
    final expenseCats = app.categories.where((c) => c.kind == Kind.expense).toList();
    final used = {for (final b in app.budgets) b.categoryId};
    final available = expenseCats.where((c) => !used.contains(c.id)).toList();
    final amt = parseAmount(_amount.text);
    final totalBudget = app.budgets.fold<double>(0, (s, b) => s + b.amount);
    final totalSpent = app.budgets.fold<double>(0, (s, b) => s + (spentByCat[b.categoryName] ?? 0));

    Future<void> add() async {
      final cat = available.where((c) => c.id == _catId).firstOrNull ?? available.firstOrNull;
      if (cat == null || amt == null || _busy) return;
      setState(() => _busy = true);
      try {
        await app.createBudget(cat, amt);
        _amount.clear();
        setState(() => _catId = '');
      } catch (e) {
        if (context.mounted) showError(context, e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(
            kicker: tr('Budgets · this month'),
            title: tr('Spend'),
            accent: tr('limits.'),
            below: app.budgets.isEmpty
                ? null
                : Text(tr('{amount} of {amount2} used', {'amount': formatCurrency(totalSpent), 'amount2': formatCurrency(totalBudget)}), style: monoStyle(p, 13, color: p.muted(0.45))),
          ),
          // Category, limit and button each get their own row on phones.
          CardBox(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldBlock(
                  label: tr('Category'),
                  child: available.isEmpty
                      ? Text(tr('All categories budgeted'), style: bodyStyle(p, 14, color: p.muted(0.5)))
                      : AppDropdown(
                          value: available.any((c) => c.id == _catId) ? _catId : available.first.id,
                          items: [for (final c in available) c.id],
                          labelOf: (id) => available.firstWhere((c) => c.id == id).name,
                          onChanged: (v) => setState(() => _catId = v),
                        ),
                ),
                const SizedBox(height: 12),
                FieldBlock(label: tr('Monthly limit'), child: AmountField(controller: _amount, onSubmitted: (_) => add())),
                const SizedBox(height: 14),
                PrimaryButton(
                  expand: true,
                  icon: LucideIcons.plus,
                  label: tr('Set budget'),
                  busy: _busy,
                  onPressed: available.isEmpty || amt == null ? null : add,
                ),
              ],
            ),
          ),
          if (!app.loading && app.budgets.isEmpty) EmptyCard(tr('No budgets yet. Pick a category and set a monthly limit.')),
          for (final b in app.budgets) _BudgetCard(budget: b, spent: spentByCat[b.categoryName] ?? 0),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatefulWidget {
  const _BudgetCard({required this.budget, required this.spent});
  final Budget budget;
  final double spent;

  @override
  State<_BudgetCard> createState() => _BudgetCardState();
}

class _BudgetCardState extends State<_BudgetCard> {
  late final _limit = TextEditingController(text: groupNumber(widget.budget.amount).replaceAll(',', ''));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void dispose() {
    _limit.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseAmount(_limit.text);
    if (v == null || v == widget.budget.amount) return;
    try {
      await context.read<AppState>().editBudget(widget.budget.id, v);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.read<AppState>();
    final b = widget.budget;
    final cat = app.categories.where((c) => c.id == b.categoryId).firstOrNull;
    final catColor = cat != null ? hexColor(cat.color) : const Color(0xFF7A746A);
    final pct = b.amount > 0 ? (widget.spent / b.amount).clamp(0.0, 1.0) : 0.0;
    final over = widget.spent > b.amount;
    final barColor = over ? const Color(0xFFCB453B) : (cat != null ? catColor : const Color(0xFF3D80BC));
    return CardBox(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            CategoryBadge(name: tr(b.categoryName), color: catColor, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(tr(b.categoryName), style: bodyStyle(p, 14, weight: FontWeight.w500, color: p.muted(0.85)))),
            TrashButton(
              tooltip: tr('Delete budget'),
              onPressed: () async {
                if (!await confirm(context, tr('Delete this budget?'))) return;
                try {
                  await app.removeBudget(b.id);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(value: pct, minHeight: 8, color: barColor, backgroundColor: p.inkA(0.06)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text(tr('{amount} spent', {'amount': formatCurrency(widget.spent)}), style: monoStyle(p, 12, color: over ? p.expense : p.muted(0.55))),
            const Spacer(),
            Text(tr('of '), style: monoStyle(p, 12, color: p.muted(0.4))),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _limit,
                focusNode: _focus,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _save(),
                style: monoStyle(p, 12, color: p.muted(0.7)),
                decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), prefixText: currencySymbol()),
              ),
            ),
          ]),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('Over by {amount}', {'amount': formatCurrency(widget.spent - b.amount)}), style: monoStyle(p, 11, color: p.expense)),
            ),
        ],
      ),
    );
  }
}

// Goals — port of the web's /app/goals: savings targets with progress and quick
// additions (negative amounts withdraw).
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
import '../util/limits.dart';
import '../widgets/ai_insights.dart';
import '../widgets/ui.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _title = TextEditingController();
  final _target = TextEditingController();
  DateTime? _due;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _target.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final target = parseAmount(_target.text);
    final valid = _title.text.trim().isNotEmpty && target != null;

    Future<void> add() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      try {
        await app.createGoal(_title.text.trim(), target, _due == null ? null : toDateKey(_due!));
        _title.clear();
        _target.clear();
        setState(() => _due = null);
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
          PageHeader(kicker: tr('Goals · {n}', {'n': app.goals.length}), title: tr('Saving'), accent: tr('targets.')),
          const AiInsightsCard(topics: [InsightTopic.goals, InsightTopic.savings]),
          CardBox(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: _title, inputFormatters: maxChars(Limits.title), decoration: InputDecoration(hintText: tr('Goal (e.g. New laptop)'))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: AmountField(controller: _target, hint: tr('Target'))),
                  const SizedBox(width: 10),
                  Expanded(child: DateButton(value: _due, hint: tr('Due date'), onPicked: (d) => setState(() => _due = d))),
                ]),
                const SizedBox(height: 12),
                PrimaryButton(expand: true, icon: LucideIcons.plus, label: tr('Add'), busy: _busy, onPressed: valid ? add : null),
              ],
            ),
          ),
          if (!app.loading && app.goals.isEmpty) EmptyCard(tr('No goals yet. What are you saving toward?')),
          for (final g in app.goals) _GoalCard(goal: g),
        ],
      ),
    );
  }
}

class _GoalCard extends StatefulWidget {
  const _GoalCard({required this.goal});
  final Goal goal;

  @override
  State<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<_GoalCard> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.read<AppState>();
    final g = widget.goal;
    final pct = g.targetAmount > 0 ? (g.savedAmount / g.targetAmount).clamp(0.0, 1.0) : 0.0;
    final done = g.savedAmount >= g.targetAmount;

    Future<void> addSaving() async {
      final n = double.tryParse(_add.text.replaceAll(',', '').trim());
      if (n == null || n == 0) return;
      try {
        await app.addToGoal(g, n);
        _add.clear();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return CardBox(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(g.title, style: displayStyle(p, 21))),
            TrashButton(
              tooltip: tr('Delete goal'),
              onPressed: () async {
                if (!await confirm(context, tr('Delete this goal?'))) return;
                try {
                  await app.removeGoal(g.id);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
          ]),
          if (g.dueOn != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(tr('due {date}', {'date': fmt(fromDateKey(g.dueOn!), 'MMM d, yyyy')}), style: monoStyle(p, 11, color: p.muted(0.35))),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              color: done ? const Color(0xFF2E8159) : const Color(0xFF3D80BC),
              backgroundColor: p.inkA(0.06),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text(formatCurrency(g.savedAmount), style: monoStyle(p, 14, color: p.muted(0.7))),
            const Spacer(),
            Text('/ ${formatCurrency(g.targetAmount)}', style: monoStyle(p, 14, color: p.muted(0.4))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 130,
              child: TextField(
                controller: _add,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onSubmitted: (_) => addSaving(),
                style: monoStyle(p, 13),
                decoration: InputDecoration(hintText: tr('+ add'), prefixText: '${currencySymbol()} '),
              ),
            ),
            const SizedBox(width: 8),
            HairlineIconButton(icon: LucideIcons.coins, tooltip: tr('Add to goal'), color: p.income, onPressed: addSaving),
            const SizedBox(width: 10),
            if (done) Text(tr('Reached'), style: monoStyle(p, 11, color: p.income)),
          ]),
        ],
      ),
    );
  }
}

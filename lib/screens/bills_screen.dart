// Bills — port of the web's /app/bills: due-date countdowns, recurrence, one-tap paid.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/limits.dart';
import '../widgets/ui.dart';

const _recurrences = ['monthly', 'weekly', 'yearly', 'once'];

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  DateTime _due = DateTime.now();
  String _recurrence = 'monthly';
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

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final amt = parseAmount(_amount.text);
    final valid = _name.text.trim().isNotEmpty && amt != null;
    final unpaid = app.bills.where((b) => !b.isPaid).toList();
    final outstanding = unpaid.fold<double>(0, (s, b) => s + b.amount);
    final today = DateTime.now();

    Future<void> add() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      try {
        await app.createBill(_name.text.trim(), amt, toDateKey(_due), _recurrence);
        _name.clear();
        _amount.clear();
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
            kicker: 'Bills · ${unpaid.length} unpaid',
            title: 'Upcoming',
            accent: 'dues.',
            below: outstanding > 0 ? Text('${formatCurrency(outstanding)} outstanding', style: monoStyle(p, 13, color: p.muted(0.45))) : null,
          ),
          CardBox(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: _name, inputFormatters: maxChars(Limits.name), decoration: const InputDecoration(hintText: 'Bill (e.g. Internet)')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: AmountField(controller: _amount, hint: 'Amount')),
                  const SizedBox(width: 10),
                  Expanded(child: DateButton(value: _due, hint: 'Due date', onPicked: (d) => setState(() => _due = d ?? _due))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: AppDropdown(
                      value: _recurrence,
                      items: _recurrences,
                      labelOf: (r) => '${r[0].toUpperCase()}${r.substring(1)}',
                      onChanged: (v) => setState(() => _recurrence = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: PrimaryButton(expand: true, icon: LucideIcons.plus, label: 'Add', busy: _busy, onPressed: valid ? add : null)),
                ]),
              ],
            ),
          ),
          if (!app.loading && app.bills.isEmpty) const EmptyCard('No bills tracked yet.'),
          if (app.bills.isNotEmpty)
            CardBox(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, b) in app.bills.indexed)
                    Builder(builder: (context) {
                      final days = DateTime(fromDateKey(b.dueOn).year, fromDateKey(b.dueOn).month, fromDateKey(b.dueOn).day)
                          .difference(DateTime(today.year, today.month, today.day))
                          .inDays;
                      final soon = !b.isPaid && days <= 3;
                      final when = b.isPaid
                          ? 'paid'
                          : days < 0
                              ? '${-days}d overdue'
                              : days == 0
                                  ? 'due today'
                                  : 'in ${days}d';
                      return Container(
                        decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
                        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                        child: Row(children: [
                          Semantics(
                            button: true,
                            label: b.isPaid ? 'Mark unpaid' : 'Mark paid',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () async {
                                try {
                                  await app.toggleBillPaid(b);
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: b.isPaid ? p.income : p.inkA(0.25)),
                                  color: b.isPaid ? p.income.withValues(alpha: 0.2) : Colors.transparent,
                                ),
                                child: b.isPaid ? Icon(LucideIcons.check, size: 16, color: p.income) : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  style: bodyStyle(p, 14, color: b.isPaid ? p.muted(0.4) : p.muted(0.85)).copyWith(
                                    decoration: b.isPaid ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                Text.rich(
                                  TextSpan(children: [
                                    TextSpan(text: '${b.recurrence[0].toUpperCase()}${b.recurrence.substring(1)} · '),
                                    TextSpan(text: when, style: TextStyle(color: soon ? p.expense : null)),
                                    TextSpan(text: ' · ${fmt(fromDateKey(b.dueOn), 'MMM d')}'),
                                  ]),
                                  style: monoStyle(p, 11, color: p.muted(0.4)),
                                ),
                              ],
                            ),
                          ),
                          if (soon) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(LucideIcons.bell, size: 14, color: p.expense)),
                          Text(formatCurrency(b.amount), style: monoStyle(p, 14, color: p.muted(0.8))),
                          TrashButton(
                            tooltip: 'Delete bill',
                            onPressed: () async {
                              if (!await confirm(context, 'Delete this bill?')) return;
                              try {
                                await app.removeBill(b.id);
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                          ),
                        ]),
                      );
                    }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

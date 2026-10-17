// Bills — port of the web's /app/bills: due-date countdowns and recurrence.
// Ticking a bill logs it as an expense (its category, from its wallet) and moves a
// repeating bill to its next due date, with Undo.
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
import '../util/money.dart';
import '../widgets/ai_insights.dart';
import '../widgets/ui.dart';
import '../widgets/wallet_picker.dart';

const _recurrences = ['monthly', 'weekly', 'yearly', 'once'];
String _cap(String s) => tr('${s[0].toUpperCase()}${s.substring(1)}');

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
  String _categoryId = ''; // '' = matched by the bill's name
  String? _walletId;
  bool _busy = false;
  String? _paying;

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

  Future<void> _pay(AppState app, Bill b) async {
    if (_paying != null) return;
    setState(() => _paying = b.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final payment = await app.payBill(b.id);
      final next = nextDue(b.dueOn, b.recurrence);
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Paid {name} — {amount} added to the ledger.', {'name': b.name, 'amount': formatCurrency(b.amount)}) +
            (next != null ? ' ${tr('Next due {date}.', {'date': fmt(fromDateKey(next), 'MMM d')})}' : '')),
        action: SnackBarAction(
          label: tr('UNDO'),
          onPressed: () => app.undoBillPayment(payment).catchError((Object e) {
            messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
          }),
        ),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _paying = null);
    }
  }

  Future<void> _unpay(AppState app, Bill b) async {
    final ask = b.lastPaidTxn != null
        ? tr('Mark "{name}" unpaid and take its {amount} expense back off the ledger?', {'name': b.name, 'amount': formatCurrency(b.amount)})
        : tr('Mark "{name}" unpaid?', {'name': b.name});
    if (!await confirm(context, ask, action: tr('Mark unpaid'))) return;
    try {
      await app.unpayBill(b.id);
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
    final expenseCats = app.categories.where((c) => c.kind == Kind.expense).toList();
    final autoCat = billCategory(Bill(id: '', name: _name.text.isEmpty ? '—' : _name.text, amount: 0, dueOn: '', recurrence: '', isPaid: false), app.categories);

    Future<void> add() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      try {
        await app.createBill(
          _name.text.trim(),
          amt,
          toDateKey(_due),
          _recurrence,
          categoryId: _categoryId.isEmpty ? null : _categoryId,
          walletId: _walletId,
        );
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
            kicker: tr('Bills · {n} unpaid', {'n': unpaid.length}),
            title: tr('Upcoming'),
            accent: tr('dues.'),
            below: outstanding > 0 ? Text(tr('{amount} outstanding', {'amount': formatCurrency(outstanding)}), style: monoStyle(p, 13, color: p.muted(0.45))) : null,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr("Tick a bill when you pay it: it's added to your ledger as an expense, and a repeating bill moves on to its next due date."),
              style: bodyStyle(p, 12.5, color: p.muted(0.45), height: 1.45),
            ),
          ),
          const AiInsightsCard(topics: [InsightTopic.bills]),
          CardBox(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: _name, inputFormatters: maxChars(Limits.name), decoration: InputDecoration(hintText: tr('Bill (e.g. Internet)'))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: AmountField(controller: _amount, hint: tr('Amount'))),
                  const SizedBox(width: 10),
                  Expanded(child: DateButton(value: _due, hint: tr('Due date'), onPicked: (d) => setState(() => _due = d ?? _due))),
                ]),
                const SizedBox(height: 10),
                AppDropdown(
                  value: _recurrence,
                  items: _recurrences,
                  labelOf: _cap,
                  onChanged: (v) => setState(() => _recurrence = v),
                ),
                // Category and wallet need the database's wallets update.
                if (app.walletsReady) ...[
                  const SizedBox(height: 10),
                  AppDropdown(
                    value: _categoryId,
                    items: ['', for (final c in expenseCats) c.id],
                    labelOf: (id) => id.isEmpty
                        ? tr('Category: {name} (auto)', {'name': tr(autoCat?.name ?? 'Other')})
                        : tr(expenseCats.firstWhere((c) => c.id == id).name),
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 12),
                  WalletPicker(
                    value: _walletId ?? defaultWallet(app.wallets)?.id,
                    onChanged: (id) => setState(() => _walletId = id),
                    label: tr('Paid from'),
                  ),
                ],
                const SizedBox(height: 12),
                PrimaryButton(expand: true, icon: LucideIcons.plus, label: tr('Add'), busy: _busy, onPressed: valid ? add : null),
              ],
            ),
          ),
          if (!app.loading && app.bills.isEmpty) EmptyCard(tr('No bills tracked yet.')),
          if (app.bills.isNotEmpty)
            CardBox(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, b) in app.bills.indexed)
                    Builder(builder: (context) {
                      final due = fromDateKey(b.dueOn);
                      final days = due.difference(DateTime(today.year, today.month, today.day)).inDays;
                      final soon = !b.isPaid && days <= 3;
                      final when = b.isPaid
                          ? 'paid'
                          : days < 0
                              ? tr('{n}d overdue', {'n': -days})
                              : days == 0
                                  ? tr('due today')
                                  : tr('in {n}d', {'n': days});
                      final cat = app.walletsReady ? billCategory(b, app.categories) : null;
                      final wallet = app.walletsReady ? (app.wallets.where((w) => w.id == b.walletId).firstOrNull ?? defaultWallet(app.wallets)) : null;
                      return Container(
                        decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.line))),
                        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                        child: Row(children: [
                          Semantics(
                            button: true,
                            label: b.isPaid ? tr('Mark {name} unpaid', {'name': b.name}) : tr('Pay {name}', {'name': b.name}),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _paying != null ? null : () => b.isPaid ? _unpay(app, b) : _pay(app, b),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: b.isPaid ? p.income : p.inkA(0.25)),
                                  color: b.isPaid ? p.income.withValues(alpha: 0.2) : Colors.transparent,
                                ),
                                child: _paying == b.id
                                    ? Padding(padding: const EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 1.6, color: p.accent))
                                    : b.isPaid
                                        ? Icon(LucideIcons.check, size: 16, color: p.income)
                                        : null,
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
                                    TextSpan(text: '${_cap(b.recurrence)} · '),
                                    TextSpan(text: when, style: TextStyle(color: soon ? p.expense : null)),
                                    TextSpan(text: ' · ${fmt(due, 'MMM d')}'),
                                    if (cat != null) TextSpan(text: ' · ${tr(cat.name)}'),
                                    if (wallet != null) TextSpan(text: ' · ${tr(wallet.name)}'),
                                  ]),
                                  maxLines: 2,
                                  style: monoStyle(p, 11, color: p.muted(0.4)),
                                ),
                              ],
                            ),
                          ),
                          if (soon) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(LucideIcons.bell, size: 14, color: p.expense)),
                          Text(formatCurrency(b.amount), style: monoStyle(p, 14, color: p.muted(0.8))),
                          IconButton(
                            tooltip: tr('Edit {name}', {'name': b.name}),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(LucideIcons.pencil, size: 16, color: p.muted(0.45)),
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              barrierColor: Colors.black.withValues(alpha: 0.45),
                              builder: (_) => _BillSheet(bill: b),
                            ),
                          ),
                          TrashButton(
                            tooltip: tr('Delete bill'),
                            onPressed: () async {
                              if (!await confirm(context, tr('Delete the bill "{name}"? Payments already in the ledger stay.', {'name': b.name}))) return;
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

/// Edit a bill: name, amount, due date, recurrence, and (with wallets) what its
/// payment is logged under and which wallet pays it.
class _BillSheet extends StatefulWidget {
  const _BillSheet({required this.bill});

  final Bill bill;

  @override
  State<_BillSheet> createState() => _BillSheetState();
}

class _BillSheetState extends State<_BillSheet> {
  late final _name = TextEditingController(text: widget.bill.name);
  late final _amount = TextEditingController(text: groupNumber(widget.bill.amount));
  late DateTime _due = fromDateKey(widget.bill.dueOn);
  late String _recurrence = widget.bill.recurrence;
  late String _categoryId = widget.bill.categoryId ?? '';
  late String? _walletId = widget.bill.walletId;
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
    final expenseCats = app.categories.where((c) => c.kind == Kind.expense).toList();
    final autoCat = billCategory(widget.bill.copyWith(name: _name.text, clearCategory: true), app.categories);

    Future<void> save() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      try {
        await app.editBill(Bill(
          id: widget.bill.id,
          name: _name.text.trim(),
          amount: (amt * 100).roundToDouble() / 100,
          dueOn: toDateKey(_due),
          recurrence: _recurrence,
          isPaid: widget.bill.isPaid,
          categoryId: _categoryId.isEmpty ? null : _categoryId,
          walletId: _walletId,
          lastPaidTxn: widget.bill.lastPaidTxn,
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
              Expanded(child: Text(tr('Edit bill'), style: displayStyle(p, 26))),
              IconButton(tooltip: tr('Close'), onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.45))),
            ]),
            const SizedBox(height: 12),
            FieldBlock(label: tr('Name'), child: TextField(controller: _name, inputFormatters: maxChars(Limits.name))),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: FieldBlock(label: tr('Amount'), child: AmountField(controller: _amount))),
              const SizedBox(width: 10),
              Expanded(child: FieldBlock(label: tr('Due'), child: DateButton(value: _due, hint: tr('Due date'), onPicked: (d) => setState(() => _due = d ?? _due)))),
            ]),
            const SizedBox(height: 14),
            FieldBlock(
              label: tr('Repeats'),
              child: AppDropdown(value: _recurrence, items: _recurrences, labelOf: _cap, onChanged: (v) => setState(() => _recurrence = v)),
            ),
            if (app.walletsReady) ...[
              const SizedBox(height: 14),
              FieldBlock(
                label: tr('Logged as'),
                child: AppDropdown(
                  value: _categoryId,
                  items: ['', for (final c in expenseCats) c.id],
                  labelOf: (id) => id.isEmpty
                      ? tr('{name} (auto)', {'name': tr(autoCat?.name ?? 'Other')})
                      : tr(expenseCats.firstWhere((c) => c.id == id).name),
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ),
              const SizedBox(height: 14),
              WalletPicker(value: _walletId ?? defaultWallet(app.wallets)?.id, onChanged: (id) => setState(() => _walletId = id), label: tr('Paid from')),
            ],
            const SizedBox(height: 18),
            PrimaryButton(expand: true, label: tr('Save'), busy: _busy, onPressed: valid ? save : null),
          ],
        ),
      ),
    );
  }
}

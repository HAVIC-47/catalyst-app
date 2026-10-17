// Dhar / baki — port of the web's /app/dhar: money you lent (they owe you) or
// borrowed (you owe them) — friends, family, shop credit. Part payments until it's
// settled; it moves money in and out of a wallet but never counts as spending or
// income.
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
import '../widgets/ui.dart';
import '../widgets/wallet_picker.dart';
import 'wallets_screen.dart' show UpdateNeeded;

class DharScreen extends StatefulWidget {
  const DharScreen({super.key});

  @override
  State<DharScreen> createState() => _DharScreenState();
}

class _DharScreenState extends State<DharScreen> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final pays = app.debtPayments;
    final open = app.debts.where((d) => debtIsOpen(d, pays)).toList();
    final closed = app.debts.where((d) => !debtIsOpen(d, pays)).toList();
    double owed(bool lent) => open.where((d) => d.lent == lent).fold<double>(0, (s, d) => s + debtRemaining(d, pays));
    final owedToYou = owed(true);
    final youOwe = owed(false);

    // One group per person, biggest balance first.
    final groups = <String, List<Debt>>{};
    for (final d in open) {
      groups.putIfAbsent(d.person.trim().toLowerCase(), () => []).add(d);
    }
    final people = [
      for (final list in groups.values)
        (person: list.first.person, list: list, net: list.fold<double>(0, (s, d) => s + (d.lent ? 1 : -1) * debtRemaining(d, pays))),
    ]..sort((a, b) => b.net.abs().compareTo(a.net.abs()));

    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(
            kicker: tr('Dhar · baki · {n} open', {'n': open.length}),
            title: tr('Who owes'),
            accent: tr('who.'),
            below: owedToYou > 0 || youOwe > 0
                ? Text.rich(
                    TextSpan(children: [
                      TextSpan(text: tr('Owed to you {amount}', {'amount': formatCurrency(owedToYou)}), style: TextStyle(color: p.income)),
                      TextSpan(text: ' · ', style: TextStyle(color: p.muted(0.3))),
                      TextSpan(text: tr('You owe {amount}', {'amount': formatCurrency(youOwe)}), style: TextStyle(color: p.expense)),
                    ]),
                    style: monoStyle(p, 13),
                  )
                : null,
          ),
          if (!app.loading && !app.walletsReady)
            const UpdateNeeded(feature: 'Dhar')
          else ...[
            const _NewDebt(),
            if (!app.loading && open.isEmpty)
              CardBox(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(children: [
                  Icon(LucideIcons.handCoins, size: 24, color: p.muted(0.25)),
                  const SizedBox(height: 10),
                  Text(
                    tr('Nothing owed either way. Add money you lent or borrowed above.'),
                    textAlign: TextAlign.center,
                    style: bodyStyle(p, 13.5, color: p.muted(0.4), height: 1.5),
                  ),
                ]),
              ),
            for (final g in people)
              CardBox(
                margin: const EdgeInsets.only(bottom: 14),
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(children: [
                        Expanded(child: Text(g.person, maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 15, weight: FontWeight.w500))),
                        Text(
                          g.net >= 0
                              ? tr('owes you {amount}', {'amount': formatCurrency(g.net)})
                              : tr('you owe {amount}', {'amount': formatCurrency(-g.net)}),
                          style: monoStyle(p, 13, color: g.net >= 0 ? p.income : p.expense),
                        ),
                      ]),
                    ),
                    for (final d in g.list) _DebtRow(debt: d),
                  ],
                ),
              ),
            if (closed.isNotEmpty) ...[
              const SizedBox(height: 12),
              Semantics(
                button: true,
                expanded: _showClosed,
                child: InkWell(
                  onTap: () => setState(() => _showClosed = !_showClosed),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Label(tr('Settled · {n}', {'n': closed.length})),
                      const SizedBox(width: 6),
                      Icon(_showClosed ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: p.labelColor),
                    ]),
                  ),
                ),
              ),
              if (_showClosed)
                CardBox(
                  margin: const EdgeInsets.only(top: 6),
                  padding: EdgeInsets.zero,
                  child: Column(children: [for (final d in closed) _DebtRow(debt: d, settled: true)]),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _NewDebt extends StatefulWidget {
  const _NewDebt();

  @override
  State<_NewDebt> createState() => _NewDebtState();
}

class _NewDebtState extends State<_NewDebt> {
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DebtDirection _direction = DebtDirection.lent;
  String? _walletId;
  DateTime _date = DateTime.now();
  DateTime? _due;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _person.addListener(() => setState(() {}));
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final amount = parseAmount(_amount.text);
    final valid = _person.text.trim().isNotEmpty && amount != null;
    final lent = _direction == DebtDirection.lent;
    final wallet = _walletId ?? startWallet(app.wallets);

    Future<void> add() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      try {
        await app.createDebt(
          person: _person.text.trim(),
          direction: _direction,
          amount: (amount * 100).roundToDouble() / 100,
          note: _note.text.trim(),
          walletId: wallet,
          occurredOn: toDateKey(_date),
          dueOn: _due == null ? null : toDateKey(_due!),
        );
        rememberWallet(wallet);
        _person.clear();
        _amount.clear();
        _note.clear();
        setState(() => _due = null);
      } catch (e) {
        if (context.mounted) showError(context, e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    Widget side(DebtDirection d, String label, String hint, Color on) {
      final active = _direction == d;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => setState(() => _direction = d),
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(color: active ? p.inkA(0.06) : Colors.transparent, borderRadius: BorderRadius.circular(9)),
              child: ExcludeSemantics(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                  Text(label, textAlign: TextAlign.center, style: bodyStyle(p, 14, weight: FontWeight.w500, color: active ? on : p.muted(0.45))),
                  Text(hint, textAlign: TextAlign.center, style: bodyStyle(p, 10.5, color: p.muted(0.4))),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return CardBox(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line), color: p.inkA(0.02)),
            child: Row(children: [
              side(DebtDirection.lent, tr('I lent'), tr('they owe me'), p.income),
              const SizedBox(width: 6),
              side(DebtDirection.borrowed, tr('I borrowed'), tr('I owe them'), p.expense),
            ]),
          ),
          const SizedBox(height: 14),
          FieldBlock(
            label: lent ? tr('Lent to') : tr('Borrowed from'),
            child: TextField(controller: _person, inputFormatters: maxChars(Limits.name), decoration: InputDecoration(hintText: tr('Name or shop'))),
          ),
          const SizedBox(height: 12),
          FieldBlock(label: tr('Amount'), child: AmountField(controller: _amount)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FieldBlock(
                label: tr('Date'),
                child: DateButton(value: _date, hint: tr('Date'), lastDate: DateTime.now(), onPicked: (d) => setState(() => _date = d ?? _date)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FieldBlock(
                label: tr('Due back · optional'),
                child: DateButton(value: _due, hint: tr('No date'), onPicked: (d) => setState(() => _due = d)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          WalletPicker(value: wallet, onChanged: (id) => setState(() => _walletId = id), label: lent ? tr('Paid out of') : tr('Received into')),
          const SizedBox(height: 12),
          FieldBlock(
            label: tr('Note · optional'),
            child: TextField(controller: _note, inputFormatters: maxChars(Limits.note), decoration: InputDecoration(hintText: tr('What it was for'))),
          ),
          const SizedBox(height: 14),
          PrimaryButton(expand: true, icon: LucideIcons.plus, label: tr('Add'), busy: _busy, onPressed: valid ? add : null),
        ],
      ),
    );
  }
}

class _DebtRow extends StatefulWidget {
  const _DebtRow({required this.debt, this.settled = false});

  final Debt debt;
  final bool settled;

  @override
  State<_DebtRow> createState() => _DebtRowState();
}

class _DebtRowState extends State<_DebtRow> {
  final _amount = TextEditingController();
  bool _paying = false;
  bool _history = false;
  bool _busy = false;
  String? _walletId;
  DateTime _date = DateTime.now();

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

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final d = widget.debt;
    final settled = widget.settled;
    final left = debtRemaining(d, app.debtPayments);
    final payments = app.debtPayments.where((x) => x.debtId == d.id).toList();
    final lent = d.lent;
    final today = DateTime.now();
    final days = d.dueOn == null ? null : fromDateKey(d.dueOn!).difference(DateTime(today.year, today.month, today.day)).inDays;
    String walletName(String? id) => tr((app.wallets.where((w) => w.id == id).firstOrNull ?? defaultWallet(app.wallets))?.name ?? '');

    Future<void> pay(double value) => _run(() async {
          await app.recordDebtPayment(
            debtId: d.id,
            amount: (value * 100).roundToDouble() / 100,
            walletId: _walletId ?? d.walletId ?? defaultWallet(app.wallets)?.id,
            paidOn: toDateKey(_date),
          );
          if (mounted) setState(() => _paying = false);
          _amount.clear();
        });

    final value = parseAmount(_amount.text);
    final dueColor = days == null ? null : (days < 0 ? p.expense : (days <= 2 ? p.accent : null));

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Opacity(
        opacity: settled ? 0.75 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(children: [
                      if (settled) TextSpan(text: '${d.person} · ', style: TextStyle(fontWeight: FontWeight.w500, color: p.muted(0.8))),
                      TextSpan(text: lent ? tr('Lent') : tr('Borrowed'), style: TextStyle(color: lent ? p.income : p.expense)),
                      const TextSpan(text: '  '),
                      TextSpan(text: formatCurrency(d.amount), style: monoStyle(p, 14, color: p.muted(0.85))),
                      const TextSpan(text: '  '),
                      TextSpan(text: fmt(fromDateKey(d.occurredOn), 'MMM d, yyyy'), style: monoStyle(p, 11, color: p.muted(0.4))),
                    ]),
                    style: bodyStyle(p, 14),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(children: [
                      if (!settled)
                        TextSpan(
                          text: lent
                              ? tr('{amount} still to get back', {'amount': formatCurrency(left)})
                              : tr('{amount} still to pay', {'amount': formatCurrency(left)}),
                          style: TextStyle(color: p.muted(0.6)),
                        ),
                      if (settled) TextSpan(text: d.closed && left > 0 ? tr('written off') : tr('settled')),
                      if (d.dueOn != null && !settled)
                        TextSpan(
                          text: ' · ${tr('due {date}', {'date': fmt(fromDateKey(d.dueOn!), 'MMM d')})}'
                              '${days! < 0 ? ' ${tr('({n}d late)', {'n': -days})}' : days == 0 ? ' ${tr('(today)')}' : ''}',
                          style: TextStyle(color: dueColor),
                        ),
                      if (app.wallets.isNotEmpty) TextSpan(text: ' · ${walletName(d.walletId)}'),
                      if (d.note.isNotEmpty) TextSpan(text: ' · ${d.note}'),
                    ]),
                    style: monoStyle(p, 11, color: p.muted(0.4)),
                  ),
                ]),
              ),
              if (settled && d.closed && left > 0)
                TextButton.icon(
                  onPressed: _busy ? null : () => _run(() => app.setDebtClosed(d.id, false)),
                  icon: Icon(LucideIcons.undo2, size: 14, color: p.muted(0.6)),
                  label: Text(tr('Reopen'), style: bodyStyle(p, 12, color: p.muted(0.6))),
                ),
              TrashButton(
                tooltip: tr('Delete'),
                onPressed: () async {
                  final ask = lent
                      ? tr('Delete this loan to {person} and its payments?', {'person': d.person})
                      : tr('Delete this loan from {person} and its payments?', {'person': d.person});
                  if (!await confirm(context, ask, action: tr('Delete'))) return;
                  await _run(() => app.removeDebt(d.id));
                },
              ),
            ]),
            if (!settled) ...[
              const SizedBox(height: 6),
              Wrap(children: [
                TextButton(
                  onPressed: () => setState(() {
                    _paying = !_paying;
                    _amount.text = groupNumber(left).replaceAll(',', '');
                  }),
                  child: Text(lent ? tr('Got some back') : tr('Paid some'), style: bodyStyle(p, 12.5, weight: FontWeight.w500, color: p.accent)),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => pay(left),
                  icon: Icon(LucideIcons.check, size: 14, color: p.income),
                  label: Text(tr('Settle'), style: bodyStyle(p, 12.5, weight: FontWeight.w500, color: p.income)),
                ),
              ]),
            ],
            if (_paying && !settled)
              Container(
                margin: const EdgeInsets.only(top: 6, right: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line), color: p.inkA(0.02)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: AmountField(controller: _amount, autofocus: true, semanticLabel: tr('Payment amount'))),
                    const SizedBox(width: 8),
                    Expanded(child: DateButton(value: _date, hint: tr('Date'), lastDate: DateTime.now(), onPicked: (x) => setState(() => _date = x ?? _date))),
                  ]),
                  const SizedBox(height: 10),
                  WalletPicker(
                    value: _walletId ?? d.walletId ?? defaultWallet(app.wallets)?.id,
                    onChanged: (id) => setState(() => _walletId = id),
                    label: lent ? tr('Received into') : tr('Paid out of'),
                  ),
                  const SizedBox(height: 8),
                  // Wraps on a narrow phone (Bangla labels run longer).
                  Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 6, children: [
                    if (left > 0)
                      TextButton(
                        onPressed: () async {
                          if (!await confirm(
                            context,
                            tr("Write off the {amount} still owed? It's closed without a payment.", {'amount': formatCurrency(left)}),
                            action: tr('Write off'),
                          )) {
                            return;
                          }
                          await _run(() => app.setDebtClosed(d.id, true));
                        },
                        child: Text(tr('Write off'), style: bodyStyle(p, 12, color: p.muted(0.5))),
                      ),
                    TextButton(onPressed: () => setState(() => _paying = false), child: Text(tr('Cancel'), style: bodyStyle(p, 13, color: p.muted(0.6)))),
                    PrimaryButton(
                      label: tr('Record'),
                      height: 40,
                      busy: _busy,
                      onPressed: value == null ? null : () => pay(value < left ? value : left),
                    ),
                  ]),
                ]),
              ),
            if (payments.isNotEmpty) ...[
              const SizedBox(height: 4),
              Semantics(
                button: true,
                expanded: _history,
                child: InkWell(
                  onTap: () => setState(() => _history = !_history),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Text(trn(payments.length, '{n} payment', '{n} payments'), style: monoStyle(p, 11, color: p.muted(0.4))),
                      Icon(_history ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 12, color: p.muted(0.4)),
                    ]),
                  ),
                ),
              ),
              if (_history)
                for (final x in payments)
                  Row(children: [
                    SizedBox(width: 60, child: Text(fmt(fromDateKey(x.paidOn), 'MMM d'), style: monoStyle(p, 11, color: p.muted(0.55)))),
                    Text(formatCurrency(x.amount), style: monoStyle(p, 11, color: p.muted(0.75))),
                    if (app.wallets.isNotEmpty) Text(' · ${walletName(x.walletId)}', style: monoStyle(p, 11, color: p.muted(0.55))),
                    const Spacer(),
                    IconButton(
                      tooltip: tr('Remove payment'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(LucideIcons.trash2, size: 14, color: p.muted(0.3)),
                      onPressed: () async {
                        if (!await confirm(context, tr('Remove this payment?'), action: tr('Remove'))) return;
                        await _run(() => app.removeDebtPayment(x.id));
                      },
                    ),
                  ]),
            ],
          ],
        ),
      ),
    );
  }
}

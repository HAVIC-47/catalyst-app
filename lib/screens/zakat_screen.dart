// Zakat calculator — port of the web's /app/zakat. What you own (wallets, cash
// elsewhere, gold, silver, money owed to you, investments) less what you owe now,
// against the nisab; 2.5% when it's at or above it. The figures are kept in the
// account's preferences, so the web shows the same ones (util/zakat.dart).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/money.dart';
import '../util/zakat.dart';
import '../widgets/ui.dart';

class ZakatScreen extends StatelessWidget {
  const ZakatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final z = app.zakat;
    final balances = walletBalances(app.wallets, app.transactions, app.transfers, app.debts, app.debtPayments);
    final open = app.debts.where((d) => debtIsOpen(d, app.debtPayments)).toList();
    final wallets = app.walletsReady ? balances.values.fold<double>(0, (s, b) => s + b) : 0.0;
    final owedToYou = open.where((d) => d.lent).fold<double>(0, (s, d) => s + debtRemaining(d, app.debtPayments));
    final youOwe = open.where((d) => !d.lent).fold<double>(0, (s, d) => s + debtRemaining(d, app.debtPayments));
    final r = zakatOf(z, wallets: wallets, owedToYou: owedToYou, youOwe: youOwe);
    final unit = z.unit == 'g' ? tr('g') : tr('bhori');
    final weight = nisabWeight(z.basis, z.unit);
    void set(ZakatInputs next) => app.setZakat(next);

    Future<void> logPaid() async {
      if (r.due <= 0) return;
      final messenger = ScaffoldMessenger.of(context);
      if (!await confirm(context, tr('Add {amount} to your ledger as zakat paid?', {'amount': formatCurrency(r.due)}), action: tr('Add'))) return;
      final cat = app.categories.where((c) => c.kind == Kind.expense && RegExp('zakat|যাকাত|জাকাত', caseSensitive: false).hasMatch(c.name)).firstOrNull ??
          app.categories.where((c) => c.kind == Kind.expense && RegExp('charity|donation|sadaqa', caseSensitive: false).hasMatch(c.name)).firstOrNull ??
          app.categories.where((c) => c.kind == Kind.expense && c.name == 'Other').firstOrNull;
      final today = toDateKey(DateTime.now());
      try {
        final t = await app.addMoney(NewTxn(
          kind: Kind.expense,
          amount: r.due,
          categoryId: cat?.id,
          categoryName: cat?.name ?? 'Other',
          note: tr('Zakat'),
          occurredOn: today,
          occurredAt: combineDateTime(today, nowTime()),
        ));
        messenger.showSnackBar(SnackBar(
          content: Text(tr('Zakat of {amount} added to the ledger.', {'amount': formatCurrency(r.due)})),
          action: SnackBarAction(label: tr('UNDO'), onPressed: () => app.removeMoney(t.id)),
        ));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }

    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(kicker: tr('Zakat'), title: tr('Zakat,'), accent: tr('worked out.')),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr("2.5% of what you've held for a lunar year, once it's at least the nisab. Your wallets and Dhar come in by themselves; add gold, silver and anything else."),
              style: bodyStyle(p, 12.5, color: p.muted(0.45), height: 1.45),
            ),
          ),
          // ---- the result first, so it's on the first screen
          CardBox(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Row(tr('What you have'), formatCurrency(r.assets)),
              _Row(tr('Less what you owe'), formatCurrency(-r.liabilities)),
              Divider(color: p.line, height: 14),
              _Row(tr('Counted for zakat'), formatCurrency(r.net), strong: true),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.accentA(0.1), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Label(tr('Zakat due (2.5%)'), size: 10),
                  const SizedBox(height: 4),
                  Text(formatCurrency(r.due), style: displayStyle(p, 34)),
                  const SizedBox(height: 6),
                  Text(
                    r.nisab == 0
                        ? tr('Add the price above to check it against the nisab.')
                        : r.above
                            ? tr("At or above the nisab — due once you've held it for a lunar year.")
                            : tr('Below the nisab — no zakat is due.'),
                    textAlign: TextAlign.center,
                    style: bodyStyle(p, 12, color: p.muted(0.55), height: 1.4),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              PrimaryButton(expand: true, icon: LucideIcons.handHeart, label: tr('Log it as paid'), onPressed: r.due > 0 ? logPaid : null),
              const SizedBox(height: 10),
              Text(tr('An estimate to help you. For your own situation, ask a scholar.'), style: bodyStyle(p, 11.5, color: p.muted(0.4), height: 1.4)),
            ]),
          ),
          // ---- nisab
          CardBox(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(tr('Nisab'), style: displayStyle(p, 19))),
                SegTabs<String>(
                  options: const ['silver', 'gold'],
                  value: z.basis,
                  compact: true,
                  label: (b) => b == 'gold' ? tr('Gold') : tr('Silver'),
                  onChanged: (b) => set(z.copyWith(basis: b)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                (z.basis == 'silver'
                        ? tr('{weight} {unit} of silver', {'weight': digits(weight.toStringAsFixed(z.unit == 'g' ? 2 : 1)), 'unit': unit})
                        : tr('{weight} {unit} of gold', {'weight': digits(weight.toStringAsFixed(z.unit == 'g' ? 2 : 1)), 'unit': unit})) +
                    (r.nisab > 0 ? ' = ${formatCurrency(r.nisab)}' : ''),
                style: bodyStyle(p, 14, color: p.muted(0.7)),
              ),
              if (r.nisab == 0) ...[
                const SizedBox(height: 4),
                Text(z.basis == 'silver' ? tr("Add today's silver price to see it.") : tr("Add today's gold price to see it."), style: bodyStyle(p, 12, color: p.accent)),
              ],
              const SizedBox(height: 6),
              Text(tr('Silver gives the lower nisab, so more people pay; many scholars advise it.'), style: bodyStyle(p, 11.5, color: p.muted(0.4), height: 1.4)),
            ]),
          ),
          // ---- what you have
          CardBox(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CardTitle(tr('What you'), tr('have')),
              const SizedBox(height: 12),
              if (app.walletsReady)
                _Check(
                  on: z.useWallets,
                  label: tr('Your wallets'),
                  hint: tr('Everything in Cash, bKash, Nagad, the bank…: {amount}', {'amount': formatCurrency(wallets)}),
                  onChanged: (v) => set(z.copyWith(useWallets: v)),
                ),
              _Check(
                on: z.useDhar,
                label: tr('Dhar'),
                hint: tr('Owed to you {owed} (counted) · you owe {owe} (taken off)', {'owed': formatCurrency(owedToYou), 'owe': formatCurrency(youOwe)}),
                onChanged: (v) => set(z.copyWith(useDhar: v)),
              ),
              const SizedBox(height: 4),
              _Money(label: tr('Cash or savings not in a wallet'), value: z.cash, onChanged: (n) => set(z.copyWith(cash: n))),
              _Money(label: tr('Investments, shares, business stock'), value: z.investments, onChanged: (n) => set(z.copyWith(investments: n))),
              _Money(label: tr('Anything else'), value: z.other, onChanged: (n) => set(z.copyWith(other: n))),
              _Money(label: '${tr('Debts due now (not in Dhar)')} · ${tr('Taken off')}', value: z.debts, onChanged: (n) => set(z.copyWith(debts: n))),
            ]),
          ),
          // ---- gold and silver
          CardBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: CardTitle(tr('Gold'), tr('& silver'))),
                SegTabs<String>(
                  options: const ['bhori', 'g'],
                  value: z.unit,
                  compact: true,
                  label: (u) => u == 'g' ? tr('grams') : tr('bhori'),
                  onChanged: (u) => set(z.copyWith(unit: u)),
                ),
              ]),
              const SizedBox(height: 12),
              for (final gold in [true, false]) ...[
                Text(gold ? tr('Gold') : tr('Silver'), style: bodyStyle(p, 14, weight: FontWeight.w600, color: p.muted(0.8))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _Number(
                      label: tr('You own ({unit})', {'unit': unit}),
                      value: gold ? z.gold : z.silver,
                      onChanged: (n) => set(gold ? z.copyWith(gold: n) : z.copyWith(silver: n)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Number(
                      label: tr("Today's price per {unit}", {'unit': unit}),
                      value: gold ? z.goldPrice : z.silverPrice,
                      money: true,
                      onChanged: (n) => set(gold ? z.copyWith(goldPrice: n) : z.copyWith(silverPrice: n)),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
              ],
              Text(tr("Use today's selling price — in Bangladesh, BAJUS publishes it. 1 bhori = 11.664 g."), style: bodyStyle(p, 11.5, color: p.muted(0.4), height: 1.4)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: monoStyle(p, 12.5, color: strong ? p.ink : p.muted(0.6)))),
        Text(value, style: monoStyle(p, 12.5, color: strong ? p.ink : p.muted(0.6), weight: strong ? FontWeight.w600 : FontWeight.w400)),
      ]),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.on, required this.label, required this.hint, required this.onChanged});

  final bool on;
  final String label;
  final String hint;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        toggled: on,
        label: label,
        child: Material(
          color: p.inkA(0.02),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(!on),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: bodyStyle(p, 14, color: p.muted(0.85))),
                      Text(hint, style: bodyStyle(p, 11.5, color: p.muted(0.45))),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  PillSwitch(on: on),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An amount field (in the account's currency) that reports a number as it's typed.
class _Money extends StatelessWidget {
  const _Money({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: _Number(label: label, value: value, money: true, onChanged: onChanged),
      );
}

class _Number extends StatefulWidget {
  const _Number({required this.label, required this.value, required this.onChanged, this.money = false});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool money;

  @override
  State<_Number> createState() => _NumberState();
}

class _NumberState extends State<_Number> {
  late final _c = TextEditingController(text: _text(widget.value));
  double _last = 0;

  static String _text(double v) => v == 0 ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : '$v');

  @override
  void initState() {
    super.initState();
    _last = widget.value;
  }

  @override
  void didUpdateWidget(_Number old) {
    super.didUpdateWidget(old);
    // Figures loaded from the account replace what's shown.
    if (widget.value != _last) {
      _last = widget.value;
      _c.text = _text(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    void changed(String s) {
      final n = double.tryParse(asciiDigits(s).replaceAll(',', '').trim()) ?? 0;
      _last = n < 0 ? 0 : n;
      widget.onChanged(_last);
    }

    return FieldBlock(
      label: widget.label,
      child: widget.money
          ? _MoneyInput(controller: _c, onChanged: changed)
          : TextField(
              controller: _c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: changed,
              style: monoStyle(p, 14),
              decoration: const InputDecoration(hintText: '0'),
            ),
    );
  }
}

class _MoneyInput extends StatelessWidget {
  const _MoneyInput({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      style: monoStyle(p, 14),
      decoration: InputDecoration(
        hintText: '0',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Text(currencySymbol(), style: monoStyle(p, 14, color: p.muted(0.4))),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

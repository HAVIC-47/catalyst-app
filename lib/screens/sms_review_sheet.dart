// Review what a bKash / Nagad message says before anything is saved (see
// services/sms.dart — it's shared or pasted into the app and parsed on the phone).
// Spending and income become entries in that wallet; cash in / out, add money and
// bank transfers become transfers between your wallets (a fee is logged as an
// expense).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../services/sms.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/money.dart';
import '../widgets/ui.dart';

/// A message shared to the app or pasted: its entries for review, or why there's
/// nothing to add.
Future<void> reviewSharedText(BuildContext context, String text) async {
  final found = await SmsShare.read(text);
  if (!context.mounted) return;
  if (found.fresh.isNotEmpty) return openSmsReview(context, found.fresh);
  final why = text.trim().isEmpty
      ? tr('Copy a bKash or Nagad message first, then tap Paste.')
      : found.already > 0
          ? tr('That message is already added.')
          : tr("That doesn't look like a bKash or Nagad payment message.");
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(why)));
}

Future<void> openSmsReview(BuildContext context, List<SmsTxn> items, {VoidCallback? onDone}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => SmsReviewSheet(items: items, onDone: onDone),
    );

/// How one message would be saved.
class SmsPlan {
  const SmsPlan({this.kind, this.wallet, this.from, this.to, this.problem});

  final Kind? kind; // expense / income entry, or null for a transfer
  final Wallet? wallet; // the entry's wallet
  final Wallet? from, to; // a transfer's wallets
  final String? problem; // why it can't be saved as it is

  bool get ok => problem == null;
}

bool _named(Wallet w, String provider) => w.name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '').contains(provider.toLowerCase());

/// Which wallets a message moves money between.
SmsPlan planSms(SmsTxn s, AppState app) {
  final live = app.walletsReady ? app.wallets.where((w) => !w.archived).toList() : const <Wallet>[];
  final mine = live.where((w) => _named(w, s.provider)).firstOrNull ?? (live.isEmpty ? null : defaultWallet(live));
  Wallet? ofKind(WalletKind k) => live.where((w) => w.kind == k && w.id != mine?.id).firstOrNull;
  if (s.isExpense) return SmsPlan(kind: Kind.expense, wallet: mine);
  if (s.isIncome) return SmsPlan(kind: Kind.income, wallet: mine);
  if (!app.walletsReady || mine == null) return SmsPlan(problem: tr('Moving money between wallets needs wallets (database update).'));
  final (other, label) = switch (s.action) {
    SmsAction.cashOut || SmsAction.cashIn => (ofKind(WalletKind.cash), tr('Cash')),
    _ => (ofKind(WalletKind.bank), tr('Bank')),
  };
  if (other == null) return SmsPlan(problem: tr('Add a {kind} wallet to record this.', {'kind': label}));
  final outward = s.action == SmsAction.cashOut || s.action == SmsAction.toBank;
  return SmsPlan(from: outward ? mine : other, to: outward ? other : mine);
}

class SmsReviewSheet extends StatefulWidget {
  const SmsReviewSheet({super.key, required this.items, this.onDone});

  final List<SmsTxn> items;
  final VoidCallback? onDone;

  @override
  State<SmsReviewSheet> createState() => _SmsReviewSheetState();
}

class _SmsReviewSheetState extends State<SmsReviewSheet> {
  final _off = <String>{}; // unticked
  final _category = <String, String>{}; // chosen category per message
  final _done = <String>{}; // saved already (a retry skips them)
  bool _busy = false;
  String _error = '';

  Category? _guess(SmsTxn s, List<Category> cats) {
    Category? named(List<String> names) {
      for (final n in names) {
        final c = cats.where((c) => c.name.toLowerCase() == n).firstOrNull;
        if (c != null) return c;
      }
      return null;
    }

    final pick = switch (s.action) {
      SmsAction.recharge => named(['mobile', 'phone', 'recharge', 'mobile recharge', 'internet', 'bills', 'utilities']),
      SmsAction.bill => named(['bills', 'utilities', 'bill']),
      SmsAction.received => named(['other', 'gift', 'gifts']),
      _ => null,
    };
    return pick ?? named(['other']) ?? cats.firstOrNull;
  }

  Future<void> _save(List<(SmsTxn, SmsPlan)> chosen) async {
    if (_busy) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = '';
    });
    var added = 0;
    try {
      for (final (s, plan) in chosen) {
        if (_done.contains(s.key)) continue;
        final day = toDateKey(s.when);
        final at = s.when.toUtc().toIso8601String();
        if (plan.kind != null) {
          final cats = app.categories.where((c) => c.kind == plan.kind).toList();
          final cat = cats.where((c) => c.id == _category[s.key]).firstOrNull ?? _guess(s, cats);
          await app.addMoney(NewTxn(
            kind: plan.kind!,
            amount: s.amount,
            categoryId: cat?.id,
            categoryName: cat?.name ?? 'Other',
            note: smsNote(s),
            occurredOn: day,
            occurredAt: at,
            walletId: plan.wallet?.id,
          ));
          if (s.fee > 0) {
            final fees = app.categories.where((c) => c.kind == Kind.expense).toList();
            final feeCat = fees.where((c) => RegExp(r'^(fees?|charges?)$', caseSensitive: false).hasMatch(c.name)).firstOrNull ??
                fees.where((c) => c.name.toLowerCase() == 'other').firstOrNull;
            await app.addMoney(NewTxn(
              kind: Kind.expense,
              amount: s.fee,
              categoryId: feeCat?.id,
              categoryName: feeCat?.name ?? 'Other',
              note: tr('{provider} fee', {'provider': s.provider}),
              occurredOn: day,
              occurredAt: at,
              walletId: plan.wallet?.id,
            ));
          }
        } else {
          await app.createTransfer(
            fromWallet: plan.from!.id,
            toWallet: plan.to!.id,
            amount: s.amount,
            note: smsNote(s),
            occurredOn: day,
            occurredAt: at,
            fee: s.fee,
          );
        }
        _done.add(s.key);
        added++;
      }
      await SmsShare.markSeen(widget.items);
      widget.onDone?.call();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(trn(added, 'Added {n} entry from your messages.', 'Added {n} entries from your messages.'))));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _skipAll() async {
    await SmsShare.markSeen(widget.items);
    widget.onDone?.call();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final plans = [for (final s in widget.items) (s, planSms(s, app))];
    final chosen = [for (final x in plans) if (x.$2.ok && !_off.contains(x.$1.key)) x];

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: p.line),
      ),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: p.inkA(0.2), borderRadius: BorderRadius.circular(4))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label(tr('bKash · Nagad')),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [TextSpan(text: '${tr('From your')} '), TextSpan(text: tr('messages.'), style: accentItalic(p, 28))]),
                    style: displayStyle(p, 28),
                  ),
                ]),
              ),
              IconButton(tooltip: tr('Close'), onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.4))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              tr('Read on this phone — nothing is saved or sent until you add it. Untick anything that isn\'t right.'),
              style: bodyStyle(p, 12.5, color: p.muted(0.5), height: 1.45),
            ),
          ),
          Divider(color: p.line, height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              itemCount: plans.length,
              separatorBuilder: (_, _) => Divider(color: p.line, height: 1),
              itemBuilder: (context, i) {
                final (s, plan) = plans[i];
                final on = plan.ok && !_off.contains(s.key) && !_done.contains(s.key);
                final cats = plan.kind == null ? const <Category>[] : app.categories.where((c) => c.kind == plan.kind).toList();
                final cat = cats.where((c) => c.id == _category[s.key]).firstOrNull ?? _guess(s, cats);
                final color = plan.kind == Kind.income ? p.income : (plan.kind == Kind.expense ? p.expense : p.saving);
                final what = plan.kind == Kind.income
                    ? tr('Income')
                    : plan.kind == Kind.expense
                        ? tr('Expense')
                        : tr('Transfer');
                return Opacity(
                  opacity: plan.ok ? 1 : 0.55,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Checkbox(
                        value: _done.contains(s.key) || on,
                        activeColor: p.accent,
                        onChanged: !plan.ok || _done.contains(s.key) ? null : (v) => setState(() => v == true ? _off.remove(s.key) : _off.add(s.key)),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(smsNote(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 14, weight: FontWeight.w500))),
                            Text(formatCurrency(s.amount), style: monoStyle(p, 14, color: color)),
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            [
                              what,
                              s.provider,
                              fmt(s.when, 'MMM d, h:mm a'),
                              if (plan.from != null) '${tr(plan.from!.name)} → ${tr(plan.to!.name)}',
                              if (plan.kind != null && plan.wallet != null) tr(plan.wallet!.name),
                              if (s.fee > 0) tr('fee {amount}', {'amount': formatCurrency(s.fee)}),
                            ].join(' · '),
                            style: monoStyle(p, 11, color: p.muted(0.45)),
                          ),
                          if (plan.problem != null) ...[
                            const SizedBox(height: 4),
                            Text(plan.problem!, style: bodyStyle(p, 12, color: p.expense)),
                          ],
                          if (on && cats.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            AppDropdown(
                              value: cat?.id ?? '',
                              items: [for (final c in cats) c.id],
                              labelOf: (id) => cats.firstWhere((c) => c.id == id).name,
                              onChanged: (id) => setState(() => _category[s.key] = id),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 11, color: p.muted(0.35), height: 1.35)),
                        ]),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(_error, style: bodyStyle(p, 12.5, color: p.expense)),
            ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              HairlineButton(
                height: 46,
                onPressed: _busy ? null : _skipAll,
                child: Text(tr('Skip all'), style: bodyStyle(p, 14, color: p.muted(0.75))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  expand: true,
                  busy: _busy,
                  label: trn(chosen.length, 'Add {n}', 'Add {n}'),
                  onPressed: chosen.isEmpty ? null : () => _save(chosen),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

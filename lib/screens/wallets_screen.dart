// Wallets — port of the web's /app/wallets: where the money sits (cash, bKash,
// Nagad, a bank account…), what's in each, and transfers between them. A transfer
// never counts as spending or income; a fee on one (a bKash cash-out, say) is
// logged as an expense.
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

const _colors = ['#2E8159', '#E2136E', '#F26522', '#3D80BC', '#7A4E86', '#B59A3C', '#CB453B', '#4C5B82', '#2F6F6B', '#7A746A'];

String kindLabel(WalletKind k) => tr(walletKindLabels[k]!);

class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final balances = walletBalances(app.wallets, app.transactions, app.transfers, app.debts, app.debtPayments);
    final live = app.wallets.where((w) => !w.archived).toList();
    final archived = app.wallets.where((w) => w.archived).toList();
    final total = live.fold<double>(0, (s, w) => s + (balances[w.id] ?? 0));
    final fallback = defaultWallet(app.wallets)?.id;

    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(
            kicker: tr('Wallets · {n}', {'n': live.length}),
            title: tr('Where it'),
            accent: tr('sits.'),
            below: app.walletsReady && live.isNotEmpty
                ? Text(tr('{amount} across your wallets', {'amount': formatCurrency(total)}), style: monoStyle(p, 13, color: p.muted(0.45)))
                : null,
          ),
          if (!app.loading && !app.walletsReady)
            const UpdateNeeded()
          else ...[
            for (final w in live)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _WalletCard(wallet: w, balance: balances[w.id] ?? 0, isDefault: w.id == fallback),
              ),
            _AddWallet(onTap: () => openWalletSheet(context)),
            const SizedBox(height: 16),
            if (live.length >= 2) const _TransferForm(),
            const _TransferList(),
            if (archived.isNotEmpty) ...[
              const SizedBox(height: 20),
              Label(tr('Archived · {n}', {'n': archived.length})),
              const SizedBox(height: 10),
              for (final w in archived)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WalletCard(wallet: w, balance: balances[w.id] ?? 0, isDefault: false),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              tr("A balance is the wallet's starting amount plus the income and expenses logged in it, its transfers, "
                  'and money lent or paid back from it. Savings entries stay in your savings pool — to move money into '
                  'a savings account, use a transfer.'),
              style: bodyStyle(p, 12, color: p.muted(0.4), height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown while the database doesn't have wallets yet (wallets, dhar).
class UpdateNeeded extends StatelessWidget {
  const UpdateNeeded({super.key, this.feature = 'Wallets'});

  final String feature;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CardBox(
      child: Text(
        tr('{feature} need a database update. In Supabase, open the SQL editor and run db/supabase.sql and then '
            'db/security.sql from the web repo — then pull down here to refresh.', {'feature': tr(feature)}),
        style: bodyStyle(p, 13.5, color: p.muted(0.6), height: 1.55),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet, required this.balance, required this.isDefault});

  final Wallet wallet;
  final double balance;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.read<AppState>();
    final w = wallet;
    final month = toDateKey(DateTime.now()).substring(0, 7);
    // Its own entries, plus (for the default wallet) those without a wallet.
    final known = {for (final x in app.wallets) x.id};
    final mine = app.transactions.where((t) => t.walletId == w.id || (isDefault && (t.walletId == null || !known.contains(t.walletId))));
    double sum(Kind k) => mine.where((t) => t.kind == k && t.occurredOn.startsWith(month)).fold<double>(0, (s, t) => s + t.amount);

    Future<void> run(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Opacity(
      opacity: w.archived ? 0.6 : 1,
      child: Semantics(
        container: true,
        label: tr('{name} wallet', {'name': w.name}),
        child: CardBox(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: hexColor(w.color), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr(w.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 15, weight: FontWeight.w500))),
                  Label(isDefault ? tr('{kind} · default', {'kind': kindLabel(w.kind)}) : kindLabel(w.kind)),
                ]),
              ),
              const SizedBox(height: 10),
              Text(formatCurrency(balance), style: monoStyle(p, 28, weight: FontWeight.w600, color: balance < 0 ? p.expense : p.ink)),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: tr('This month: ')),
                  TextSpan(text: tr('in {amount}', {'amount': formatCurrency(sum(Kind.income))}), style: TextStyle(color: p.income)),
                  const TextSpan(text: ' · '),
                  TextSpan(text: tr('out {amount}', {'amount': formatCurrency(sum(Kind.expense))}), style: TextStyle(color: p.expense)),
                ]),
                style: monoStyle(p, 11, color: p.muted(0.4)),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: p.line),
              Row(children: [
                TextButton.icon(
                  onPressed: () => openWalletSheet(context, wallet: w, balance: balance),
                  icon: Icon(LucideIcons.pencil, size: 14, color: p.muted(0.6)),
                  label: Text(tr('Edit'), style: bodyStyle(p, 12.5, color: p.muted(0.6))),
                ),
                TextButton.icon(
                  onPressed: () => run(() => app.editWallet(w.id, archived: !w.archived)),
                  icon: Icon(w.archived ? LucideIcons.archiveRestore : LucideIcons.archive, size: 14, color: p.muted(0.6)),
                  label: Text(w.archived ? tr('Restore') : tr('Archive'), style: bodyStyle(p, 12.5, color: p.muted(0.6))),
                ),
                const Spacer(),
                TrashButton(
                  tooltip: tr('Delete {name}', {'name': w.name}),
                  onPressed: () async {
                    if (!await confirm(
                      context,
                      tr('Delete the {name} wallet? Its entries move to your default wallet, and its transfers are removed.', {'name': w.name}),
                      action: tr('Delete'),
                    )) {
                      return;
                    }
                    await run(() => app.removeWallet(w.id));
                  },
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddWallet extends StatelessWidget {
  const _AddWallet({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: tr('Add a wallet'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: _DashedBorder(p.line),
            child: SizedBox(
              height: 72,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(LucideIcons.plus, size: 18, color: p.muted(0.5)),
                const SizedBox(width: 8),
                Text(tr('Add a wallet'), style: bodyStyle(p, 14, color: p.muted(0.55))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, (d + 5).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// New wallet, or edit one ([wallet] with its current [balance]).
Future<void> openWalletSheet(BuildContext context, {Wallet? wallet, double balance = 0}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _WalletSheet(wallet: wallet, balance: balance),
    );

class _WalletSheet extends StatefulWidget {
  const _WalletSheet({this.wallet, this.balance = 0});

  final Wallet? wallet;
  final double balance;

  @override
  State<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<_WalletSheet> {
  late final _name = TextEditingController(text: widget.wallet?.name ?? '');
  late final _now = TextEditingController(text: widget.wallet == null ? '' : groupNumber(widget.balance.abs()).replaceAll(',', '').padLeft(1));
  late WalletKind _kind = widget.wallet?.kind ?? WalletKind.mobile;
  late String _color = widget.wallet?.color ?? _colors[4];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.wallet != null && widget.balance < 0) _now.text = '-${_now.text}';
    _name.addListener(() => setState(() {}));
    _now.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.read<AppState>();
    final w = widget.wallet;
    final now = _now.text.trim().isEmpty && w == null ? 0.0 : parseSigned(_now.text);
    final valid = _name.text.trim().isNotEmpty && now != null;

    Future<void> save() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      try {
        if (w == null) {
          await app.createWallet(name: _name.text.trim(), kind: _kind, color: _color, openingBalance: (now * 100).roundToDouble() / 100);
        } else {
          // "Balance now" sets the starting amount so the wallet adds up to it.
          final opening = ((w.openingBalance + (now - widget.balance)) * 100).roundToDouble() / 100;
          await app.editWallet(w.id, name: _name.text.trim(), kind: _kind, color: _color, openingBalance: opening);
        }
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
              Expanded(child: Text(w == null ? tr('New wallet') : tr('Edit wallet'), style: displayStyle(p, 26))),
              IconButton(tooltip: tr('Close'), onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.45))),
            ]),
            const SizedBox(height: 12),
            FieldBlock(
              label: tr('Name'),
              child: TextField(
                controller: _name,
                autofocus: w == null,
                inputFormatters: maxChars(Limits.name),
                decoration: InputDecoration(hintText: tr('Name (e.g. Rocket, DBBL)')),
              ),
            ),
            const SizedBox(height: 14),
            FieldBlock(
              label: tr('Kind'),
              child: AppDropdown(
                value: _kind.name,
                items: [for (final k in WalletKind.values) k.name],
                labelOf: (k) => kindLabel(walletKindFrom(k)),
                onChanged: (k) => setState(() => _kind = walletKindFrom(k)),
              ),
            ),
            const SizedBox(height: 14),
            FieldBlock(
              label: tr('Balance now'),
              child: AmountField(controller: _now, signed: true, hint: w == null ? tr("What's in it now") : '0'),
            ),
            const SizedBox(height: 14),
            FieldBlock(
              label: tr('Color'),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _colors)
                    Semantics(
                      button: true,
                      selected: _color == c,
                      label: tr('Color {hex}', {'hex': c}),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle),
                          child: _color == c ? Icon(LucideIcons.check, size: 16, color: p.onAccent) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(expand: true, icon: w == null ? LucideIcons.plus : null, label: w == null ? tr('Add') : tr('Save'), busy: _busy, onPressed: valid ? save : null),
          ],
        ),
      ),
    );
  }
}

class _TransferForm extends StatefulWidget {
  const _TransferForm();

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  final _amount = TextEditingController();
  final _fee = TextEditingController();
  final _note = TextEditingController();
  String? _from;
  String? _to;
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _fee.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final live = app.wallets.where((w) => !w.archived).toList();
    final ids = [for (final w in live) w.id];
    final from = ids.contains(_from) ? _from! : ids.first;
    final to = ids.contains(_to) ? _to! : ids[1];
    final amount = parseAmount(_amount.text);
    final valid = from != to && amount != null;
    String name(String id) => tr(live.firstWhere((w) => w.id == id).name);

    Future<void> move() async {
      if (!valid || _busy) return;
      setState(() => _busy = true);
      final messenger = ScaffoldMessenger.of(context);
      try {
        final day = toDateKey(_date);
        await app.createTransfer(
          fromWallet: from,
          toWallet: to,
          amount: (amount * 100).roundToDouble() / 100,
          note: _note.text.trim(),
          occurredOn: day,
          occurredAt: combineDateTime(day, day == toDateKey(DateTime.now()) ? nowTime() : '12:00'),
          fee: parseAmount(_fee.text) ?? 0,
        );
        messenger.showSnackBar(SnackBar(
          content: Text(tr('Moved {amount} from {from} to {to}.', {'amount': formatCurrency(amount), 'from': name(from), 'to': name(to)})),
        ));
        _amount.clear();
        _fee.clear();
        _note.clear();
      } catch (e) {
        if (context.mounted) showError(context, e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return CardBox(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitle(tr('Move|title'), tr('money.'), size: 22),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: FieldBlock(
                label: tr('From|wallet'),
                child: AppDropdown(value: from, items: ids, labelOf: name, onChanged: (v) => setState(() => _from = v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: Icon(LucideIcons.arrowRight, size: 18, color: p.muted(0.3)),
            ),
            Expanded(
              child: FieldBlock(
                label: tr('To|wallet'),
                child: AppDropdown(value: to, items: ids, labelOf: name, onChanged: (v) => setState(() => _to = v)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FieldBlock(label: tr('Amount'), child: AmountField(controller: _amount))),
            const SizedBox(width: 10),
            Expanded(child: FieldBlock(label: tr('Fee · optional'), child: AmountField(controller: _fee))),
          ]),
          const SizedBox(height: 12),
          FieldBlock(label: tr('Date'), child: DateButton(value: _date, hint: tr('Date'), onPicked: (d) => setState(() => _date = d ?? _date))),
          const SizedBox(height: 12),
          FieldBlock(
            label: tr('Note · optional'),
            child: TextField(controller: _note, inputFormatters: maxChars(Limits.note), decoration: InputDecoration(hintText: tr('Cash out, top-up…'))),
          ),
          if (from == to) ...[
            const SizedBox(height: 8),
            Text(tr('Pick two different wallets.'), style: bodyStyle(p, 12, color: p.expense)),
          ],
          const SizedBox(height: 10),
          Text(tr('A fee is added to your ledger as an expense from the first wallet.'), style: bodyStyle(p, 11.5, color: p.muted(0.4), height: 1.4)),
          const SizedBox(height: 12),
          PrimaryButton(expand: true, icon: LucideIcons.arrowLeftRight, label: tr('Move'), busy: _busy, onPressed: valid ? move : null),
        ],
      ),
    );
  }
}

class _TransferList extends StatelessWidget {
  const _TransferList();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    if (app.transfers.isEmpty) return const SizedBox.shrink();
    String name(String id) => tr(app.wallets.where((w) => w.id == id).firstOrNull?.name ?? 'Deleted wallet');
    return CardBox(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 10), child: Label(tr('Transfers · {n}', {'n': app.transfers.length}))),
          for (final t in app.transfers.take(30))
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(children: [
                SizedBox(width: 56, child: Text(fmt(fromDateKey(t.occurredOn), 'MMM d'), style: monoStyle(p, 11, color: p.muted(0.4)))),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${name(t.fromWallet)} → ${name(t.toWallet)}'),
                      if (t.note.isNotEmpty) TextSpan(text: ' · ${t.note}', style: TextStyle(color: p.muted(0.4))),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(p, 13.5, color: p.muted(0.8)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatCurrency(t.amount), style: monoStyle(p, 13.5, color: p.muted(0.8))),
                TrashButton(
                  tooltip: tr('Delete transfer'),
                  onPressed: () async {
                    if (!await confirm(context, tr("Delete this transfer? Both wallets' balances go back."), action: tr('Delete'))) return;
                    try {
                      await app.removeTransfer(t.id);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// A dhar movement shown among a day's entries (the ledger and a calendar day's
// Transactions tab): + into a wallet, − out of it.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/money.dart';

class DharLine extends StatelessWidget {
  const DharLine({super.key, required this.move, this.wallet, this.divider = true});

  final DharMove move;
  final String? wallet;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      decoration: BoxDecoration(border: divider ? Border(top: BorderSide(color: p.line)) : null),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: p.accentA(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(LucideIcons.handCoins, size: 16, color: p.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(move.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 14, color: p.muted(0.85))),
            Text(wallet == null ? tr('Dhar') : '${tr('Dhar')} · $wallet', maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 11.5, color: p.muted(0.4))),
          ]),
        ),
        Text(formatCurrency(move.amount, sign: true), style: monoStyle(p, 14, color: move.amount > 0 ? p.income : p.muted(0.8))),
      ]),
    );
  }
}

// Picks the wallet an entry came from or went into — the web's WalletSelect.
// Shows nothing until the database has wallets, so older setups look as before.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/i18n.dart';
import '../util/money.dart';
import 'ui.dart';

const _lastKey = 'wallet:last';
String? _last;

/// Read once at startup (AppShell): the wallet used last on this phone.
Future<void> loadLastWallet() async => _last = (await SharedPreferences.getInstance()).getString(_lastKey);

/// The wallet a new entry starts with: the one used last, else the default.
String? startWallet(List<Wallet> wallets) {
  final live = wallets.where((w) => !w.archived);
  return live.where((w) => w.id == _last).firstOrNull?.id ?? defaultWallet(wallets)?.id;
}

/// Remember the wallet just used, for the next entry.
void rememberWallet(String? id) {
  if (id == null) return;
  _last = id;
  SharedPreferences.getInstance().then((p) => p.setString(_lastKey, id));
}

class WalletPicker extends StatelessWidget {
  const WalletPicker({super.key, required this.value, required this.onChanged, this.label});

  final String? value;
  final ValueChanged<String> onChanged;
  final String? label; // the English text; shown through tr()

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    if (!app.walletsReady || app.wallets.isEmpty) return const SizedBox.shrink();
    // Archived wallets stay listed only when they're the current choice.
    final options = app.wallets.where((w) => !w.archived || w.id == value).toList();
    final current = value ?? defaultWallet(app.wallets)?.id;
    return FieldBlock(
      label: tr(label ?? 'Wallet'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final w in options)
            Semantics(
              button: true,
              selected: current == w.id,
              label: tr(w.name),
              child: Material(
                color: current == w.id ? p.inkA(0.06) : Colors.transparent,
                shape: StadiumBorder(side: BorderSide(color: current == w.id ? p.inkA(0.3) : p.line)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onChanged(w.id),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: hexColor(w.color), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(tr(w.name),
                            style: bodyStyle(p, 13, weight: FontWeight.w500, color: current == w.id ? p.ink : p.muted(0.6))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

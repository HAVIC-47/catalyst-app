// Expenses still missing a price — things marked as bought before their price was
// known — all in one list to fill in at the end of a shopping trip. Reached from the
// notification, the banner and the ledger. A price saved here also goes on the item.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/ui.dart';

Future<void> openPriceSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const PriceSheet(),
    );

class PriceSheet extends StatefulWidget {
  const PriceSheet({super.key});

  @override
  State<PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<PriceSheet> {
  final _fields = <String, TextEditingController>{};
  bool _busy = false;

  TextEditingController _field(String id) => _fields.putIfAbsent(id, () => TextEditingController()..addListener(() => setState(() {})));

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<(String, double)> get _filled => [
        for (final e in _fields.entries)
          if (parseAmount(e.value.text) case final v?) (e.key, (v * 100).round() / 100),
      ];

  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await app.setPrices(_filled);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = context.watch<AppState>().needPrice;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: p.line),
      ),
      padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: p.inkA(0.2), borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Label(tr('Add prices')),
                const SizedBox(height: 4),
                Text(tr('What did you pay?'), style: displayStyle(p, 26)),
              ]),
            ),
            IconButton(tooltip: tr('Close'), onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.45))),
          ]),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(tr('Nothing is waiting for a price.'), textAlign: TextAlign.center, style: bodyStyle(p, 13.5, color: p.muted(0.5))),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final (i, t) in items.indexed) _row(p, t, first: i == 0)],
              ),
            ),
          const SizedBox(height: 14),
          Row(children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Later'), style: bodyStyle(p, 14, color: p.muted(0.6)))),
            const SizedBox(width: 8),
            Expanded(child: PrimaryButton(expand: true, label: tr('Save'), busy: _busy, onPressed: _filled.isEmpty ? null : _save)),
          ]),
        ],
      ),
    );
  }

  Widget _row(Palette p, Txn t, {required bool first}) {
    final name = t.note.isEmpty ? tr(t.categoryName) : t.note;
    return Container(
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 14, color: p.muted(0.85))),
            const SizedBox(height: 2),
            Text('${fmt(fromDateKey(t.occurredOn), 'MMM d')} · ${tr(t.categoryName)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 11.5, color: p.muted(0.45))),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 128, child: AmountField(controller: _field(t.id), autofocus: first, semanticLabel: tr('Price of {name}', {'name': name}))),
      ]),
    );
  }
}

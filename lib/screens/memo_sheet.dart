// Memo scanner — port of the web's MemoScanner: take or choose a photo of a memo
// (receipt) or a screenshot of notes, let the web app's /api/scan-memo read it
// with Gemini, review what it found, then save. A memo's items each become an
// expense; a note's lines become expenses and income, and categories the note
// names that don't exist yet are created (the user is told which). The Gemini
// key stays on the server; the request carries the user's Supabase session token.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_state.dart';
import '../data/scan.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/currency.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/limits.dart';
import '../widgets/scan_ui.dart';
import '../widgets/ui.dart';
import '../widgets/wallet_picker.dart';
import 'entry_sheet.dart';

Future<void> openMemoScanner(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (c) => MemoSheet(
      // Open from the caller's context — the sheet's is gone once it closes.
      onManualEntry: () {
        Navigator.pop(c);
        openEntry(context);
      },
    ),
  );
}

class _MemoItem {
  const _MemoItem(this.name, this.amount, this.category);
  final String name;
  final double amount;
  final String category;
}

class _Memo {
  _Memo.fromJson(Map<String, dynamic> j)
      : merchant = j['merchant'] as String? ?? '',
        date = j['date'] as String? ?? '',
        time = j['time'] as String? ?? '',
        currency = j['currency'] as String? ?? '',
        items = [
          for (final i in (j['items'] as List? ?? const []).whereType<Map>())
            _MemoItem('${i['name'] ?? 'Item'}', (i['amount'] as num?)?.toDouble() ?? 0, '${i['category'] ?? ''}'),
        ],
        extras = [
          for (final x in (j['extras'] as List? ?? const []).whereType<Map>())
            _MemoItem('${x['name'] ?? 'Extra'}', (x['amount'] as num?)?.toDouble() ?? 0, ''),
        ],
        discount = (j['discount'] as num?)?.toDouble() ?? 0,
        total = (j['total'] as num?)?.toDouble() ?? 0;

  final String merchant, date, time, currency;
  final List<_MemoItem> items, extras;
  final double discount, total;
}

/// A note of expenses and income, as the reader returns it.
class _Notes {
  _Notes.fromJson(Map<String, dynamic> j)
      : date = j['date'] as String? ?? '',
        entries = [
          for (final e in (j['entries'] as List? ?? const []).whereType<Map>())
            (
              type: e['type'] == 'income' ? Kind.income : Kind.expense,
              name: '${e['name'] ?? ''}',
              amount: (e['amount'] as num?)?.toDouble() ?? 0,
              category: '${e['category'] ?? ''}',
              date: e['date'] as String? ?? '',
            ),
        ];

  final String date; // the note's own date, '' if none
  final List<({Kind type, String name, double amount, String category, String date})> entries;
}

class _Line {
  _Line(String name, double amount, this.categoryId)
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: _plain(amount));

  final TextEditingController name;
  final TextEditingController amount;
  String categoryId;
  bool on = true;
  bool saved = false;

  double get value => double.tryParse(amount.text) ?? 0;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

/// A line read from a note: expense or income, with a category by name (a new
/// one is created on save).
class _Entry {
  _Entry({required this.type, required String name, required double amount, required this.category, required this.date})
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: _plain(amount));

  Kind type;
  final TextEditingController name;
  final TextEditingController amount;
  String category;
  String date; // yyyy-mm-dd
  bool on = true;
  bool saved = false;

  double get value => double.tryParse(amount.text) ?? 0;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

// Colors for categories a note creates (the Settings swatches, same as the web).
const _newColors = ['#C06A33', '#2E8159', '#3D80BC', '#7A4E86', '#B59A3C', '#CB453B', '#4C5B82', '#8E5B6E', '#2F6F6B'];

/// Discount share for each line, proportional to its amount, rounded so the
/// shares add up exactly (same rule as the web's discountShares).
List<double> _discountShares(List<double> amounts, double discount) {
  final sum = amounts.fold<double>(0, (s, a) => s + a);
  if (discount <= 0 || sum <= discount) return [for (final _ in amounts) 0];
  final shares = [for (final a in amounts) (discount * a / sum * 100).roundToDouble() / 100];
  final drift = ((discount - shares.fold<double>(0, (s, x) => s + x)) * 100).roundToDouble() / 100;
  if (drift != 0) {
    var biggest = 0;
    for (var i = 1; i < amounts.length; i++) {
      if (amounts[i] > amounts[biggest]) biggest = i;
    }
    shares[biggest] = ((shares[biggest] + drift) * 100).roundToDouble() / 100;
  }
  return shares;
}

enum _Step { pick, reading, review, notes, done, error }

class MemoSheet extends StatefulWidget {
  const MemoSheet({super.key, required this.onManualEntry});

  final VoidCallback onManualEntry;

  @override
  State<MemoSheet> createState() => _MemoSheetState();
}

class _MemoSheetState extends State<MemoSheet> {
  final _place = TextEditingController();
  _Step _step = _Step.pick;
  Uint8List? _photo;
  String _error = '';
  _Memo? _memo;
  List<_Line> _lines = [];
  String _dateKey = toDateKey(DateTime.now());
  String _time = nowTime();
  String _oddDate = '';
  bool _saving = false;
  int _addedCount = 0;
  double _addedSum = 0;
  // Notes: their lines, and what was saved (for the done screen).
  List<_Entry> _entries = [];
  ({int count, double spent, double earned, List<Category> created})? _noted;
  int _run = 0; // bumps on reset, so a late reply from an abandoned scan is ignored
  String? _walletId; // where the money came from / went (null = the one used last)

  /// The wallet the scanned entries go in (null while the database has no wallets).
  String? _wallet(AppState app) => app.walletsReady ? _walletId ?? startWallet(app.wallets) : null;

  @override
  void dispose() {
    _place.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  List<Category> get _cats => context
      .read<AppState>()
      .categories
      .where((c) => c.kind == Kind.expense && c.name != breakSaving)
      .toList();

  List<Category> get _incomeCats => context.read<AppState>().categories.where((c) => c.kind == Kind.income).toList();

  void _reset() {
    for (final l in _lines) {
      l.dispose();
    }
    for (final e in _entries) {
      e.dispose();
    }
    setState(() {
      _run++;
      _step = _Step.pick;
      _photo = null;
      _memo = null;
      _lines = [];
      _entries = [];
      _noted = null;
      _error = '';
    });
  }

  Future<void> _pick(ImageSource source) async {
    final Uint8List? bytes;
    try {
      bytes = await Scan.pick(source);
    } on ScanError catch (e) {
      _fail(e.message);
      return;
    }
    if (bytes == null || !mounted) return;
    await _read(bytes);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _step = _Step.error;
    });
  }

  Future<void> _read(Uint8List bytes) async {
    final mime = imageMime(bytes);
    if (mime == null) {
      _fail(tr('Couldn\'t open that image — use a JPEG or PNG photo.'));
      return;
    }
    final run = ++_run;
    setState(() {
      _step = _Step.reading;
      _photo = bytes;
      _error = '';
    });
    try {
      final data = await Scan.send('/api/scan-memo', {
        'image': base64Encode(bytes),
        'mimeType': mime,
        'categories': [for (final c in _cats) c.name],
        'incomeCategories': [for (final c in _incomeCats) c.name],
        'notes': true, // also read screenshots of notes (expenses and income)
        'today': toDateKey(DateTime.now()),
      });
      if (!mounted || run != _run) return;
      final notes = data['notes'], memo = data['memo'];
      if (notes is Map<String, dynamic>) {
        _reviewNotes(_Notes.fromJson(notes));
      } else if (memo is Map<String, dynamic>) {
        _review(_Memo.fromJson(memo));
      } else {
        throw ScanError(tr('The memo reader couldn\'t process this photo.'));
      }
    } on ScanError catch (e) {
      if (run == _run) _fail(e.message);
    } catch (_) {
      if (run == _run) _fail(tr('No connection — try again.'));
    }
  }

  void _review(_Memo m) {
    final cats = _cats;
    Category? byName(String name) {
      for (final c in cats) {
        if (c.name.toLowerCase() == name.toLowerCase()) return c;
      }
      return null;
    }

    final fallback = byName('Other') ?? (cats.isEmpty ? null : cats.first);
    // VAT, service charge etc. go with the memo's main category (its biggest item).
    final biggest = [...m.items]..sort((a, b) => b.amount.compareTo(a.amount));
    final mainCat = (biggest.isEmpty ? null : byName(biggest.first.category)) ?? fallback;
    for (final l in _lines) {
      l.dispose();
    }
    // Trust the printed date only if it's from the last month: a misread digit
    // (৩ vs ৬) would otherwise file the expenses years away from today.
    final today = toDateKey(DateTime.now());
    final monthAgo = toDateKey(DateTime.now().subtract(const Duration(days: 31)));
    final recent = m.date.isNotEmpty && m.date.compareTo(today) <= 0 && m.date.compareTo(monthAgo) >= 0;
    setState(() {
      _memo = m;
      _lines = [
        for (final i in m.items) _Line(i.name, i.amount, (byName(i.category) ?? fallback)?.id ?? ''),
        for (final x in m.extras) _Line(x.name, x.amount, mainCat?.id ?? ''),
      ];
      _place.text = m.merchant;
      _dateKey = recent ? m.date : today;
      _oddDate = m.date.isNotEmpty && !recent ? m.date : '';
      _time = m.time.isNotEmpty ? m.time : nowTime();
      _step = _Step.review;
    });
  }

  Future<void> _save(List<(_Line, double)> chosen, double sum) async {
    if (chosen.isEmpty || _saving) return;
    final app = context.read<AppState>();
    final cats = _cats;
    setState(() {
      _saving = true;
      _error = '';
    });
    final occurredAt = combineDateTime(_dateKey, _time);
    final wallet = _wallet(app);
    var done = 0;
    try {
      for (final (line, amount) in chosen) {
        final cat = cats.where((c) => c.id == line.categoryId).firstOrNull ?? (cats.isEmpty ? null : cats.first);
        await app.addMoney(NewTxn(
          kind: Kind.expense,
          amount: amount,
          categoryId: cat?.id,
          categoryName: cat?.name ?? 'Other',
          place: _clip(_place.text, Limits.place),
          note: _clip(line.name.text, Limits.note),
          occurredOn: _dateKey,
          occurredAt: occurredAt,
          walletId: wallet,
        ));
        // Mark it saved right away so a retry after an error never adds it twice.
        line.saved = true;
        done++;
      }
      rememberWallet(wallet);
      if (!mounted) return;
      setState(() {
        _addedCount = done;
        _addedSum = sum;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is PostgrestException ? e.message : tr('Couldn\'t save — check your connection.');
      setState(() => _error = done > 0 ? tr('Added {done} of {n}. {msg} Tap Add again for the rest.', {'done': done, 'n': chosen.length, 'msg': msg}) : msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------- notes
  List<Category> _catsOf(Kind type) => type == Kind.income ? _incomeCats : _cats;

  Category? _findCat(Kind type, String name) {
    final n = name.trim().toLowerCase();
    return context.read<AppState>().categories.where((c) => c.kind == type && c.name.toLowerCase() == n).firstOrNull;
  }

  String _categoryOf(_Entry e) {
    final name = _clip(e.category, Limits.name);
    return name.isEmpty ? 'Other' : name;
  }

  void _reviewNotes(_Notes n) {
    final fallback = n.date.isNotEmpty ? n.date : toDateKey(DateTime.now());
    for (final e in _entries) {
      e.dispose();
    }
    setState(() {
      _entries = [
        for (final e in n.entries)
          _Entry(
            type: e.type,
            name: e.name,
            amount: e.amount,
            // The user's own spelling when the category exists.
            category: _findCat(e.type, e.category)?.name ?? e.category,
            date: e.date.isNotEmpty ? e.date : fallback,
          ),
      ];
      _noted = null;
      _time = nowTime();
      _step = _Step.notes;
    });
  }

  List<_Entry> get _chosenEntries => _entries.where((e) => e.on && !e.saved && e.value > 0).toList();

  /// Categories the chosen lines name that the user doesn't have yet (created on save).
  List<(Kind, String)> _freshCats(List<_Entry> chosen) {
    final fresh = <String, (Kind, String)>{};
    for (final e in chosen) {
      final name = _categoryOf(e);
      if (_findCat(e.type, name) == null) fresh.putIfAbsent('${e.type.name}:${name.toLowerCase()}', () => (e.type, name));
    }
    return fresh.values.toList();
  }

  Future<void> _saveNotes() async {
    final chosen = _chosenEntries;
    if (chosen.isEmpty || _saving) return;
    final app = context.read<AppState>();
    setState(() {
      _saving = true;
      _error = '';
    });
    final created = <Category>[];
    final wallet = _wallet(app);
    var done = 0;
    var spent = 0.0, earned = 0.0;
    // Keeps what did get saved, so the done screen tells the whole story even after a retry.
    void tally() {
      final prev = _noted;
      _noted = (
        count: (prev?.count ?? 0) + done,
        spent: (prev?.spent ?? 0) + spent,
        earned: (prev?.earned ?? 0) + earned,
        created: [...?prev?.created, ...created],
      );
    }

    try {
      // 1. Categories the note named that don't exist yet.
      final byKey = <String, Category>{};
      for (final e in chosen) {
        final name = _categoryOf(e);
        final k = '${e.type.name}:${name.toLowerCase()}';
        if (byKey.containsKey(k)) continue;
        final existing = _findCat(e.type, name);
        if (existing != null) {
          byKey[k] = existing;
          continue;
        }
        final c = await app.createCategory(
          name: name,
          kind: e.type,
          color: _newColors[app.categories.length % _newColors.length],
          sort: app.categories.where((c) => c.kind == e.type).length,
        );
        created.add(c);
        byKey[k] = c;
      }
      // 2. One entry per line.
      for (final e in chosen) {
        final cat = byKey['${e.type.name}:${_categoryOf(e).toLowerCase()}']!;
        final amount = (e.value * 100).roundToDouble() / 100;
        await app.addMoney(NewTxn(
          kind: e.type,
          amount: amount,
          categoryId: cat.id,
          categoryName: cat.name,
          note: _clip(e.name.text, Limits.note),
          occurredOn: e.date,
          occurredAt: combineDateTime(e.date, _time),
          walletId: wallet,
        ));
        // Mark it saved right away so a retry after an error never adds it twice.
        e.saved = true;
        done++;
        if (e.type == Kind.income) {
          earned += amount;
        } else {
          spent += amount;
        }
      }
      rememberWallet(wallet);
      if (!mounted) return;
      setState(() {
        tally();
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is PostgrestException ? e.message : tr('Couldn\'t save — check your connection.');
      setState(() {
        tally();
        _error = done > 0 ? tr('Added {done} of {n}. {msg} Tap Add again for the rest.', {'done': done, 'n': chosen.length, 'msg': msg}) : msg;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _clip(String s, int max) {
    final t = s.trim();
    return t.length > max ? t.substring(0, max) : t;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final body = switch (_step) {
      _Step.pick => _pickView(p),
      _Step.reading => ScanReading(photo: _photo, text: tr('Reading the memo…')),
      _Step.review => _reviewView(p),
      _Step.notes => _notesView(p),
      _Step.done => _noted != null ? _notesDoneView(p, _noted!) : _doneView(p),
      _Step.error => ScanFailed(photo: _photo, message: _error, onRetry: _reset),
    };
    return ScanSheet(
      label: tr('Memo · notes'),
      title: tr('Scan a memo'),
      tall: _step == _Step.review || _step == _Step.notes,
      body: body,
    );
  }

  Widget _pickView(Palette p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Take a photo of a memo or receipt — or choose a screenshot of your notes (Notepad, any notes app, a chat) with '
            'expenses and income. You check everything before it\'s saved, and categories your note names that you don\'t '
            'have yet are created for you.'),
            style: bodyStyle(p, 14, color: p.muted(0.6), height: 1.5),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: ScanChoice(icon: LucideIcons.camera, label: tr('Take photo'), primary: true, onTap: () => _pick(ImageSource.camera))),
            const SizedBox(width: 12),
            Expanded(
              child: ScanChoice(icon: LucideIcons.imageUp, label: tr('Choose photo or screenshot'), primary: false, onTap: () => _pick(ImageSource.gallery)),
            ),
          ]),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: widget.onManualEntry,
              child: Text(tr('Add an entry by hand instead'), style: bodyStyle(p, 12.5, color: p.muted(0.55))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _doneView(Palette p) {
    final place = _place.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleCheck, size: 40, color: p.income),
          const SizedBox(height: 10),
          Text(trn(_addedCount, 'Added {n} expense', 'Added {n} expenses'), style: displayStyle(p, 24, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${formatCurrency(_addedSum)}${place.isEmpty ? '' : ' · $place'}', style: monoStyle(p, 13, color: p.muted(0.6))),
          const SizedBox(height: 18),
          _doneButtons(p),
        ],
      ),
    );
  }

  Widget _doneButtons(Palette p) => Row(mainAxisSize: MainAxisSize.min, children: [
        HairlineButton(
          height: 44,
          onPressed: _reset,
          child: Text(tr('Scan another'), style: bodyStyle(p, 14, color: p.muted(0.85))),
        ),
        const SizedBox(width: 10),
        PrimaryButton(label: tr('Done'), height: 44, onPressed: () => Navigator.pop(context)),
      ]);

  Widget _notesDoneView(Palette p, ({int count, double spent, double earned, List<Category> created}) n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      child: Column(
        children: [
          Icon(LucideIcons.circleCheck, size: 40, color: p.income),
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(trn(n.count, 'Added {n} entry', 'Added {n} entries'), style: displayStyle(p, 24, weight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              if (n.spent > 0) TextSpan(text: tr('Spent {amount}', {'amount': formatCurrency(n.spent)}), style: TextStyle(color: p.expense)),
              if (n.spent > 0 && n.earned > 0) const TextSpan(text: ' · '),
              if (n.earned > 0) TextSpan(text: tr('Earned {amount}', {'amount': formatCurrency(n.earned)}), style: TextStyle(color: p.income)),
            ]),
            textAlign: TextAlign.center,
            style: monoStyle(p, 13, color: p.muted(0.6)),
          ),
          if (n.created.isNotEmpty) ...[
            const SizedBox(height: 14),
            ScanNotice(
              lead: n.created.length == 1 ? tr('New category created: ') : tr('New categories created: '),
              text: tr('{list}. Rename or recolor them in Settings.', {'list': n.created.map((c) => '${c.name} (${tr(c.kind.name)})').join(', ')}),
            ),
          ],
          const SizedBox(height: 18),
          _doneButtons(p),
        ],
      ),
    );
  }

  Widget _footer(Palette p, {required String label, required VoidCallback? onAdd}) {
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: Row(children: [
        HairlineButton(
          height: 46,
          onPressed: _saving ? null : _reset,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.rotateCcw, size: 16, color: p.muted(0.75)),
            const SizedBox(width: 8),
            Text(tr('Retake'), style: bodyStyle(p, 14, color: p.muted(0.8))),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: PrimaryButton(expand: true, busy: _saving, label: label, onPressed: onAdd)),
      ]),
    );
  }

  Widget _reviewView(Palette p) {
    final m = _memo!;
    final cats = _cats;
    // Amounts after each line's share of the discount (shared out over all lines,
    // so unticking a line doesn't move its share onto the others).
    final amounts = [for (final l in _lines) l.value > 0 ? l.value : 0.0];
    final shares = _discountShares(amounts, m.discount);
    final finals = [for (var i = 0; i < amounts.length; i++) ((amounts[i] - shares[i]) * 100).roundToDouble() / 100];
    final chosen = <(_Line, double)>[
      for (var i = 0; i < _lines.length; i++)
        if (_lines[i].on && !_lines[i].saved && finals[i] > 0) (_lines[i], finals[i]),
    ];
    final sum = (chosen.fold<double>(0, (s, x) => s + x.$2) * 100).roundToDouble() / 100;
    final mismatch = m.total > 0 && _lines.every((l) => l.on) && (sum - m.total).abs() > 1;
    final date = fromDateKey(_dateKey);
    final tParts = _time.split(':');
    final tod = TimeOfDay(hour: int.tryParse(tParts[0]) ?? 12, minute: int.tryParse(tParts.length > 1 ? tParts[1] : '0') ?? 0);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: [
              FieldBlock(
                label: tr('Shop'),
                child: TextField(
                  controller: _place,
                  inputFormatters: maxChars(Limits.place),
                  decoration: InputDecoration(hintText: tr('Shop or place')),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FieldBlock(
                    label: tr('Date'),
                    child: DateButton(
                      value: date,
                      hint: tr('Date'),
                      onPicked: (d) {
                        if (d != null) setState(() => _dateKey = toDateKey(d));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FieldBlock(
                    label: tr('Time'),
                    child: HairlineButton(
                      height: 44,
                      fill: p.inkA(0.02),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: tod);
                        if (picked != null) {
                          setState(() => _time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                        }
                      },
                      child: Text(tod.format(context), style: bodyStyle(p, 13.5)),
                    ),
                  ),
                ),
              ]),
              if (_oddDate.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tr('The memo\'s date read as {oddDate} — using today instead. Change it above if that\'s wrong.', {'oddDate': _oddDate}),
                    style: bodyStyle(p, 12, color: p.accent)),
              ],
              ..._walletField(),
              const SizedBox(height: 20),
              Label(tr('Items · {n}', {'n': _lines.length})),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
                child: Column(children: [
                  for (var i = 0; i < _lines.length; i++) ...[
                    if (i > 0) Divider(color: p.line, height: 1),
                    _lineRow(p, _lines[i], shares[i], cats),
                  ],
                ]),
              ),
              if (m.discount > 0) ...[
                const SizedBox(height: 8),
                Text(tr('Discount {amount} shared across the items.', {'amount': formatCurrency(m.discount)}), style: bodyStyle(p, 12, color: p.muted(0.55))),
              ],
              if (m.currency.isNotEmpty && m.currency != 'BDT') ...[
                const SizedBox(height: 8),
                Text(tr('This memo is in {currency} — amounts are saved as {x1}, as written.', {'currency': m.currency, 'x1': tr(currentCurrency.name)}),
                    style: bodyStyle(p, 12, color: p.accent)),
              ],
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 6,
                children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: tr('Memo total ')),
                    TextSpan(text: m.total > 0 ? formatCurrency(m.total) : '—', style: TextStyle(color: p.ink)),
                  ]), style: monoStyle(p, 13, color: p.muted(0.55))),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: tr('Adding ')),
                    TextSpan(text: formatCurrency(sum), style: TextStyle(color: p.expense)),
                  ]), style: monoStyle(p, 13, color: p.muted(0.55))),
                ],
              ),
              if (mismatch) ...[
                const SizedBox(height: 6),
                Text(tr('That doesn\'t match the memo total — check the amounts.'), style: bodyStyle(p, 12, color: p.expense)),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error, style: bodyStyle(p, 12.5, color: p.expense)),
              ],
            ],
          ),
        ),
        _footer(
          p,
          label: trn(chosen.length, 'Add {n} expense', 'Add {n} expenses'),
          onAdd: chosen.isEmpty ? null : () => _save(chosen, sum),
        ),
      ],
    );
  }

  /// The wallet picker for the review screens (nothing until the database has wallets).
  List<Widget> _walletField() {
    final app = context.watch<AppState>();
    if (!app.walletsReady || app.wallets.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      WalletPicker(value: _wallet(app), onChanged: (id) => setState(() => _walletId = id), label: tr('Wallet')),
    ];
  }

  static const _plainInput = InputDecoration(
    isDense: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    contentPadding: EdgeInsets.symmetric(vertical: 8),
  );

  Widget _lineRow(Palette p, _Line l, double share, List<Category> cats) {
    final enabled = !l.saved;
    return Opacity(
      opacity: l.on && enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
        child: Column(children: [
          Row(children: [
            Checkbox(
              value: l.on,
              activeColor: p.accent,
              onChanged: enabled ? (v) => setState(() => l.on = v ?? false) : null,
            ),
            Expanded(
              child: TextField(
                controller: l.name,
                enabled: enabled,
                inputFormatters: maxChars(Limits.title),
                style: bodyStyle(p, 14),
                decoration: _plainInput,
              ),
            ),
            Text(currencySymbol(), style: monoStyle(p, 14, color: p.muted(0.4))),
            SizedBox(
              width: 84,
              child: TextField(
                controller: l.amount,
                enabled: enabled,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), ...maxChars(12)],
                onChanged: (_) => setState(() {}),
                style: monoStyle(p, 14),
                decoration: _plainInput,
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Row(children: [
              Expanded(
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: AppDropdown(
                    value: l.categoryId,
                    items: [for (final c in cats) c.id],
                    labelOf: (id) => cats.firstWhere((c) => c.id == id).name,
                    onChanged: (id) => setState(() => l.categoryId = id),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 76,
                child: Text(
                  l.saved ? tr('added') : share > 0 ? '−${formatCurrency(share)}' : '',
                  textAlign: TextAlign.right,
                  style: monoStyle(p, 11.5, color: p.muted(0.45)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _notesView(Palette p) {
    final chosen = _chosenEntries;
    final fresh = _freshCats(chosen);
    double total(Kind k) => (chosen.where((e) => e.type == k).fold<double>(0, (s, e) => s + e.value) * 100).roundToDouble() / 100;
    final n = _entries.length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: [
              Text(
                trn(n, "Found {n} entry in your note. Check it — untick it if you don't want it — then add.",
                    "Found {n} entries in your note. Check them — untick anything you don't want — then add."),
                style: bodyStyle(p, 14, color: p.muted(0.6), height: 1.5),
              ),
              if (fresh.isNotEmpty) ...[
                const SizedBox(height: 12),
                ScanNotice(
                  lead: fresh.length == 1 ? tr('New category ') : tr('New categories '),
                  text: tr('from your note will be created: {list}.', {'list': fresh.map((f) => '${f.$2} (${tr(f.$1.name)})').join(', ')}),
                ),
              ],
              ..._walletField(),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
                child: Column(children: [
                  for (var i = 0; i < _entries.length; i++) ...[
                    if (i > 0) Divider(color: p.line, height: 1),
                    _entryRow(p, _entries[i]),
                  ],
                ]),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 6,
                children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: tr('Spending ')),
                    TextSpan(text: formatCurrency(total(Kind.expense)), style: TextStyle(color: p.expense)),
                  ]), style: monoStyle(p, 13, color: p.muted(0.55))),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: tr('Income ')),
                    TextSpan(text: formatCurrency(total(Kind.income)), style: TextStyle(color: p.income)),
                  ]), style: monoStyle(p, 13, color: p.muted(0.55))),
                ],
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error, style: bodyStyle(p, 12.5, color: p.expense)),
              ],
            ],
          ),
        ),
        _footer(
          p,
          label: _saving ? tr('Adding…') : trn(chosen.length, 'Add {n} entry', 'Add {n} entries'),
          onAdd: chosen.isEmpty ? null : _saveNotes,
        ),
      ],
    );
  }

  Widget _entryRow(Palette p, _Entry e) {
    final enabled = !e.saved;
    final income = e.type == Kind.income;
    final existing = _findCat(e.type, e.category);
    // The note's own label comes first while it's new; the user's categories follow.
    final names = [
      if (existing == null && e.category.trim().isNotEmpty) e.category,
      for (final c in _catsOf(e.type)) c.name,
    ];
    return Opacity(
      opacity: e.on && enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 12),
        child: Column(children: [
          Row(children: [
            Checkbox(
              value: e.on,
              activeColor: p.accent,
              onChanged: enabled ? (v) => setState(() => e.on = v ?? false) : null,
            ),
            Expanded(
              child: TextField(
                controller: e.name,
                enabled: enabled,
                inputFormatters: maxChars(Limits.title),
                style: bodyStyle(p, 14),
                decoration: _plainInput,
              ),
            ),
            Text(income ? '+' : '−', style: monoStyle(p, 14, color: income ? p.income : p.expense)),
            const SizedBox(width: 3),
            Text(currencySymbol(), style: monoStyle(p, 14, color: p.muted(0.4))),
            SizedBox(
              width: 84,
              child: TextField(
                controller: e.amount,
                enabled: enabled,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), ...maxChars(12)],
                onChanged: (_) => setState(() {}),
                style: monoStyle(p, 14),
                decoration: _plainInput,
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: IgnorePointer(
              ignoring: !enabled,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  SegTabs<Kind>(
                    options: const [Kind.expense, Kind.income],
                    value: e.type,
                    compact: true,
                    label: (k) => k == Kind.income ? tr('Income') : tr('Expense'),
                    onChanged: (k) => setState(() => e.type = k),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DateButton(
                      value: fromDateKey(e.date),
                      hint: tr('Date'),
                      lastDate: DateTime.now(),
                      onPicked: (d) {
                        if (d != null) setState(() => e.date = toDateKey(d));
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: AppDropdown(
                      value: existing?.name ?? e.category,
                      items: names,
                      labelOf: (name) => existing == null && name == e.category ? tr('New: {name}', {'name': name}) : tr(name),
                      onChanged: (name) => setState(() => e.category = name),
                    ),
                  ),
                  if (e.saved) ...[
                    const SizedBox(width: 10),
                    Text(tr('added'), style: monoStyle(p, 11.5, color: p.muted(0.45))),
                  ],
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

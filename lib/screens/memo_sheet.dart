// Memo scanner — port of the web's MemoScanner: take or choose a photo of a memo
// (receipt), let the web app's /api/scan-memo read it with Gemini, review what it
// found, then add every item as its own expense. The Gemini key stays on the
// server; the request carries the user's Supabase session token instead.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/limits.dart';
import '../widgets/ui.dart';
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

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

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

/// The photo's real type, from its first bytes.
String? _mimeOf(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length > 12 && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') return 'image/webp';
  if (b.length > 12 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') return 'image/heic';
  return null;
}

class _ScanError implements Exception {
  const _ScanError(this.message);
  final String message;
}

enum _Step { pick, reading, review, done, error }

class MemoSheet extends StatefulWidget {
  const MemoSheet({super.key, required this.onManualEntry});

  final VoidCallback onManualEntry;

  @override
  State<MemoSheet> createState() => _MemoSheetState();
}

class _MemoSheetState extends State<MemoSheet> {
  final _picker = ImagePicker();
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
  int _run = 0; // bumps on reset, so a late reply from an abandoned scan is ignored

  @override
  void dispose() {
    _place.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<Category> get _cats => context
      .read<AppState>()
      .categories
      .where((c) => c.kind == Kind.expense && c.name != breakSaving)
      .toList();

  void _reset() {
    for (final l in _lines) {
      l.dispose();
    }
    setState(() {
      _run++;
      _step = _Step.pick;
      _photo = null;
      _memo = null;
      _lines = [];
      _error = '';
    });
  }

  Future<void> _pick(ImageSource source) async {
    XFile? file;
    try {
      // The reader only needs ~1600px; this keeps the upload small.
      file = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    } on PlatformException {
      _fail(source == ImageSource.camera ? 'Couldn\'t open the camera — choose a photo instead.' : 'Couldn\'t open your photos.');
      return;
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
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
    final mime = _mimeOf(bytes);
    if (mime == null) {
      _fail('Couldn\'t open that image — use a JPEG or PNG photo.');
      return;
    }
    final run = ++_run;
    setState(() {
      _step = _Step.reading;
      _photo = bytes;
      _error = '';
    });
    try {
      final auth = Supabase.instance.client.auth;
      var session = auth.currentSession;
      if (session != null && session.isExpired) session = (await auth.refreshSession()).session;
      if (session == null) throw const _ScanError('Log in again to scan memos.');

      final res = await http
          .post(
            Uri.parse('$apiBaseUrl/api/scan-memo'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
            body: jsonEncode({
              'image': base64Encode(bytes),
              'mimeType': mime,
              'categories': [for (final c in _cats) c.name],
              'today': toDateKey(DateTime.now()),
            }),
          )
          .timeout(const Duration(seconds: 75));
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {
        data = null;
      }
      final memo = data?['memo'];
      if (res.statusCode != 200 || memo is! Map<String, dynamic>) {
        throw _ScanError(data?['error'] as String? ?? 'The memo reader couldn\'t process this photo.');
      }
      if (!mounted || run != _run) return;
      _review(_Memo.fromJson(memo));
    } on _ScanError catch (e) {
      if (run == _run) _fail(e.message);
    } on TimeoutException {
      if (run == _run) _fail('The memo reader took too long — try again.');
    } catch (_) {
      if (run == _run) _fail('No connection — try again.');
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
        ));
        // Mark it saved right away so a retry after an error never adds it twice.
        line.saved = true;
        done++;
      }
      if (!mounted) return;
      setState(() {
        _addedCount = done;
        _addedSum = sum;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is PostgrestException ? e.message : 'Couldn\'t save — check your connection.';
      setState(() => _error = done > 0 ? 'Added $done of ${chosen.length}. $msg Tap Add again for the rest.' : msg);
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
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final body = switch (_step) {
      _Step.pick => _pickView(p),
      _Step.reading => _readingView(p),
      _Step.review => _reviewView(p),
      _Step.done => _doneView(p),
      _Step.error => _errorView(p),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: FractionallySizedBox(
        heightFactor: _step == _Step.review ? 0.94 : null,
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: p.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: p.inkA(0.2), borderRadius: BorderRadius.circular(4))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Label('Memo'),
                          const SizedBox(height: 4),
                          Text('Scan a memo', style: displayStyle(p, 30)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, color: p.muted(0.4)),
                    ),
                  ],
                ),
              ),
              Divider(color: p.line, height: 1),
              if (_step == _Step.review) Expanded(child: body) else Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigButton(Palette p, {required IconData icon, required String label, required bool primary, required VoidCallback onTap}) {
    final fg = primary ? p.onAccent : p.muted(0.85);
    return SizedBox(
      height: 104,
      child: Material(
        color: primary ? p.accent : p.inkA(0.02),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: primary ? BorderSide.none : BorderSide(color: p.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: fg),
              const SizedBox(height: 8),
              Text(label, style: bodyStyle(p, 14, weight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickView(Palette p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Take a photo of a memo or receipt, or choose one. Every item becomes its own expense — you check them before anything is saved.',
            style: bodyStyle(p, 14, color: p.muted(0.6), height: 1.5),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _bigButton(p, icon: LucideIcons.camera, label: 'Take photo', primary: true, onTap: () => _pick(ImageSource.camera))),
            const SizedBox(width: 12),
            Expanded(child: _bigButton(p, icon: LucideIcons.imageUp, label: 'Choose photo', primary: false, onTap: () => _pick(ImageSource.gallery))),
          ]),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: widget.onManualEntry,
              child: Text('Add an entry by hand instead', style: bodyStyle(p, 12.5, color: p.muted(0.55))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(Palette p, double maxHeight) => _photo == null
      ? const SizedBox.shrink()
      : ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_photo!, fit: BoxFit.contain),
          ),
        );

  Widget _readingView(Palette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _preview(p, 220),
          const SizedBox(height: 18),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
            const SizedBox(width: 10),
            Text('Reading the memo…', style: bodyStyle(p, 14, color: p.muted(0.75))),
          ]),
          const SizedBox(height: 6),
          Text('Usually a few seconds.', style: bodyStyle(p, 12, color: p.muted(0.5))),
        ],
      ),
    );
  }

  Widget _errorView(Palette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _preview(p, 160),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(_error, textAlign: TextAlign.center, style: bodyStyle(p, 14, color: p.expense)),
          ),
          const SizedBox(height: 16),
          HairlineButton(
            height: 44,
            onPressed: _reset,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.rotateCcw, size: 16, color: p.muted(0.8)),
              const SizedBox(width: 8),
              Text('Try again', style: bodyStyle(p, 14, color: p.muted(0.85))),
            ]),
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
          Text('Added $_addedCount expense${_addedCount == 1 ? '' : 's'}', style: displayStyle(p, 24, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${formatCurrency(_addedSum)}${place.isEmpty ? '' : ' · $place'}', style: monoStyle(p, 13, color: p.muted(0.6))),
          const SizedBox(height: 18),
          Row(mainAxisSize: MainAxisSize.min, children: [
            HairlineButton(
              height: 44,
              onPressed: _reset,
              child: Text('Scan another', style: bodyStyle(p, 14, color: p.muted(0.85))),
            ),
            const SizedBox(width: 10),
            PrimaryButton(label: 'Done', height: 44, onPressed: () => Navigator.pop(context)),
          ]),
        ],
      ),
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
                label: 'Shop',
                child: TextField(
                  controller: _place,
                  inputFormatters: maxChars(Limits.place),
                  decoration: const InputDecoration(hintText: 'Shop or place'),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FieldBlock(
                    label: 'Date',
                    child: DateButton(
                      value: date,
                      hint: 'Date',
                      onPicked: (d) {
                        if (d != null) setState(() => _dateKey = toDateKey(d));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FieldBlock(
                    label: 'Time',
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
                Text('The memo\'s date read as $_oddDate — using today instead. Change it above if that\'s wrong.',
                    style: bodyStyle(p, 12, color: p.accent)),
              ],
              const SizedBox(height: 20),
              Label('Items · ${_lines.length}'),
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
                Text('Discount ${formatCurrency(m.discount)} shared across the items.', style: bodyStyle(p, 12, color: p.muted(0.55))),
              ],
              if (m.currency.isNotEmpty && m.currency != 'BDT') ...[
                const SizedBox(height: 8),
                Text('This memo is in ${m.currency} — amounts are saved as taka.', style: bodyStyle(p, 12, color: p.accent)),
              ],
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 6,
                children: [
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Memo total '),
                    TextSpan(text: m.total > 0 ? formatCurrency(m.total) : '—', style: TextStyle(color: p.ink)),
                  ]), style: monoStyle(p, 13, color: p.muted(0.55))),
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Adding '),
                    TextSpan(text: formatCurrency(sum), style: TextStyle(color: p.expense)),
                  ]), style: monoStyle(p, 13, color: p.muted(0.55))),
                ],
              ),
              if (mismatch) ...[
                const SizedBox(height: 6),
                Text('That doesn\'t match the memo total — check the amounts.', style: bodyStyle(p, 12, color: p.expense)),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error, style: bodyStyle(p, 12.5, color: p.expense)),
              ],
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          child: Row(children: [
            HairlineButton(
              height: 46,
              onPressed: _saving ? null : _reset,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.rotateCcw, size: 16, color: p.muted(0.75)),
                const SizedBox(width: 8),
                Text('Retake', style: bodyStyle(p, 14, color: p.muted(0.8))),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                expand: true,
                busy: _saving,
                label: 'Add ${chosen.length} expense${chosen.length == 1 ? '' : 's'}',
                onPressed: chosen.isEmpty ? null : () => _save(chosen, sum),
              ),
            ),
          ]),
        ),
      ],
    );
  }

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
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            Text('৳', style: monoStyle(p, 14, color: p.muted(0.4))),
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
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
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
                  l.saved ? 'added' : share > 0 ? '−${formatCurrency(share)}' : '',
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
}

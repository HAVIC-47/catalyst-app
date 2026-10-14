// List scanner — port of the web's ListScanner: a screenshot or photo of a list
// (any notes app, Notepad, a chat, a handwritten list) -> the web app's
// /api/scan-list reads it -> every item goes straight onto the to-do or to-buy
// board on screen, with Undo. Ticked or crossed-out items land in the board's
// last column (Done / Bought). Opened by the + in the bottom bar on those pages.
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
import '../util/format.dart';
import '../widgets/scan_ui.dart';
import '../widgets/ui.dart';
import 'boards_screen.dart';

Future<void> openListScanner(BuildContext context, BoardKind kind) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => ListScanSheet(kind: kind),
  );
}

/// One item read from the list (the web's ListItem).
class ListItem {
  const ListItem({required this.title, required this.notes, required this.done, required this.priority, required this.due, required this.price});

  factory ListItem.fromJson(Map<dynamic, dynamic> j) {
    final due = j['due'], price = j['price'];
    return ListItem(
      title: '${j['title'] ?? ''}'.trim(),
      notes: '${j['notes'] ?? ''}'.trim(),
      done: j['done'] == true,
      priority: priorityFrom('${j['priority']}'),
      due: due is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(due) ? due : '',
      price: price is num && price > 0 ? price.toDouble() : 0,
    );
  }

  final String title;
  final String notes;
  final bool done; // ticked or crossed out
  final TicketPriority priority;
  final String due; // yyyy-mm-dd, or ''
  final double price; // to-buy only; 0 when none
}

enum _Step { pick, reading, done, error }

class ListScanSheet extends StatefulWidget {
  const ListScanSheet({super.key, required this.kind});

  final BoardKind kind;

  @override
  State<ListScanSheet> createState() => _ListScanSheetState();
}

class _ListScanSheetState extends State<ListScanSheet> {
  _Step _step = _Step.pick;
  Uint8List? _photo;
  String _error = '';
  ({String board, String? doneColumn, List<Ticket> tickets})? _added;
  bool _undone = false;
  bool _busy = false;
  int _run = 0; // bumps on reset, so a late reply from an abandoned scan is ignored

  BoardCopy get _copy => boardCopy[widget.kind]!;

  void _reset() {
    setState(() {
      _run++;
      _step = _Step.pick;
      _photo = null;
      _added = null;
      _undone = false;
      _error = '';
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _step = _Step.error;
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

  Future<void> _read(Uint8List bytes) async {
    final mime = imageMime(bytes);
    if (mime == null) {
      _fail('Couldn\'t open that image — use a JPEG or PNG screenshot.');
      return;
    }
    final run = ++_run;
    setState(() {
      _step = _Step.reading;
      _photo = bytes;
      _error = '';
    });
    try {
      final data = await Scan.send('/api/scan-list', {
        'image': base64Encode(bytes),
        'mimeType': mime,
        'kind': widget.kind.name,
        'today': toDateKey(DateTime.now()),
      });
      final list = data['list'];
      final items = [
        if (list is Map)
          for (final i in (list['items'] as List? ?? const []).whereType<Map>()) ListItem.fromJson(i),
      ].where((i) => i.title.isNotEmpty).toList();
      if (items.isEmpty) throw const ScanError('Couldn\'t find any items in this screenshot — try a sharper one.');
      if (!mounted || run != _run) return;
      await _addAll(items);
    } on ScanError catch (e) {
      if (run == _run) _fail(e.message);
    } on PostgrestException catch (e) {
      if (run == _run) _fail(boardError(e));
    } catch (_) {
      if (run == _run) _fail('No connection — try again.');
    }
  }

  /// Everything goes in at once, in the list's order: open items at the bottom of
  /// the first column, ticked ones in the last. No board yet? Start one.
  Future<void> _addAll(List<ListItem> items) async {
    final app = context.read<AppState>();
    var board = app.boardOf(widget.kind);
    if (board == null) {
      board = await app.createBoard(_copy.suggested, widget.kind);
      app.selectBoard(widget.kind, board.id);
    }
    final cols = app.columnsOf(board.id);
    if (cols.isEmpty) throw ScanError('Add a column to "${board.name}" first.');
    final first = cols.first.id;
    final last = cols.length > 1 ? cols.last.id : first;
    final tickets = await app.createTickets(board.id, [
      for (final i in items)
        (
          columnId: i.done ? last : first,
          title: i.title,
          description: i.notes,
          priority: i.priority,
          dueOn: i.due.isEmpty ? null : i.due,
          amount: widget.kind == BoardKind.shopping && i.price > 0 ? i.price : null,
        ),
    ]);
    final name = board.name;
    if (!mounted) return;
    setState(() {
      _added = (board: name, doneColumn: cols.length > 1 ? last : null, tickets: tickets);
      _step = _Step.done;
    });
  }

  Future<void> _undo() async {
    final added = _added;
    if (added == null || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await context.read<AppState>().removeTickets([for (final t in added.tickets) t.id]);
      if (mounted) setState(() => _undone = true);
    } catch (e) {
      if (mounted) setState(() => _error = e is PostgrestException ? boardError(e) : 'Couldn\'t undo — check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final body = switch (_step) {
      _Step.pick => _pickView(p),
      _Step.reading => ScanReading(photo: _photo, text: 'Reading the list…'),
      _Step.done => _doneView(p, _added!),
      _Step.error => ScanFailed(photo: _photo, message: _error, onRetry: _reset),
    };
    return ScanSheet(label: _copy.kicker, title: 'Scan a list', body: body);
  }

  Widget _pickView(Palette p) {
    final target = context.watch<AppState>().boardOf(widget.kind);
    final shopping = widget.kind == BoardKind.shopping;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'Upload a screenshot of your ${shopping ? 'shopping list' : 'to-do list'} — from any notes app, Notepad, '
                    'a chat, or a photo of a handwritten list. Every item goes straight onto ',
              ),
              TextSpan(text: target?.name ?? _copy.suggested, style: TextStyle(fontWeight: FontWeight.w600, color: p.ink)),
              TextSpan(text: '${target == null ? ' (a new ${_copy.board})' : ''}; ticked items go in as ${shopping ? 'bought' : 'done'}.'),
            ]),
            style: bodyStyle(p, 14, color: p.muted(0.6), height: 1.5),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: ScanChoice(icon: LucideIcons.imageUp, label: 'Upload screenshot', primary: true, onTap: () => _pick(ImageSource.gallery)),
            ),
            const SizedBox(width: 12),
            Expanded(child: ScanChoice(icon: LucideIcons.camera, label: 'Take photo', primary: false, onTap: () => _pick(ImageSource.camera))),
          ]),
        ],
      ),
    );
  }

  Widget _doneView(Palette p, ({String board, String? doneColumn, List<Ticket> tickets}) added) {
    final n = added.tickets.length;
    final total = added.tickets.fold<double>(0, (s, t) => s + (t.amount ?? 0));
    final shopping = widget.kind == BoardKind.shopping;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(_undone ? LucideIcons.undo2 : LucideIcons.circleCheck, size: 40, color: _undone ? p.muted(0.5) : p.income),
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              _undone ? 'Taken back off the board' : 'Added $n ${ticketNoun(widget.kind, n)}',
              textAlign: TextAlign.center,
              style: displayStyle(p, 24, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: _undone ? 'Nothing was kept on ${added.board}.' : 'to ${added.board}'),
              if (!_undone && total > 0) TextSpan(text: ' · ${formatCurrency(total)}', style: monoStyle(p, 13, color: p.muted(0.6))),
            ]),
            textAlign: TextAlign.center,
            style: bodyStyle(p, 13.5, color: p.muted(0.6)),
          ),
          if (!_undone) ...[
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: n,
                separatorBuilder: (_, _) => Divider(color: p.line, height: 1),
                itemBuilder: (_, i) {
                  final t = added.tickets[i];
                  final done = t.columnId == added.doneColumn;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      PriorityIcon(t.priority),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bodyStyle(p, 14, color: done ? p.muted(0.45) : p.muted(0.85)).copyWith(
                            decoration: done ? TextDecoration.lineThrough : null,
                            decorationColor: p.muted(0.35),
                          ),
                        ),
                      ),
                      if (t.amount != null) ...[
                        const SizedBox(width: 8),
                        Text(formatCurrency(t.amount!), style: monoStyle(p, 12, color: p.muted(0.6))),
                      ],
                      if (done) ...[
                        const SizedBox(width: 8),
                        Label(shopping ? 'bought' : 'done'),
                      ],
                    ]),
                  );
                },
              ),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error, style: bodyStyle(p, 12.5, color: p.expense)),
          ],
          const SizedBox(height: 18),
          // Undo on the left, the way out on the right; wraps on narrow screens.
          Wrap(
            alignment: _undone ? WrapAlignment.end : WrapAlignment.spaceBetween,
            spacing: 10,
            runSpacing: 10,
            children: [
              // In a Row so it keeps its own width (a bare HairlineButton fills the line).
              if (!_undone)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  HairlineButton(
                    height: 44,
                    onPressed: _busy ? null : _undo,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _busy
                          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: p.muted(0.7)))
                          : Icon(LucideIcons.undo2, size: 16, color: p.muted(0.75)),
                      const SizedBox(width: 8),
                      Text('Undo', style: bodyStyle(p, 14, color: p.muted(0.8))),
                    ]),
                  ),
                ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                HairlineButton(
                  height: 44,
                  onPressed: _busy ? null : _reset,
                  child: Text('Scan another', style: bodyStyle(p, 14, color: p.muted(0.85))),
                ),
                const SizedBox(width: 10),
                PrimaryButton(label: 'Done', height: 44, onPressed: () => Navigator.pop(context)),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}

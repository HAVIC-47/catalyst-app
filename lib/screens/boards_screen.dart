// To-do and To buy — port of the web's Jira-style boards (/app/todo,
// /app/shopping): boards with status columns and tickets. Long-press a ticket to
// drag it within or across columns (the board and page scroll when you hold it
// near an edge); tap it to edit. Same tables as the web, so both stay in sync.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/limits.dart';
import '../widgets/ui.dart';

typedef _Copy = ({
  String kicker,
  String title,
  String accent,
  String board,
  String item,
  IconData icon,
  String intro,
  String hint,
  String suggested,
  String placeholder,
});

const Map<BoardKind, _Copy> _copy = {
  BoardKind.todo: (
    kicker: 'To-do',
    title: 'Get it',
    accent: 'done.',
    board: 'board',
    item: 'ticket',
    icon: LucideIcons.listTodo,
    intro: "Make a board for anything you're working on — home, work, a trip. Add tickets, then drag them across as they go from to do to done.",
    hint: 'Board name (e.g. Home, Work)',
    suggested: 'My tasks',
    placeholder: 'What needs doing?',
  ),
  BoardKind.shopping: (
    kicker: 'To buy',
    title: 'Things to',
    accent: 'buy.',
    board: 'list',
    item: 'item',
    icon: LucideIcons.shoppingCart,
    intro: 'Make a list for each shop or occasion. Add what you need with a price, then drag items to In cart and Bought as you shop.',
    hint: 'List name (e.g. Groceries, Eid)',
    suggested: 'Groceries',
    placeholder: 'What do you need?',
  ),
};

String _noun(BoardKind k, [int n = 1]) => '${_copy[k]!.item}${n == 1 ? '' : 's'}';

/// A failed save as a sentence (with a hint when the boards tables are missing).
String _boardError(Object e) {
  final msg = e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
  if (RegExp(r'(board|ticket).*(does not exist|schema cache)', caseSensitive: false).hasMatch(msg)) {
    return "Boards aren't set up yet — run db/supabase.sql in Supabase.";
  }
  return msg;
}

const _gap = 12.0; // between columns

class BoardsScreen extends StatefulWidget {
  const BoardsScreen({super.key, required this.kind});

  final BoardKind kind;

  @override
  State<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends State<BoardsScreen> {
  String? _selected; // board id — the one last opened, per kind (this device)
  final _page = ScrollController();
  final _board = ScrollController();
  final _viewport = GlobalKey();
  final _cardKeys = <String, GlobalKey>{};
  double _extent = 300; // column width + gap, for snapping

  // Drag and drop.
  String? _dragging; // ticket id
  (String, int)? _hover; // (column id, insert-before index)
  String? _draggingColumn; // column id
  int? _columnHover; // insert-before index among the board's columns
  final _colKeys = <String, GlobalKey>{};
  Offset? _pointer; // global pointer position while dragging
  Timer? _autoScroll;

  String get _prefsKey => 'board:${widget.kind.name}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _selected = p.getString(_prefsKey));
    });
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _page.dispose();
    _board.dispose();
    super.dispose();
  }

  void _choose(String id) {
    setState(() => _selected = id);
    SharedPreferences.getInstance().then((p) => p.setString(_prefsKey, id));
    if (_board.hasClients) _board.jumpTo(0);
  }

  // ---------------------------------------------------------------- drag and drop
  void _startDrag(String id) {
    setState(() {
      _dragging = id;
      _hover = null;
    });
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) => _edgeScroll());
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (!mounted) return;
    setState(() {
      _dragging = null;
      _hover = null;
      _pointer = null;
    });
    _snapBoard();
  }

  void _setHover(String columnId, int index) {
    if (_dragging == null || _hover == (columnId, index)) return;
    setState(() => _hover = (columnId, index));
  }

  // A column is picked up by its title (long press) and dropped between columns.
  void _startColumnDrag(String id) {
    setState(() {
      _draggingColumn = id;
      _columnHover = null;
    });
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) => _edgeScroll());
  }

  void _endColumnDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (!mounted) return;
    setState(() {
      _draggingColumn = null;
      _columnHover = null;
      _pointer = null;
    });
    _snapBoard();
  }

  void _setColumnHover(int index) {
    if (_draggingColumn == null || _columnHover == index) return;
    setState(() => _columnHover = index);
  }

  /// Drops column [id] before position [_columnHover] (of the columns as shown).
  Future<void> _dropColumn(String id) async {
    final hover = _columnHover;
    if (hover == null) return;
    final app = context.read<AppState>();
    final col = app.boardColumns.where((c) => c.id == id).firstOrNull;
    if (col == null) return;
    final from = app.columnsOf(col.boardId).indexWhere((c) => c.id == id);
    final to = hover > from ? hover - 1 : hover;
    if (to == from) return; // dropped where it started
    try {
      await app.placeColumn(id, to);
    } catch (_) {
      if (mounted) showError(context, "Couldn't move the column — try again.");
    }
  }

  /// Holding a ticket near an edge scrolls the board sideways and the page up or down.
  void _edgeScroll() {
    final pt = _pointer;
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (pt == null || box == null || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    const edge = 56.0, speed = 16.0;
    double pull(double distance) => distance < edge ? speed * (1 - distance / edge).clamp(0.0, 1.0) : 0;
    void nudge(ScrollController c, double by) {
      if (by == 0 || !c.hasClients) return;
      final pos = c.position;
      c.jumpTo((pos.pixels + by).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    }

    nudge(_board, pull(rect.right - pt.dx) - pull(pt.dx - rect.left));
    nudge(_page, pull(rect.bottom - pt.dy) - pull(pt.dy - rect.top));
    if (_draggingColumn != null) _columnHoverAt(pt);
  }

  /// A finger held still at the edge sends no move events while the board scrolls
  /// under it, so the landing spot for a column is worked out from where it is now.
  void _columnHoverAt(Offset pt) {
    final app = context.read<AppState>();
    final col = app.boardColumns.where((c) => c.id == _draggingColumn).firstOrNull;
    if (col == null) return;
    final cols = app.columnsOf(col.boardId);
    for (final (i, c) in cols.indexed) {
      final box = _colKeys[c.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final left = box.localToGlobal(Offset.zero).dx;
      if (pt.dx < left + box.size.width + _gap / 2) {
        _setColumnHover(pt.dx < left + box.size.width / 2 ? i : i + 1);
        return;
      }
    }
    _setColumnHover(cols.length); // past the last column
  }

  void _snapBoard() {
    if (!_board.hasClients) return;
    final pos = _board.position;
    final target = ((pos.pixels / _extent).round() * _extent).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() > 1) {
      _board.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _drop(String id) async {
    final hover = _hover;
    if (hover == null) return;
    await _moveTo(id, hover.$1, hover.$2);
  }

  /// Puts ticket [id] into [columnId] before position [index] (of that column as shown).
  Future<void> _moveTo(String id, String columnId, int index) async {
    final app = context.read<AppState>();
    final ticket = app.tickets.where((t) => t.id == id).firstOrNull;
    if (ticket == null) return;
    final order = app.ticketsIn(columnId).map((t) => t.id).toList();
    var i = index;
    final old = order.indexOf(id);
    if (old >= 0) {
      order.removeAt(old);
      if (old < i) i--;
    }
    i = i.clamp(0, order.length);
    if (ticket.columnId == columnId && old == i) return; // dropped where it started
    order.insert(i, id);
    try {
      await app.placeTicket(id, columnId, order);
    } catch (_) {
      if (mounted) showError(context, "Couldn't move it — try again.");
    }
  }

  // ---------------------------------------------------------------- board actions
  Future<void> _newBoard() async {
    final copy = _copy[widget.kind]!;
    final name = await _askName(context, title: 'New ${copy.board}', hint: copy.hint, action: 'Create');
    if (name == null || !mounted) return;
    try {
      final b = await context.read<AppState>().createBoard(name, widget.kind);
      _choose(b.id);
    } catch (e) {
      if (mounted) showError(context, _boardError(e));
    }
  }

  Future<void> _boardMenu(String action, Board board) async {
    final app = context.read<AppState>();
    final copy = _copy[widget.kind]!;
    try {
      if (action == 'rename') {
        final name = await _askName(context, title: 'Rename ${copy.board}', initial: board.name, hint: copy.hint);
        if (name != null && name != board.name) await app.renameBoard(board.id, name);
      } else if (action == 'delete') {
        final n = app.tickets.where((t) => t.boardId == board.id).length;
        final what = n > 0 ? ' and its $n ${_noun(widget.kind, n)}' : '';
        if (!await confirm(context, 'Delete "${board.name}"$what?')) return;
        await app.removeBoard(board.id);
      }
    } catch (e) {
      if (mounted) showError(context, _boardError(e));
    }
  }

  Future<void> _columnMenu(String action, BoardColumn c, int ticketCount) async {
    final app = context.read<AppState>();
    try {
      switch (action) {
        case 'rename':
          final name = await _askName(context, title: 'Rename column', initial: c.name, hint: 'Column name');
          if (name != null && name != c.name) await app.renameColumn(c.id, name);
        case 'left':
          await app.moveColumn(c.id, -1);
        case 'right':
          await app.moveColumn(c.id, 1);
        case 'delete':
          final what = ticketCount > 0 ? ' and its $ticketCount ${_noun(widget.kind, ticketCount)}' : '';
          if (!await confirm(context, 'Delete "${c.name}"$what?')) return;
          await app.removeColumn(c.id);
      }
    } catch (e) {
      if (mounted) showError(context, _boardError(e));
    }
  }

  Future<void> _addColumn(String boardId) async {
    final name = await _askName(context, title: 'New column', hint: 'Column name (e.g. Waiting)', action: 'Add');
    if (name == null || !mounted) return;
    try {
      await context.read<AppState>().createColumn(boardId, name);
    } catch (e) {
      if (mounted) showError(context, _boardError(e));
    }
  }

  Future<void> _open(Ticket t) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (_) => _TicketSheet(ticket: t),
      );

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final copy = _copy[widget.kind]!;
    final mine = app.boards.where((b) => b.kind == widget.kind).toList();
    final board = mine.where((b) => b.id == _selected).firstOrNull ?? mine.firstOrNull;
    final colW = math.min(MediaQuery.sizeOf(context).width * 0.84, 320.0);
    _extent = colW + _gap;
    _cardKeys.removeWhere((id, _) => !app.tickets.any((t) => t.id == id));

    const pad = EdgeInsets.symmetric(horizontal: 16);
    return Listener(
      key: _viewport,
      onPointerMove: (e) {
        if (_dragging != null || _draggingColumn != null) _pointer = e.position;
      },
      child: RefreshIndicator(
        onRefresh: app.load,
        child: ListView(
          controller: _page,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          children: [
            Padding(
              padding: pad,
              child: PageHeader(
                kicker: '${copy.kicker} · ${mine.length} ${copy.board}${mine.length == 1 ? '' : 's'}',
                title: copy.title,
                accent: copy.accent,
              ),
            ),
            if (mine.isNotEmpty)
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: pad,
                  children: [
                    for (final b in mine)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OptionChip(label: b.name, selected: b.id == board?.id, round: true, onTap: () => _choose(b.id)),
                      ),
                    OptionChip(label: '+ New ${copy.board}', selected: false, round: true, onTap: _newBoard),
                  ],
                ),
              ),
            if (board == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: app.loading
                    ? Center(child: Text('Loading…', style: monoStyle(p, 12, color: p.muted(0.3))))
                    : _NewBoardCard(kind: widget.kind, onCreated: _choose),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 4, 8),
                child: _BoardTitle(board: board, onMenu: (a) => _boardMenu(a, board)),
              ),
              _columns(app, board, colW),
            ],
          ],
        ),
      ),
    );
  }

  Widget _columns(AppState app, Board board, double colW) {
    final cols = app.columnsOf(board.id);
    return SingleChildScrollView(
      key: ValueKey(_extent), // a new width (rotation) needs a new snap size
      controller: _board,
      scrollDirection: Axis.horizontal,
      physics: _ColumnSnap(_extent),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, c) in cols.indexed)
            Padding(
              padding: const EdgeInsets.only(right: _gap),
              child: _column(app, board, c, i, cols, colW),
            ),
          // Holding a column over "Add column" puts it last.
          DragTarget<_ColumnDrag>(
            onWillAcceptWithDetails: (_) => true,
            onMove: (_) => _setColumnHover(cols.length),
            onAcceptWithDetails: (d) => _dropColumn(d.data.id),
            builder: (context, candidate, rejected) => _AddColumnTile(width: colW, onTap: () => _addColumn(board.id)),
          ),
        ],
      ),
    );
  }

  Widget _column(AppState app, Board board, BoardColumn c, int index, List<BoardColumn> cols, double width) {
    final p = Palette.of(context);
    final items = app.ticketsIn(c.id);
    final done = cols.length > 1 && index == cols.length - 1;
    final total = board.kind == BoardKind.shopping ? items.fold<double>(0, (s, t) => s + (t.amount ?? 0)) : 0.0;
    final target = _dragging != null && _hover?.$1 == c.id;
    final colKey = _colKeys.putIfAbsent(c.id, GlobalKey.new);
    // Where a dragged column would land, shown as a line in the gap — only when it
    // would actually move.
    final moving = _draggingColumn == null ? -1 : cols.indexWhere((x) => x.id == _draggingColumn);
    final slotBefore = moving >= 0 && _columnHover == index && index != moving && index != moving + 1;
    final slotAfter = moving >= 0 && index == cols.length - 1 && _columnHover == cols.length && moving != cols.length - 1;

    // Insertion slots between cards keep a fixed height, so the line showing where
    // a ticket will land never shifts the layout under your finger.
    Widget slot(int i) => SizedBox(
          height: 8,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hover == (c.id, i) ? 1 : 0,
              child: Container(height: 2.5, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(2))),
            ),
          ),
        );

    final ticketTarget = DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      // Only reached when not over a card: above the first card lands at the top,
      // anywhere else at the bottom.
      onMove: (_) {
        final first = items.isEmpty ? null : _cardKeys[items.first.id]?.currentContext?.findRenderObject() as RenderBox?;
        final above = first != null && _pointer != null && _pointer!.dy < first.localToGlobal(Offset.zero).dy;
        _setHover(c.id, above ? 0 : items.length);
      },
      onAcceptWithDetails: (d) => _drop(d.data),
      builder: (context, candidate, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        decoration: BoxDecoration(
          color: p.inkA(0.025),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: target ? p.accentA(0.45) : p.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ColumnHeader(
              column: c,
              count: items.length,
              total: total,
              first: index == 0,
              last: index == cols.length - 1,
              onMenu: (a) => _columnMenu(a, c, items.length),
              // The title is the column's handle: long press, then drag sideways.
              wrapTitle: (title) => LongPressDraggable<_ColumnDrag>(
                data: _ColumnDrag(c.id),
                delay: const Duration(milliseconds: 280),
                feedback: Material(
                  type: MaterialType.transparency,
                  child: Transform.rotate(
                    angle: 0.02,
                    child: _ColumnPreview(column: c, items: items, kind: board.kind, total: total, width: width),
                  ),
                ),
                childWhenDragging: title,
                onDragStarted: () => _startColumnDrag(c.id),
                onDragEnd: (_) => _endColumnDrag(),
                child: Semantics(
                  label: '${c.name} column',
                  hint: 'Long press and drag to move',
                  // Screen readers move columns with actions instead of dragging.
                  customSemanticsActions: {
                    if (index > 0) const CustomSemanticsAction(label: 'Move left'): () => _columnMenu('left', c, items.length),
                    if (index < cols.length - 1)
                      const CustomSemanticsAction(label: 'Move right'): () => _columnMenu('right', c, items.length),
                  },
                  child: ExcludeSemantics(child: title),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, t) in items.indexed) ...[
                    slot(i),
                    _ticketTile(t, i, c, cols, board.kind, done, width),
                  ],
                  slot(items.length),
                  if (items.isEmpty)
                    Container(
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
                      child: Text(
                        _dragging != null ? 'Drop here' : (index == 0 ? 'Add a ${_noun(board.kind)} below' : 'Drag here'),
                        style: bodyStyle(p, 12, color: p.muted(0.35)),
                      ),
                    ),
                ],
              ),
            ),
            _QuickAdd(key: ValueKey('add-${c.id}'), columnId: c.id, kind: board.kind),
          ],
        ),
      ),
    );

    Widget columnSlot({required bool before}) => Positioned(
          top: 0,
          bottom: 0,
          left: before ? -(_gap / 2) - 1.5 : null,
          right: before ? null : -(_gap / 2) - 1.5,
          child: Container(width: 3, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(2))),
        );

    return DragTarget<_ColumnDrag>(
      key: colKey,
      onWillAcceptWithDetails: (_) => true,
      // Left half of a column: land before it; right half: after it.
      onMove: (d) {
        final box = colKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final x = _pointer?.dx ?? d.offset.dx;
        final mid = box.localToGlobal(Offset.zero).dx + box.size.width / 2;
        _setColumnHover(x < mid ? index : index + 1);
      },
      onAcceptWithDetails: (d) => _dropColumn(d.data.id),
      builder: (context, candidate, rejected) => Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(opacity: _draggingColumn == c.id ? 0.35 : 1, child: ticketTarget),
          if (slotBefore) columnSlot(before: true),
          if (slotAfter) columnSlot(before: false),
        ],
      ),
    );
  }

  Widget _ticketTile(Ticket t, int index, BoardColumn c, List<BoardColumn> cols, BoardKind kind, bool done, double width) {
    final key = _cardKeys.putIfAbsent(t.id, GlobalKey.new);
    final card = _TicketCard(ticket: t, kind: kind, done: done);
    return DragTarget<String>(
      key: key,
      onWillAcceptWithDetails: (_) => true,
      onMove: (d) {
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final y = _pointer?.dy ?? d.offset.dy;
        final mid = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
        _setHover(c.id, y < mid ? index : index + 1);
      },
      onAcceptWithDetails: (d) => _drop(d.data),
      builder: (context, candidate, rejected) => LongPressDraggable<String>(
        data: t.id,
        delay: const Duration(milliseconds: 280),
        feedback: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: width - 16,
            child: Transform.rotate(angle: 0.026, child: _TicketCard(ticket: t, kind: kind, done: false, lifted: true)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: card),
        onDragStarted: () => _startDrag(t.id),
        onDragEnd: (_) => _endDrag(),
        child: Semantics(
          button: true,
          label: '${t.title}, number ${t.number}',
          hint: 'Long press and drag to move',
          // Screen readers move tickets with actions instead of dragging.
          customSemanticsActions: {
            for (final other in cols)
              if (other.id != c.id)
                CustomSemanticsAction(label: 'Move to ${other.name}'): () =>
                    _moveTo(t.id, other.id, context.read<AppState>().ticketsIn(other.id).length),
          },
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _open(t),
              child: ExcludeSemantics(child: card),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal paging by column: a swipe settles with a column at the left edge.
class _ColumnSnap extends ScrollPhysics {
  const _ColumnSnap(this.extent, {super.parent});

  final double extent;

  @override
  _ColumnSnap applyTo(ScrollPhysics? ancestor) => _ColumnSnap(extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    var page = position.pixels / extent;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final target = (page.roundToDouble() * extent).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance);
  }

  @override
  bool get allowImplicitScrolling => false;
}

// ---------------------------------------------------------------- pieces

class _BoardTitle extends StatelessWidget {
  const _BoardTitle({required this.board, required this.onMenu});

  final Board board;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final copy = _copy[board.kind]!;
    final cols = app.columnsOf(board.id);
    final doneId = cols.length > 1 ? cols.last.id : null;
    final items = app.tickets.where((t) => t.boardId == board.id).toList();
    final open = items.where((t) => t.columnId != doneId).toList();
    final toGet = open.fold<double>(0, (s, t) => s + (t.amount ?? 0));
    final stats = board.kind == BoardKind.shopping
        ? '${open.length} to get${toGet > 0 ? ' · ${formatCurrency(toGet)}' : ''}'
        : '${open.length} open · ${items.length - open.length} done';
    // Name and stats share one Expanded row, so the name only truncates when it
    // really doesn't fit (a Flexible beside a Spacer would cap it at half).
    return Row(children: [
      Expanded(
        child: Row(children: [
          Flexible(child: Text(board.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: displayStyle(p, 24))),
          const SizedBox(width: 10),
          Text(stats, style: monoStyle(p, 12, color: p.muted(0.45))),
        ]),
      ),
      PopupMenuButton<String>(
        tooltip: '${board.name} options',
        icon: Icon(LucideIcons.ellipsis, size: 18, color: p.muted(0.5)),
        onSelected: onMenu,
        itemBuilder: (_) => [
          _menuItem(context, 'rename', LucideIcons.pencil, 'Rename ${copy.board}'),
          _menuItem(context, 'delete', LucideIcons.trash2, 'Delete ${copy.board}', danger: true),
        ],
      ),
    ]);
  }
}

PopupMenuItem<String> _menuItem(BuildContext context, String value, IconData icon, String label, {bool enabled = true, bool danger = false}) {
  final p = Palette.of(context);
  final color = danger ? p.expense : p.muted(0.8);
  return PopupMenuItem<String>(
    value: value,
    enabled: enabled,
    child: Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: bodyStyle(p, 14, color: color)),
      ]),
    ),
  );
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.column,
    required this.count,
    required this.total,
    required this.first,
    required this.last,
    required this.onMenu,
    this.wrapTitle,
  });

  final BoardColumn column;
  final int count;
  final double total;
  final bool first;
  final bool last;
  final ValueChanged<String> onMenu;
  final Widget Function(Widget title)? wrapTitle; // e.g. the drag handle

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
      child: Row(children: [
        Expanded(
          child: wrapTitle?.call(_title(p)) ?? _title(p),
        ),
        PopupMenuButton<String>(
          tooltip: '${column.name} column options',
          icon: Icon(LucideIcons.ellipsis, size: 18, color: p.muted(0.45)),
          onSelected: onMenu,
          itemBuilder: (_) => [
            _menuItem(context, 'rename', LucideIcons.pencil, 'Rename'),
            _menuItem(context, 'left', LucideIcons.arrowLeft, 'Move left', enabled: !first),
            _menuItem(context, 'right', LucideIcons.arrowRight, 'Move right', enabled: !last),
            _menuItem(context, 'delete', LucideIcons.trash2, 'Delete column', danger: true),
          ],
        ),
      ]),
    );
  }

  // Name, count and total. Opaque to touches across its whole width, so a long
  // press anywhere on the title picks the column up.
  Widget _title(Palette p) => ColoredBox(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Flexible(
              child: Text(
                column.name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(p, 11, weight: FontWeight.w500, color: p.muted(0.7), letterSpacing: 1.8),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: p.inkA(0.06), borderRadius: BorderRadius.circular(99)),
              child: Text('$count', style: monoStyle(p, 10, color: p.muted(0.55))),
            ),
            if (total > 0) ...[
              const SizedBox(width: 8),
              Text(formatCurrency(total), style: monoStyle(p, 11, color: p.muted(0.55))),
            ],
          ]),
        ),
      );
}

/// What a dragged column carries (its own type, so ticket drop zones ignore it).
class _ColumnDrag {
  const _ColumnDrag(this.id);
  final String id;
}

/// The column under your finger while it's being moved: a still copy, lifted.
class _ColumnPreview extends StatelessWidget {
  const _ColumnPreview({required this.column, required this.items, required this.kind, required this.total, required this.width});

  final BoardColumn column;
  final List<Ticket> items;
  final BoardKind kind;
  final double total;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accentA(0.45)),
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 26, offset: Offset(0, 14), spreadRadius: -8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _ColumnHeader(column: column, count: items.length, total: total, first: true, last: true, onMenu: (_) {}),
          ),
          for (final t in items.take(6)) ...[
            _TicketCard(ticket: t, kind: kind, done: false),
            const SizedBox(height: 8),
          ],
          if (items.length > 6) Text('+${items.length - 6} more', style: bodyStyle(p, 12, color: p.muted(0.45))),
        ],
      ),
    );
  }
}

class _PriorityIcon extends StatelessWidget {
  const _PriorityIcon(this.priority);

  final TicketPriority priority;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (icon, color) = switch (priority) {
      TicketPriority.high => (LucideIcons.chevronsUp, p.expense),
      TicketPriority.medium => (LucideIcons.equal, const Color(0xFFB59A3C)),
      TicketPriority.low => (LucideIcons.chevronsDown, p.saving),
    };
    return Icon(icon, size: 14, color: color, semanticLabel: '${priority.name} priority');
  }
}

/// A ticket as it sits on the board (also the floating copy while dragging).
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.kind, required this.done, this.lifted = false});

  final Ticket ticket;
  final BoardKind kind;
  final bool done; // in the board's last column
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final due = ticket.dueOn;
    final overdue = !done && due != null && due.compareTo(toDateKey(DateTime.now())) < 0;
    final meta = monoStyle(p, 11, color: p.muted(0.45));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: lifted ? p.accentA(0.45) : p.line),
        boxShadow: lifted
            ? const [BoxShadow(color: Color(0x59000000), blurRadius: 26, offset: Offset(0, 14), spreadRadius: -8)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ticket.title,
            style: bodyStyle(p, 14, color: done ? p.muted(0.5) : p.muted(0.9), height: 1.3).copyWith(
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: p.muted(0.35),
            ),
          ),
          const SizedBox(height: 7),
          Row(children: [
            _PriorityIcon(ticket.priority),
            const SizedBox(width: 8),
            Text('#${ticket.number}', style: meta),
            if (due != null) ...[
              const SizedBox(width: 10),
              Icon(LucideIcons.calendarClock, size: 12, color: overdue ? p.expense : p.muted(0.45)),
              const SizedBox(width: 3),
              Text(fmt(fromDateKey(due), 'MMM d'), style: overdue ? meta.copyWith(color: p.expense) : meta),
            ],
            if (ticket.description.isNotEmpty) ...[
              const SizedBox(width: 10),
              Icon(LucideIcons.alignLeft, size: 12, color: p.muted(0.45)),
            ],
            const Spacer(),
            if (kind == BoardKind.shopping && ticket.amount != null)
              Text(formatCurrency(ticket.amount!), style: monoStyle(p, 12, color: p.muted(0.75))),
          ]),
        ],
      ),
    );
  }
}

/// "+ Add ticket" at the foot of a column; stays open for quick runs of entries.
class _QuickAdd extends StatefulWidget {
  const _QuickAdd({super.key, required this.columnId, required this.kind});

  final String columnId;
  final BoardKind kind;

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text.trim().isEmpty && !_busy && mounted) setState(() => _open = false);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _text.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().createTicket(widget.columnId, title);
      _text.clear();
      _focus.requestFocus(); // ready for the next one
    } catch (e) {
      if (mounted) showError(context, _boardError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (!_open) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _open = true);
              WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
            },
            icon: Icon(LucideIcons.plus, size: 16, color: p.muted(0.45)),
            label: Text('Add ${_noun(widget.kind)}', style: bodyStyle(p, 13.5, color: p.muted(0.45))),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            inputFormatters: maxChars(Limits.title),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(hintText: _copy[widget.kind]!.placeholder),
          ),
          const SizedBox(height: 8),
          Row(children: [
            PrimaryButton(label: 'Add', height: 38, busy: _busy, onPressed: _text.text.trim().isEmpty ? null : _submit),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () {
                _text.clear();
                _focus.unfocus();
                setState(() => _open = false);
              },
              child: Text('Cancel', style: bodyStyle(p, 13, color: p.muted(0.55))),
            ),
          ]),
        ],
      ),
    );
  }
}

class _AddColumnTile extends StatelessWidget {
  const _AddColumnTile({required this.width, required this.onTap});

  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: width,
      child: HairlineButton(
        height: 48,
        onPressed: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.plus, size: 16, color: p.muted(0.45)),
          const SizedBox(width: 8),
          Text('Add column', style: bodyStyle(p, 13.5, color: p.muted(0.45))),
        ]),
      ),
    );
  }
}

/// First board of a kind: a short intro and a name to start with.
class _NewBoardCard extends StatefulWidget {
  const _NewBoardCard({required this.kind, required this.onCreated});

  final BoardKind kind;
  final ValueChanged<String> onCreated;

  @override
  State<_NewBoardCard> createState() => _NewBoardCardState();
}

class _NewBoardCardState extends State<_NewBoardCard> {
  late final _name = TextEditingController(text: _copy[widget.kind]!.suggested);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final n = _name.text.trim();
    if (n.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final b = await context.read<AppState>().createBoard(n, widget.kind);
      widget.onCreated(b.id);
    } catch (e) {
      if (mounted) showError(context, _boardError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final copy = _copy[widget.kind]!;
    return CardBox(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line), color: p.inkA(0.02)),
              child: Icon(copy.icon, size: 20, color: p.accent),
            ),
          ),
          const SizedBox(height: 14),
          Text('Start your first ${copy.board}', style: displayStyle(p, 24)),
          const SizedBox(height: 6),
          Text(copy.intro, style: bodyStyle(p, 13.5, color: p.muted(0.5), height: 1.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            inputFormatters: maxChars(Limits.name),
            onSubmitted: (_) => _create(),
            decoration: InputDecoration(hintText: copy.hint),
          ),
          const SizedBox(height: 10),
          PrimaryButton(expand: true, icon: LucideIcons.plus, label: 'Create', busy: _busy, onPressed: _name.text.trim().isEmpty ? null : _create),
          const SizedBox(height: 8),
          Text(
            'Starts with ${defaultBoardColumns[widget.kind]!.join(' · ')} — rename them or add more any time.',
            style: bodyStyle(p, 12, color: p.muted(0.4)),
          ),
        ],
      ),
    );
  }
}

/// A one-field dialog for names (boards, columns). Null when cancelled or empty.
Future<String?> _askName(BuildContext context, {required String title, String initial = '', String hint = '', String action = 'Save'}) async {
  final p = Palette.of(context);
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: displayStyle(p, 22)),
      content: TextField(
        controller: controller,
        autofocus: true,
        inputFormatters: maxChars(Limits.name),
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel', style: TextStyle(color: p.muted(0.6)))),
        TextButton(onPressed: () => Navigator.pop(c, controller.text), child: Text(action, style: TextStyle(color: p.accent))),
      ],
    ),
  );
  controller.dispose();
  final name = result?.trim() ?? '';
  return name.isEmpty ? null : name;
}

// ---------------------------------------------------------------- ticket editor

/// Edit a ticket: title, status (its column), priority, due date, price (to-buy
/// boards) and notes. A new status puts it at the bottom of that column.
class _TicketSheet extends StatefulWidget {
  const _TicketSheet({required this.ticket});

  final Ticket ticket;

  @override
  State<_TicketSheet> createState() => _TicketSheetState();
}

class _TicketSheetState extends State<_TicketSheet> {
  late final _title = TextEditingController(text: widget.ticket.title);
  late final _notes = TextEditingController(text: widget.ticket.description);
  late final _price = TextEditingController(text: widget.ticket.amount == null ? '' : groupNumber(widget.ticket.amount!));
  late TicketPriority _priority = widget.ticket.priority;
  late DateTime? _due = widget.ticket.dueOn == null ? null : fromDateKey(widget.ticket.dueOn!);
  late String _columnId = widget.ticket.columnId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _price.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save(BoardKind kind) async {
    final app = context.read<AppState>();
    final t = widget.ticket;
    final price = _price.text.trim().isEmpty ? null : parseAmount(_price.text);
    setState(() => _busy = true);
    try {
      await app.saveTicket(t.edited(
        title: _title.text.trim(),
        description: _notes.text.trim(),
        priority: _priority,
        dueOn: _due == null ? null : toDateKey(_due!),
        amount: kind == BoardKind.shopping ? price : t.amount,
      ));
      if (_columnId != t.columnId) {
        final order = app.ticketsIn(_columnId).map((x) => x.id).toList()..add(t.id);
        await app.placeTicket(t.id, _columnId, order);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showError(context, _boardError(e));
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete(BoardKind kind) async {
    if (!await confirm(context, 'Delete this ${_noun(kind)}?')) return;
    if (!mounted) return;
    try {
      await context.read<AppState>().removeTicket(widget.ticket.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, _boardError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final t = widget.ticket;
    final board = app.boards.where((b) => b.id == t.boardId).firstOrNull;
    final kind = board?.kind ?? BoardKind.todo;
    final cols = app.columnsOf(t.boardId);
    final priceOk = _price.text.trim().isEmpty || parseAmount(_price.text) != null;
    final valid = _title.text.trim().isNotEmpty && priceOk;

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
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: p.inkA(0.2), borderRadius: BorderRadius.circular(4))),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label('#${t.number} · ${board?.name ?? ''}'),
                  const SizedBox(height: 4),
                  Text('Edit ${_noun(kind)}', style: displayStyle(p, 26)),
                ]),
              ),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.45))),
            ]),
            const SizedBox(height: 14),
            FieldBlock(
              label: 'Title',
              child: TextField(controller: _title, minLines: 1, maxLines: 3, inputFormatters: maxChars(Limits.title)),
            ),
            const SizedBox(height: 14),
            FieldBlock(
              label: 'Status',
              child: AppDropdown(
                value: _columnId,
                items: [for (final c in cols) c.id],
                labelOf: (id) => cols.where((c) => c.id == id).firstOrNull?.name ?? '',
                onChanged: (v) => setState(() => _columnId = v),
              ),
            ),
            const SizedBox(height: 14),
            FieldBlock(
              label: 'Priority',
              child: SegTabs<TicketPriority>(
                options: TicketPriority.values,
                value: _priority,
                expand: true,
                label: (v) => '${v.name[0].toUpperCase()}${v.name.substring(1)}',
                onChanged: (v) => setState(() => _priority = v),
              ),
            ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: FieldBlock(
                  label: 'Due date',
                  child: Row(children: [
                    Expanded(child: DateButton(value: _due, hint: 'None', onPicked: (d) => setState(() => _due = d))),
                    if (_due != null)
                      IconButton(
                        tooltip: 'Clear due date',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _due = null),
                        icon: Icon(LucideIcons.x, size: 16, color: p.muted(0.45)),
                      ),
                  ]),
                ),
              ),
              if (kind == BoardKind.shopping) ...[
                const SizedBox(width: 10),
                Expanded(child: FieldBlock(label: 'Price', child: AmountField(controller: _price, hint: 'Optional'))),
              ],
            ]),
            const SizedBox(height: 14),
            FieldBlock(
              label: 'Notes',
              child: TextField(
                controller: _notes,
                minLines: 3,
                maxLines: 6,
                inputFormatters: maxChars(Limits.description),
                decoration: InputDecoration(
                  hintText: kind == BoardKind.shopping ? 'Brand, size, where to get it…' : 'Details, links, next steps…',
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              HairlineIconButton(icon: LucideIcons.trash2, tooltip: 'Delete this ${_noun(kind)}', size: 46, onPressed: () => _delete(kind)),
              const SizedBox(width: 10),
              Expanded(child: PrimaryButton(expand: true, label: 'Save', busy: _busy, onPressed: valid ? () => _save(kind) : null)),
            ]),
          ],
        ),
      ),
    );
  }
}

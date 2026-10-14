// The store without Supabase, for widget tests: data is set directly, and writes
// are applied locally (what the real AppState does around its network calls).
import 'dart:convert';

import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/theme/app_theme.dart';
import 'package:catalyst/theme/palette.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FakeApp extends AppState {
  final moves = <(String, String, List<String>)>[];
  var _id = 0;

  String _next(String prefix) => '$prefix${++_id}';

  /// Something new was logged: AppState swaps in a new list, like a real add.
  void logSomething() {
    transactions = [...transactions];
    notifyListeners();
  }

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> load() async {}

  @override
  Future<void> placeTicket(String id, String columnId, List<String> order) async {
    moves.add((id, columnId, order));
    tickets = [
      for (final t in tickets)
        order.contains(t.id) ? t.moved(t.id == id ? columnId : t.columnId, (order.indexOf(t.id) + 1) * sortStep) : t,
    ];
    notifyListeners();
  }

  @override
  Future<Board> createBoard(String name, BoardKind kind) async {
    final b = Board(id: _next('b'), name: name, kind: kind, sort: boards.length);
    boards = [...boards, b];
    boardColumns = [
      ...boardColumns,
      for (final (i, n) in defaultBoardColumns[kind]!.indexed) BoardColumn(id: _next('col'), boardId: b.id, name: n, sort: i),
    ];
    notifyListeners();
    return b;
  }

  @override
  Future<List<Ticket>> createTickets(String boardId, List<NewTicket> drafts) async {
    final made = [for (final r in newTicketRows(boardId, drafts, tickets)) Ticket.fromRow({...r, 'id': _next('n')})];
    tickets = [...tickets, ...made];
    notifyListeners();
    return made;
  }

  @override
  Future<void> removeTickets(List<String> ids) async {
    tickets = tickets.where((t) => !ids.contains(t.id)).toList();
    notifyListeners();
  }

  @override
  Future<Category> createCategory({required String name, required Kind kind, required String color, required int sort}) async {
    final c = Category(id: _next('cat'), name: name, kind: kind, color: color, sort: sort);
    categories = [...categories, c];
    notifyListeners();
    return c;
  }

  @override
  Future<void> addMoney(NewTxn t) async {
    transactions = [Txn.fromRow({...t.toRow(), 'id': _next('tx'), 'created_at': ''}), ...transactions];
    notifyListeners();
  }

  /// What the database sends back for an update: the new values, same id and created_at.
  @override
  Future<void> editMoney(String id, NewTxn t) async {
    final old = transactions.firstWhere((x) => x.id == id);
    final updated = Txn.fromRow({...t.toRow(), 'id': id, 'created_at': old.createdAt});
    transactions = [for (final x in transactions) x.id == id ? updated : x]..sort(newestFirst);
    notifyListeners();
  }

  @override
  Future<void> removeMoney(String id) async {
    transactions = transactions.where((t) => t.id != id).toList();
    notifyListeners();
  }
}

Ticket ticket(String id, String column, int number, String title, double sort, {TicketPriority priority = TicketPriority.medium}) =>
    Ticket(id: id, boardId: 'b1', columnId: column, number: number, title: title, description: '', priority: priority, dueOn: null, amount: null, sort: sort);

/// One to-do board, "Home", with three columns and four tickets.
FakeApp seeded() => FakeApp()
  ..loading = false
  ..boards = [const Board(id: 'b1', name: 'Home', kind: BoardKind.todo, sort: 0)]
  ..boardColumns = [
    const BoardColumn(id: 'c1', boardId: 'b1', name: 'To do', sort: 0),
    const BoardColumn(id: 'c2', boardId: 'b1', name: 'In progress', sort: 1),
    const BoardColumn(id: 'c3', boardId: 'b1', name: 'Done', sort: 2),
  ]
  ..tickets = [
    ticket('t1', 'c1', 1, 'Fix the kitchen tap', 1024, priority: TicketPriority.high),
    ticket('t2', 'c1', 2, 'Call the landlord', 2048),
    ticket('t4', 'c2', 4, 'Paint the balcony', 1024),
    ticket('t5', 'c3', 5, 'Pay internet bill', 1024),
  ];

Widget host(AppState app, Widget child) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Palette.night), home: Scaffold(body: child)),
    );

/// A 1×1 PNG — enough for the scanners, whose readers are faked.
final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

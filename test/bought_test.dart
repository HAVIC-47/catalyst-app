// A to-buy item marked as bought joins that day's expenses — at its price, or with
// none yet and a nudge to add it — and moving it back asks before taking that off.
// The real store on the fake database, so these are the rules the app runs.
import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/boards_screen.dart';
import 'package:catalyst/screens/calendar_screen.dart';
import 'package:catalyst/screens/dashboard_screen.dart';
import 'package:catalyst/screens/entry_sheet.dart';
import 'package:catalyst/screens/ledger_screen.dart';
import 'package:catalyst/screens/price_sheet.dart';
import 'package:catalyst/services/notifications.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/money.dart';
import 'package:catalyst/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';
import 'fake_money_db.dart';

const _cash = Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 0, sort: 0, archived: false);

Category _cat(String id, String name) => Category(id: id, name: name, kind: Kind.expense, color: '#2E8159', sort: 0);

Ticket _item(String id, String column, String title, double? amount, {String board = 'list'}) =>
    Ticket(id: id, boardId: board, columnId: column, number: 1, title: title, description: '', priority: TicketPriority.medium, dueOn: null, amount: amount, sort: 1024);

/// The Groceries list (To buy · In cart · Bought) and a to-do board, on the fake database.
AppState _store() => AppState()
  ..db = FakeMoneyDb()
  ..loading = false
  ..walletsReady = true
  ..wallets = [_cash]
  ..categories = [_cat('g', 'Groceries'), _cat('s', 'Shopping'), _cat('o', 'Other')]
  ..boards = [
    const Board(id: 'list', name: 'Groceries', kind: BoardKind.shopping, sort: 0),
    const Board(id: 'home', name: 'Home', kind: BoardKind.todo, sort: 1),
  ]
  ..boardColumns = [
    const BoardColumn(id: 'buy', boardId: 'list', name: 'To buy', sort: 0),
    const BoardColumn(id: 'cart', boardId: 'list', name: 'In cart', sort: 1),
    const BoardColumn(id: 'bought', boardId: 'list', name: 'Bought', sort: 2),
    const BoardColumn(id: 'todo', boardId: 'home', name: 'To do', sort: 0),
    const BoardColumn(id: 'done', boardId: 'home', name: 'Done', sort: 1),
  ]
  ..tickets = [
    _item('milk', 'buy', 'Milk', 120),
    _item('eggs', 'buy', 'Eggs', null),
    _item('tap', 'todo', 'Fix the tap', 300, board: 'home'),
  ];

FakeMoneyDb _db(AppState app) => app.db as FakeMoneyDb;

/// What the store said while [run] ran.
Future<({List<String> notices, List<AppAlert> alerts})> _said(AppState app, Future<void> Function() run) async {
  final notices = <String>[];
  final alerts = <AppAlert>[];
  final a = app.notices.stream.listen(notices.add);
  final b = app.alerts.stream.listen(alerts.add);
  await run();
  await Future<void>.delayed(Duration.zero);
  await a.cancel();
  await b.cancel();
  return (notices: notices, alerts: alerts);
}

Future<void> _buy(AppState app, String id) => app.placeTicket(id, 'bought', [...app.ticketsIn('bought').map((t) => t.id), id]);

/// A button that moves [id] the way the board does (asking when it has to).
Widget _mover(AppState app, String id, String column) => host(
      app,
      Builder(builder: (c) => TextButton(onPressed: () => placeAsking(c, id, column, [id]), child: const Text('move'))),
    );

String _columnOf(AppState app, String id) => app.tickets.firstWhere((t) => t.id == id).columnId;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('what a bought item is logged as', () {
    test('its category: named like its list, else Shopping, else Other', () {
      final cats = [_cat('g', 'Groceries'), _cat('s', 'Shopping'), _cat('o', 'Other')];
      expect(boughtCategory('Groceries', cats)?.id, 'g');
      expect(boughtCategory('  groceries ', cats)?.id, 'g');
      expect(boughtCategory('Eid', cats)?.id, 's');
      expect(boughtCategory('Eid', [cats[0], cats[2]])?.id, 'o');
      expect(boughtCategory('Eid', [cats[0]])?.id, 'g');
      expect(boughtCategory('Eid', const []), isNull);
    });

    test('only an expense with no amount needs a price', () {
      Txn txn(Kind k, double a) => Txn.fromRow({'id': 'x', 'kind': k.name, 'amount': a, 'occurred_on': '2026-11-05', 'occurred_at': '2026-11-05T08:00:00Z'});
      expect(needsPrice(txn(Kind.expense, 0)), isTrue);
      expect(needsPrice(txn(Kind.expense, 5)), isFalse);
      expect(needsPrice(txn(Kind.income, 0)), isFalse);
      expect(needsPrice(txn(Kind.saving, 0)), isFalse);
    });

    test('Bought is a to-buy list\'s last column, whatever it\'s called', () {
      final app = _store();
      expect(app.boughtColumn('list'), 'bought');
      expect(app.boughtColumn('home'), isNull); // a to-do board
      expect(app.boughtColumn('nope'), isNull);
      app.boardColumns = [
        const BoardColumn(id: 'a', boardId: 'list', name: 'Later', sort: 5),
        const BoardColumn(id: 'b', boardId: 'list', name: 'Got it', sort: 9),
      ];
      expect(app.boughtColumn('list'), 'b');
      app.boardColumns = [const BoardColumn(id: 'a', boardId: 'list', name: 'Only', sort: 0)];
      expect(app.boughtColumn('list'), isNull); // one column: nothing is "done" there, same as the strike-through
    });

    test('an entry read from the database knows its item, and copies keep it', () {
      final t = Txn.fromRow({'id': 'x', 'kind': 'expense', 'amount': 0, 'occurred_on': '2026-11-05', 'occurred_at': '2026-11-05T08:00:00Z', 'ticket_id': 'milk'});
      expect(t.ticketId, 'milk');
      expect(t.withWallet('w').ticketId, 'milk');
      expect(t.unlinked().ticketId, 'milk');
      expect(t.withoutTicket().ticketId, isNull);
    });
  });

  group('into Bought', () {
    test('an item with a price joins today\'s expenses at that price, and says so', () async {
      final app = _store();
      final said = await _said(app, () => _buy(app, 'milk'));
      final t = app.transactions.single;
      expect((t.kind, t.amount, t.note, t.ticketId, t.occurredOn), (Kind.expense, 120.0, 'Milk', 'milk', toDateKey(DateTime.now())));
      expect((t.categoryId, t.categoryName, t.walletId), ('g', 'Groceries', 'cash'));
      expect(said.notices, ["Milk added to today's expenses — ৳120."]);
      expect(said.alerts, isEmpty);
      expect(app.needPrice, isEmpty);
    });

    test('an item with no price is logged anyway, and a notification asks for one', () async {
      final app = _store();
      final said = await _said(app, () => _buy(app, 'eggs'));
      expect(app.transactions.single.amount, 0);
      expect(app.needPrice.map((t) => t.note), ['Eggs']);
      expect(said.notices, isEmpty);
      expect(said.alerts.single.title, 'Add a price');
      expect(said.alerts.single.body, "Eggs added to today's expenses with no price yet.");
      expect(said.alerts.single.target, NoticeTarget.prices);
    });

    test('with that kind of notification off it still says what happened, quietly', () async {
      final app = _store()..reminders = const ReminderPrefs(prices: false);
      final said = await _said(app, () => _buy(app, 'eggs'));
      expect(said.alerts, isEmpty);
      expect(said.notices, ["Eggs added to today's expenses with no price yet."]);
    });

    test('a price of zero counts as no price', () async {
      final app = _store()..tickets = [_item('milk', 'buy', 'Milk', 0)];
      final said = await _said(app, () => _buy(app, 'milk'));
      expect(app.needPrice, hasLength(1));
      expect(said.alerts, hasLength(1));
    });

    test('moving along the list, or within Bought, logs nothing', () async {
      final app = _store();
      await app.placeTicket('milk', 'cart', ['milk']);
      expect(app.transactions, isEmpty);
      await _buy(app, 'milk');
      expect(app.transactions, hasLength(1));
      await app.placeTicket('milk', 'bought', ['milk']); // reordered inside Bought
      expect(app.transactions, hasLength(1));
      expect(_db(app).calls.where((c) => c.startsWith('logBought')), hasLength(1));
    });

    test('a to-do board\'s last column isn\'t Bought', () async {
      final app = _store();
      await app.placeTicket('tap', 'done', ['tap']);
      expect(app.transactions, isEmpty);
    });

    test('an item already in the ledger isn\'t logged twice', () async {
      final app = _store();
      await _buy(app, 'milk');
      await app.placeTicket('milk', 'buy', ['milk']); // (asking is the screen's part)
      await _buy(app, 'milk');
      expect(app.transactions, hasLength(1));
    });

    test('another device got there first: nothing is added here, and nothing is said', () async {
      final app = _store();
      _db(app).boughtFails = 'duplicate';
      final said = await _said(app, () => _buy(app, 'milk'));
      expect(_db(app).calls, contains('logBought milk (already there)'));
      expect(app.transactions, isEmpty); // the reload has no server to reach in this test
      expect(said.notices, isEmpty);
      expect(said.alerts, isEmpty);
    });

    test('before the database update Bought stays a plain column, without a word', () async {
      final app = _store();
      _db(app).boughtFails = Exception("Could not find the 'ticket_id' column of 'transactions' in the schema cache");
      final said = await _said(app, () => _buy(app, 'milk'));
      expect(_columnOf(app, 'milk'), 'bought');
      expect(app.transactions, isEmpty);
      expect(said.notices, isEmpty);
    });

    test('anything else going wrong says the item is bought but not logged', () async {
      final app = _store();
      _db(app).boughtFails = Exception('boom');
      final said = await _said(app, () => _buy(app, 'milk'));
      expect(_columnOf(app, 'milk'), 'bought');
      expect(said.notices, ["Milk is marked as bought, but couldn't be added to your expenses."]);
    });

    test('a move that fails logs nothing', () async {
      final app = _store();
      _db(app).ticketFails = Exception('no');
      await expectLater(_buy(app, 'milk'), throwsException);
      expect(app.transactions, isEmpty);
      expect(_db(app).calls.where((c) => c.startsWith('logBought')), isEmpty);
    });

    test('an item added straight to Bought is bought; one added elsewhere isn\'t', () async {
      final app = _store();
      await app.createTicket('buy', 'Salt');
      expect(app.transactions, isEmpty);
      await app.createTicket('bought', 'Sugar');
      expect(app.transactions.single.note, 'Sugar');
      expect(app.needPrice, hasLength(1));
    });

    test('a scanned batch doesn\'t log anything, ticked or not (its date and price are unknown)', () async {
      final app = _store();
      await app.createTickets('list', [
        (columnId: 'bought', title: 'Soap', description: '', priority: TicketPriority.medium, dueOn: null, amount: 80),
        (columnId: 'buy', title: 'Oil', description: '', priority: TicketPriority.medium, dueOn: null, amount: null),
      ]);
      expect(app.ticketsIn('bought').map((t) => t.title), ['Soap']);
      expect(app.transactions, isEmpty);
      expect(_db(app).calls.where((c) => c.startsWith('logBought')), isEmpty);
    });

    test('a budget hears about it like any other expense', () async {
      final app = _store()
        ..budgets = [const Budget(id: 'b', categoryId: 'g', categoryName: 'Groceries', amount: 100, period: 'monthly')];
      final said = await _said(app, () async {
        await _buy(app, 'milk');
        await Future<void>.delayed(const Duration(milliseconds: 20)); // reads the prefs first
      });
      expect(said.notices.any((n) => n.contains('Groceries budget is used up')), isTrue, reason: '${said.notices}');
    });
  });

  group('prices stay in step', () {
    test('a price added later reaches the expense and the item', () async {
      final app = _store();
      await _buy(app, 'eggs');
      final id = app.transactions.single.id;
      await app.setPrices([(id, 150.5)]);
      expect(app.transactions.single.amount, 150.5);
      expect(app.tickets.firstWhere((t) => t.id == 'eggs').amount, 150.5);
      expect(app.needPrice, isEmpty);
      expect(app.transactions.single.ticketId, 'eggs'); // still linked
      expect(_db(app).calls, containsAll(['updateTransaction $id 150.5 Eggs', 'updateTicket eggs {amount: 150.5}']));
    });

    test('a new amount in the ledger reaches the item', () async {
      final app = _store();
      await _buy(app, 'milk');
      final t = app.transactions.single;
      await app.editMoney(t.id, t.edited(amount: 130));
      expect(app.tickets.firstWhere((x) => x.id == 'milk').amount, 130);
    });

    test('changing only the note in the ledger leaves the item alone', () async {
      final app = _store();
      await _buy(app, 'milk');
      final t = app.transactions.single;
      await app.editMoney(t.id, t.edited(note: 'Milk from Agora'));
      expect(_db(app).calls.where((c) => c.startsWith('updateTicket milk {amount')), isEmpty);
      expect(app.tickets.firstWhere((x) => x.id == 'milk').amount, 120);
    });

    test('a new price on the item reaches its expense; no price takes it back to asking', () async {
      final app = _store();
      await _buy(app, 'milk');
      Ticket milk() => app.tickets.firstWhere((t) => t.id == 'milk');
      await app.saveTicket(milk().edited(title: 'Milk', description: '', priority: TicketPriority.medium, dueOn: null, amount: 140));
      expect(app.transactions.single.amount, 140);
      await app.saveTicket(milk().edited(title: 'Milk', description: '', priority: TicketPriority.medium, dueOn: null, amount: null));
      expect(app.transactions.single.amount, 0);
      expect(app.needPrice, hasLength(1));
    });

    test('a new title reaches the note only while the note still says the old one', () async {
      final app = _store();
      await _buy(app, 'milk');
      Ticket milk() => app.tickets.firstWhere((t) => t.id == 'milk');
      Ticket retitled(String title) => milk().edited(title: title, description: '', priority: TicketPriority.medium, dueOn: null, amount: 120);
      await app.saveTicket(retitled('Milk 2L'));
      expect(app.transactions.single.note, 'Milk 2L');
      final t = app.transactions.single;
      await app.editMoney(t.id, t.edited(note: 'For the party'));
      await app.saveTicket(retitled('Milk 1L'));
      expect(app.transactions.single.note, 'For the party');
    });

    test('an item with no expense just saves', () async {
      final app = _store();
      final milk = app.tickets.first;
      await app.saveTicket(milk.edited(title: 'Milk', description: '', priority: TicketPriority.medium, dueOn: null, amount: 99));
      expect(app.transactions, isEmpty);
      expect(_db(app).calls.where((c) => c.startsWith('updateTransaction')), isEmpty);
    });
  });

  group('moving back asks first', () {
    Future<AppState> bought(WidgetTester tester) async {
      final app = _store();
      await tester.runAsync(() => _buy(app, 'milk'));
      await tester.pumpWidget(_mover(app, 'milk', 'buy'));
      await tester.tap(find.text('move'));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('it says what\'s in the expenses and where the item is going, before anything changes', (tester) async {
      final app = await bought(tester);
      expect(find.text('Remove it from your expenses too?'), findsOneWidget);
      final date = fmt(fromDateKey(toDateKey(DateTime.now())), 'MMM d');
      expect(find.text("Milk is in your expenses for $date — ৳120. It's going back to To buy."), findsOneWidget);
      expect(_columnOf(app, 'milk'), 'bought');
      expect(app.transactions, hasLength(1));
    });

    testWidgets('with no price yet it says that instead', (tester) async {
      final app = _store();
      await tester.runAsync(() => _buy(app, 'eggs'));
      await tester.pumpWidget(_mover(app, 'eggs', 'buy'));
      await tester.tap(find.text('move'));
      await tester.pumpAndSettle();
      final date = fmt(fromDateKey(toDateKey(DateTime.now())), 'MMM d');
      expect(find.text("Eggs is in your expenses for $date, with no price yet. It's going back to To buy."), findsOneWidget);
    });

    testWidgets('Cancel leaves everything where it was', (tester) async {
      final app = await bought(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_columnOf(app, 'milk'), 'bought');
      expect(app.transactions.single.ticketId, 'milk');
    });

    testWidgets('tapping outside is Cancel too', (tester) async {
      final app = await bought(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Remove it from your expenses too?'), findsNothing);
      expect(_columnOf(app, 'milk'), 'bought');
      expect(app.transactions, hasLength(1));
    });

    testWidgets('Remove expense moves it back and takes the expense off', (tester) async {
      final app = await bought(tester);
      final notices = <String>[];
      final sub = app.notices.stream.listen(notices.add);
      addTearDown(sub.cancel);
      await tester.tap(find.text('Remove expense'));
      await tester.pumpAndSettle();
      expect(_columnOf(app, 'milk'), 'buy');
      expect(app.transactions, isEmpty);
      expect(notices, ['Milk is off your expenses.']);
    });

    testWidgets('Keep expense moves it back and leaves the expense, and buying again logs a new one', (tester) async {
      final app = await bought(tester);
      await tester.tap(find.text('Keep expense'));
      await tester.pumpAndSettle();
      expect(_columnOf(app, 'milk'), 'buy');
      expect(app.transactions.single.ticketId, isNull);
      await tester.runAsync(() => _buy(app, 'milk'));
      expect(app.transactions, hasLength(2));
      expect(app.transactions.where((t) => t.ticketId == 'milk'), hasLength(1));
    });

    testWidgets('an expense that can\'t be taken off is reported, and the item has still moved', (tester) async {
      final app = await bought(tester);
      app.db = _FailingDelete();
      final notices = <String>[];
      final sub = app.notices.stream.listen(notices.add);
      addTearDown(sub.cancel);
      await tester.tap(find.text('Remove expense'));
      await tester.pumpAndSettle();
      expect(_columnOf(app, 'milk'), 'buy');
      expect(notices, ["Milk moved, but its expense couldn't be changed — check it in the ledger."]);
    });

    testWidgets('nothing to ask: no expense, or going to Bought, or along the list', (tester) async {
      final app = _store();
      await tester.pumpWidget(_mover(app, 'milk', 'cart'));
      await tester.tap(find.text('move'));
      await tester.pumpAndSettle();
      expect(find.text('Remove it from your expenses too?'), findsNothing);
      expect(_columnOf(app, 'milk'), 'cart');

      await tester.runAsync(() => _buy(app, 'milk'));
      expect(app.expenseLeaving('milk', 'bought'), isNull); // staying in Bought
      expect(app.expenseLeaving('milk', 'cart'), isNotNull);
      expect(app.expenseLeaving('eggs', 'cart'), isNull); // no expense
    });

    testWidgets('dragged on the board: into Bought logs it, and back out asks', (tester) async {
      final app = _store();
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> drag(String title, String column) async {
        final gesture = await tester.startGesture(tester.getCenter(find.text(title)));
        await tester.pump(const Duration(milliseconds: 400));
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.text(column)) + const Offset(0, 60));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(host(app, const BoardsScreen(kind: BoardKind.shopping)));
      await tester.pumpAndSettle();
      await drag('Milk', 'BOUGHT');
      expect(_columnOf(app, 'milk'), 'bought');
      expect(app.transactions.single.note, 'Milk');

      await drag('Milk', 'TO BUY');
      expect(find.text('Remove it from your expenses too?'), findsOneWidget);
      expect(_columnOf(app, 'milk'), 'bought');
      await tester.tap(find.text('Remove expense'));
      await tester.pumpAndSettle();
      expect(_columnOf(app, 'milk'), 'buy');
      expect(app.transactions, isEmpty);
    });

    testWidgets('from the item\'s editor: a price and Bought in one save logs that price', (tester) async {
      final app = _store();
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(app, const BoardsScreen(kind: BoardKind.shopping)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eggs'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Optional'), '165');
      await tester.tap(find.text('To buy').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bought').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(_columnOf(app, 'eggs'), 'bought');
      expect(app.transactions.single.amount, 165);
      expect(app.needPrice, isEmpty);
    });
  });

  group('asking for prices', () {
    AppState waiting() {
      final today = toDateKey(DateTime.now());
      Txn entry(String id, String note, double amount) => Txn.fromRow({
            'id': id, 'kind': 'expense', 'amount': amount, 'category_name': 'Groceries', 'note': note,
            'occurred_on': today, 'occurred_at': '${today}T08:00:00Z', 'created_at': '', 'ticket_id': id,
          });
      final app = _store()..transactions = [entry('eggs', 'Eggs', 0), entry('salt', 'Salt', 0), entry('milk', 'Milk', 120)];
      _db(app).ticketOf.addAll({'eggs': 'eggs', 'salt': 'salt', 'milk': 'milk'});
      return app;
    }

    testWidgets('the ledger shows Add price instead of ৳0, and it opens the list', (tester) async {
      final app = waiting();
      await tester.pumpWidget(host(app, const LedgerScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Add price'), findsNWidgets(2));
      expect(find.textContaining('৳120'), findsWidgets);
      await tester.tap(find.text('Add price').first);
      await tester.pumpAndSettle();
      expect(find.byType(PriceSheet), findsOneWidget);
      expect(find.text('What did you pay?'), findsOneWidget);
      expect(find.descendant(of: find.byType(PriceSheet), matching: find.text('Eggs')), findsOneWidget);
      expect(find.descendant(of: find.byType(PriceSheet), matching: find.text('Salt')), findsOneWidget);
      expect(find.descendant(of: find.byType(PriceSheet), matching: find.text('Milk')), findsNothing);
    });

    testWidgets('the list saves what\'s filled in, and leaves the rest waiting', (tester) async {
      final app = waiting();
      await tester.pumpWidget(host(app, Builder(builder: (c) => TextButton(onPressed: () => openPriceSheet(c), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(PriceSheet), matching: find.byType(TextField));
      PrimaryButton save() => tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(save().onPressed, isNull); // nothing to save yet
      await tester.enterText(fields.first, '০০');
      await tester.pump();
      expect(save().onPressed, isNull); // zero isn't a price
      await tester.enterText(fields.first, '1,250.50');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(PriceSheet), findsNothing);
      expect(app.transactions.firstWhere((t) => t.id == 'eggs').amount, 1250.5);
      expect(app.needPrice.map((t) => t.id), ['salt']);
    });

    testWidgets('Bengali digits work, and Later leaves everything waiting', (tester) async {
      final app = waiting();
      await tester.pumpWidget(host(app, Builder(builder: (c) => TextButton(onPressed: () => openPriceSheet(c), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(PriceSheet), matching: find.byType(TextField)).first, '১৫০');
      await tester.pump();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(PriceSheet), findsNothing);
      expect(app.needPrice, hasLength(2));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(PriceSheet), matching: find.byType(TextField)).first, '১৫০');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(app.transactions.firstWhere((t) => t.id == 'eggs').amount, 150);
    });

    testWidgets('the entry editor keeps a priceless entry saveable, with its amount empty', (tester) async {
      final app = waiting();
      await tester.pumpWidget(host(app, Scaffold(body: TxnEditSheet(txn: app.transactions.first))));
      await tester.pumpAndSettle();
      final amount = tester.widget<TextField>(find.byType(TextField).first);
      expect(amount.controller!.text, '');
      await tester.enterText(find.widgetWithText(TextField, 'What was it for?'), 'Eggs, a dozen');
      await tester.pump();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final t = app.transactions.firstWhere((x) => x.id == 'eggs');
      expect((t.note, t.amount, t.ticketId), ('Eggs, a dozen', 0.0, 'eggs'));
    });

    testWidgets('the dashboard and calendar draw a period whose only expense has no price', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final today = toDateKey(DateTime.now());
      final app = FakeApp()
        ..loading = false
        ..categories = [_cat('g', 'Groceries')]
        ..transactions = [
          Txn.fromRow({'id': 'eggs', 'kind': 'expense', 'amount': 0, 'category_name': 'Groceries', 'note': 'Eggs', 'occurred_on': today, 'occurred_at': '${today}T08:00:00Z', 'created_at': '', 'ticket_id': 'eggs'}),
        ];
      for (final screen in <Widget>[DashboardScreen(onCustomize: () {}), const CalendarScreen(), const LedgerScreen()]) {
        await tester.pumpWidget(host(app, screen));
        await tester.pump(const Duration(milliseconds: 300));
        for (var i = 0; i < 4; i++) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -500), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
      }
    });

    test('a reminder is scheduled for tonight, or the next evening once tonight has passed', () {
      final app = waiting();
      PlannedNotice? notice(DateTime now) => Notifications.plan(app, now).where((n) => n.target == NoticeTarget.prices).firstOrNull;
      final morning = notice(DateTime(2026, 11, 5, 10))!;
      expect(morning.at, DateTime(2026, 11, 5, 21));
      expect(morning.title, 'Prices to add');
      expect(morning.body, '2 bought items need a price');
      expect(notice(DateTime(2026, 11, 5, 22))!.at, DateTime(2026, 11, 6, 21));
    });

    test('one item reads as one, and none schedules nothing, and it can be turned off', () {
      final app = waiting();
      app.transactions = app.transactions.where((t) => t.id != 'salt').toList();
      bool has(AppState a) => Notifications.plan(a, DateTime(2026, 11, 5, 10)).any((n) => n.target == NoticeTarget.prices);
      expect(Notifications.plan(app, DateTime(2026, 11, 5, 10)).firstWhere((n) => n.target == NoticeTarget.prices).body, '1 bought item needs a price');
      expect(has(waiting()..reminders = const ReminderPrefs(prices: false)), isFalse);
      expect(has(_store()), isFalse);
    });

    test('the setting travels with the account, and older settings start with it on', () {
      expect(const ReminderPrefs().prices, isTrue);
      expect(ReminderPrefs.fromJson(const ReminderPrefs(prices: false).toJson()).prices, isFalse);
      expect(ReminderPrefs.fromJson({'checkin': true}).prices, isTrue);
      expect(const ReminderPrefs().copyWith(prices: false).onCount, ReminderPrefs.kinds - 1);
    });
  });

  group('in the shell', () {
    void channels() {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in ['catalyst/widget', 'catalyst/sms']) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
      }
      addTearDown(() {
        for (final name in ['catalyst/widget', 'catalyst/sms']) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
      });
    }

    Txn priceless(String id) => Txn.fromRow({
          'id': id, 'kind': 'expense', 'amount': 0, 'category_name': 'Groceries', 'note': id, 'occurred_on': toDateKey(DateTime.now()),
          'occurred_at': DateTime.now().toUtc().toIso8601String(), 'created_at': '', 'ticket_id': id,
        });

    testWidgets('a banner says what needs a price; dismissed, it comes back with another', (tester) async {
      channels();
      final app = FakeApp()
        ..loading = false
        ..transactions = [priceless('Eggs')];
      await tester.pumpWidget(await shellFor(app));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1 bought item needs a price'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss').first);
      await tester.pump();
      expect(find.text('1 bought item needs a price'), findsNothing);

      app.transactions = [...app.transactions, priceless('Salt')];
      app.logSomething();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2 bought items need a price'), findsOneWidget);

      await tester.tap(find.text('ADD PRICE'));
      await tester.pumpAndSettle();
      expect(find.byType(PriceSheet), findsOneWidget);
    });

    testWidgets('no banner with that kind of notification off', (tester) async {
      channels();
      final app = FakeApp()
        ..loading = false
        ..reminders = const ReminderPrefs(prices: false)
        ..transactions = [priceless('Eggs')];
      await tester.pumpWidget(await shellFor(app));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1 bought item needs a price'), findsNothing);
    });

    testWidgets('a tapped notification opens the list', (tester) async {
      channels();
      final app = FakeApp()
        ..loading = false
        ..transactions = [priceless('Eggs')];
      await tester.pumpWidget(await shellFor(app));
      await tester.pump(const Duration(seconds: 1));
      Notifications.taps.add(NoticeTarget.prices);
      await tester.pumpAndSettle();
      expect(find.byType(PriceSheet), findsOneWidget);
    });
  });
}

/// The fake database, except that deleting an expense fails.
class _FailingDelete extends FakeMoneyDb {
  @override
  Future<void> deleteTransaction(String id) async => throw Exception('no');
}

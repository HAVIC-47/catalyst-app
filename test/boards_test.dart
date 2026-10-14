import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/data/insights.dart';
import 'package:catalyst/data/scan.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/boards_screen.dart';
import 'package:catalyst/screens/list_scan_sheet.dart';
import 'package:catalyst/screens/shell.dart';
import 'package:catalyst/theme/app_theme.dart';
import 'package:catalyst/theme/palette.dart';
import 'package:catalyst/theme/theme_controller.dart';
import 'package:catalyst/util/range.dart';
import 'package:catalyst/widgets/ai_insights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';

Future<Widget> _shell(AppState app) async {
  final theme = await ThemeController.load();
  return MultiProvider(
    providers: [ChangeNotifierProvider.value(value: theme), ChangeNotifierProvider<AppState>.value(value: app)],
    child: MaterialApp(theme: buildTheme(Palette.night), home: const AppShell()),
  );
}

Map<String, dynamic> _item(String title, {bool done = false, String priority = 'medium', String due = '', String notes = '', double price = 0}) =>
    {'title': title, 'notes': notes, 'done': done, 'priority': priority, 'due': due, 'price': price};

void main() {
  final pick = Scan.pick, send = Scan.send;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    Scan.pick = pick;
    Scan.send = send;
    AiInsightsCard.request = requestInsight;
  });

  group('ticket order', () {
    test('sortBetween splits neighbours, pads the ends, and gives up when too close', () {
      expect(sortBetween(null, null), sortStep);
      expect(sortBetween(null, 1024), 0);
      expect(sortBetween(1024, null), 2048);
      expect(sortBetween(1024, 2048), 1536);
      expect(sortBetween(1, 1 + 1e-9), isNull);
      expect(sortBetween(5, 5), isNull);
    });

    test('byTicketOrder sorts by sort, then number', () {
      final a = ticket('a', 'c', 2, 'a', 10), b = ticket('b', 'c', 1, 'b', 10), c = ticket('c', 'c', 3, 'c', 5);
      expect(([a, b, c]..sort(byTicketOrder)).map((t) => t.id), ['c', 'b', 'a']);
    });

    test('Ticket.fromRow reads the database row', () {
      final t = Ticket.fromRow({
        'id': 'x', 'board_id': 'b', 'column_id': 'c', 'number': 7, 'title': 'Rice', 'description': null,
        'priority': 'high', 'due_on': '2026-10-20', 'amount': '950.50', 'sort': 2048,
      });
      expect(t.number, 7);
      expect(t.priority, TicketPriority.high);
      expect(t.amount, 950.5);
      expect(t.sort, 2048.0);
      expect(t.description, '');
      expect(Ticket.fromRow({'id': 'y', 'board_id': 'b', 'column_id': 'c', 'title': 'T', 'priority': 'weird'}).priority, TicketPriority.medium);
    });

    test('newTicketRows numbers after the board and joins the bottom of each column, in order', () {
      final existing = [
        ticket('t1', 'c1', 1, 'a', 1024),
        ticket('t2', 'c1', 7, 'b', 5000),
        ticket('t3', 'c3', 3, 'c', 2048),
        const Ticket(id: 'x', boardId: 'other', columnId: 'z', number: 99, title: 'x', description: '', priority: TicketPriority.low, dueOn: null, amount: null, sort: 9e9),
      ];
      NewTicket draft(String column, String title) =>
          (columnId: column, title: title, description: '', priority: TicketPriority.high, dueOn: '2026-10-20', amount: 950);
      final rows = newTicketRows('b1', [draft('c1', 'A'), draft('c3', 'B'), draft('c1', 'C'), draft('c2', 'D')], existing);
      expect(rows.map((r) => r['number']), [8, 9, 10, 11]); // the other board's #99 doesn't count
      expect(rows.map((r) => r['sort']), [5000 + sortStep, 2048 + sortStep, 5000 + 2 * sortStep, sortStep]);
      expect(rows.first, containsPair('board_id', 'b1'));
      expect(rows.first, containsPair('priority', 'high'));
      expect(rows.first, containsPair('due_on', '2026-10-20'));
      expect(rows.first, containsPair('amount', 950));
    });
  });

  group('insights', () {
    test('InsightResult parses the API reply and drops empty bits', () {
      final r = InsightResult.fromJson({
        'insight': {
          'headline': 'Calmer week',
          'summary': 'You spent less.',
          'highlights': ['Shopping was 69%', '', 3],
          'suggestions': [
            {'title': 'Cap shopping', 'detail': 'Set a limit.'},
            'junk',
          ],
        },
        'generatedAt': '2026-10-14T08:00:00.000Z',
        'stale': true,
        'empty': false,
      });
      expect(r.insight!.highlights, ['Shopping was 69%']);
      expect(r.insight!.suggestions, [('Cap shopping', 'Set a limit.')]);
      expect(r.stale, isTrue);
      expect(r.generatedAt, isNotNull);
    });

    test('no saved summary', () {
      final r = InsightResult.fromJson({'insight': null, 'generatedAt': null, 'stale': false, 'empty': true});
      expect(r.insight, isNull);
      expect(r.empty, isTrue);
      expect(Insight.fromJson({'summary': ''}), isNull);
    });
  });

  group('boards screen', () {
    testWidgets('shows the board, its columns and tickets', (tester) async {
      await tester.pumpWidget(host(seeded(), const BoardsScreen(kind: BoardKind.todo)));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets);
      expect(find.text('TO DO'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('Fix the kitchen tap'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('3 open · 1 done'), findsOneWidget);
    });

    testWidgets('long-press drag moves a ticket into another column', (tester) async {
      final app = seeded();
      await tester.pumpWidget(host(app, const BoardsScreen(kind: BoardKind.todo)));
      await tester.pumpAndSettle();

      final from = tester.getCenter(find.text('Call the landlord'));
      final target = tester.getRect(find.ancestor(of: find.text('Paint the balcony'), matching: find.byType(Container)).first);
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 400)); // past the long-press delay
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      // Into the lower half of "Paint the balcony": lands below it.
      await gesture.moveTo(Offset(target.center.dx, target.bottom - 6));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(app.moves, hasLength(1));
      expect(app.moves.single.$1, 't2');
      expect(app.moves.single.$2, 'c2');
      expect(app.moves.single.$3, ['t4', 't2']);
      expect(app.ticketsIn('c2').map((t) => t.id), ['t4', 't2']);
      expect(app.ticketsIn('c1').map((t) => t.id), ['t1']);
    });

    testWidgets('a quick tap opens the editor instead of dragging', (tester) async {
      final app = seeded();
      await tester.pumpWidget(host(app, const BoardsScreen(kind: BoardKind.todo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fix the kitchen tap'));
      await tester.pumpAndSettle();
      expect(find.text('Edit ticket'), findsOneWidget);
      expect(find.text('#1 · HOME'), findsOneWidget);
      expect(app.moves, isEmpty);
    });

    testWidgets('first visit offers to create a board', (tester) async {
      final app = FakeApp()..loading = false;
      await tester.pumpWidget(host(app, const BoardsScreen(kind: BoardKind.shopping)));
      await tester.pumpAndSettle();
      expect(find.text('Start your first list'), findsOneWidget);
      expect(find.text('Starts with To buy · In cart · Bought — rename them or add more any time.'), findsOneWidget);
    });

    testWidgets('the board shows the board it was left on', (tester) async {
      final app = seeded()
        ..boards = [...seeded().boards, const Board(id: 'b9', name: 'Work', kind: BoardKind.todo, sort: 1)]
        ..selectedBoards[BoardKind.todo] = 'b9';
      await tester.pumpWidget(host(app, const BoardsScreen(kind: BoardKind.todo)));
      await tester.pumpAndSettle();
      expect(find.text('0 open · 0 done'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(app.selectedBoards[BoardKind.todo], 'b1');
      expect(find.text('3 open · 1 done'), findsOneWidget);
    });

    testWidgets('a folded AI to-do summary sits under the title, plus a tip about +', (tester) async {
      final calls = <InsightTopic>[];
      AiInsightsCard.request = ({required topic, required period, required start, required generate}) async {
        calls.add(topic);
        return InsightResult.fromJson({'insight': null, 'generatedAt': null, 'stale': false, 'empty': false});
      };
      await tester.pumpWidget(host(seeded(), const BoardsScreen(kind: BoardKind.todo)));
      await tester.pumpAndSettle();
      expect(find.textContaining('AI TO-DO SUMMARY'), findsOneWidget);
      expect(find.text('Tip: tap + below to add tickets from a screenshot of your notes.'), findsOneWidget);
      expect(calls, isEmpty); // folded: nothing is asked for

      await tester.tap(find.textContaining('AI TO-DO SUMMARY'));
      await tester.pumpAndSettle();
      expect(calls, [InsightTopic.todo]);
      expect(find.text("What's done, what's overdue or due soon, and what to tackle first."), findsOneWidget);
      expect(find.text('Summarize this week'), findsOneWidget);
    });
  });

  group('list scanner', () {
    testWidgets('+ on To-do reads a screenshot of a list onto the board, with Undo', (tester) async {
      final app = seeded();
      final sent = <(String, Map<String, dynamic>)>[];
      Scan.pick = (_) async => png;
      Scan.send = (path, body) async {
        sent.add((path, body));
        return {
          'list': {
            'items': [
              _item('Pay electricity bill', priority: 'high', due: '2026-10-20', notes: 'before the 20th'),
              _item('Book bus tickets', done: true),
              _item('Call mum', priority: 'low'),
            ],
          },
        };
      };

      await tester.pumpWidget(await _shell(app));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Scan a memo or notes'), findsOneWidget);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('To-do'));
      await tester.pumpAndSettle();

      // On a board the + adds a list instead of scanning a memo.
      await tester.tap(find.byTooltip('Add from a screenshot of your list'));
      await tester.pumpAndSettle();
      expect(find.text('Scan a list'), findsOneWidget);
      expect(find.textContaining('Every item goes straight onto Home;'), findsOneWidget);
      await tester.tap(find.text('Upload screenshot'));
      await tester.pumpAndSettle();

      expect(find.text('Added 3 tickets'), findsOneWidget);
      expect(find.text('to Home'), findsOneWidget);
      expect(sent.single.$1, '/api/scan-list');
      expect(sent.single.$2, containsPair('kind', 'todo'));
      expect(sent.single.$2, containsPair('mimeType', 'image/png'));
      // Open items join the bottom of To do; the ticked one goes straight to Done.
      expect(app.ticketsIn('c1').map((t) => t.title), ['Fix the kitchen tap', 'Call the landlord', 'Pay electricity bill', 'Call mum']);
      expect(app.ticketsIn('c3').map((t) => t.title), ['Pay internet bill', 'Book bus tickets']);
      final bill = app.tickets.firstWhere((t) => t.title == 'Pay electricity bill');
      expect((bill.number, bill.priority, bill.dueOn, bill.description), (6, TicketPriority.high, '2026-10-20', 'before the 20th'));

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Taken back off the board'), findsOneWidget);
      expect(app.tickets.map((t) => t.id), ['t1', 't2', 't4', 't5']);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Scan a list'), findsNothing);
    });

    testWidgets('a first to-buy list can start straight from a screenshot', (tester) async {
      final app = FakeApp()..loading = false;
      Scan.pick = (_) async => png;
      Scan.send = (path, body) async => {
            'list': {
              'items': [_item('Rice 5 kg', price: 950), _item('Eggs (12)', price: 165), _item('Soap', done: true)],
            },
          };
      await tester.pumpWidget(host(app, const BoardsScreen(kind: BoardKind.shopping)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Or start from a screenshot of your list'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Groceries (a new list); ticked items go in as bought.'), findsOneWidget);
      await tester.tap(find.text('Upload screenshot'));
      await tester.pumpAndSettle();

      expect(find.text('Added 3 items'), findsOneWidget);
      expect(find.text('to Groceries · ৳1,115'), findsOneWidget);
      expect(find.text('BOUGHT'), findsWidgets);
      final board = app.boards.single;
      expect((board.name, board.kind), ('Groceries', BoardKind.shopping));
      expect(app.selectedBoards[BoardKind.shopping], board.id);
      final cols = app.columnsOf(board.id);
      expect(app.ticketsIn(cols.first.id).map((t) => (t.title, t.amount)), [('Rice 5 kg', 950), ('Eggs (12)', 165)]);
      expect(app.ticketsIn(cols.last.id).map((t) => (t.title, t.amount)), [('Soap', null)]);
    });

    testWidgets('a reader error is shown with Try again, and nothing is added', (tester) async {
      final app = seeded();
      Scan.pick = (_) async => png;
      Scan.send = (path, body) async => throw const ScanError("That doesn't look like a list — try a screenshot of your notes.");
      await tester.pumpWidget(host(app, Builder(builder: (c) => TextButton(onPressed: () => openListScanner(c, BoardKind.todo), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload screenshot'));
      await tester.pumpAndSettle();
      expect(find.text("That doesn't look like a list — try a screenshot of your notes."), findsOneWidget);
      expect(app.tickets, hasLength(4));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Upload screenshot'), findsOneWidget);
    });
  });

  testWidgets('bottom bar: Calendar · Dashboard · + · Ledger · More (Journal moved to More)', (tester) async {
    await tester.pumpWidget(await _shell(seeded()));
    await tester.pumpAndSettle();
    final bar = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_BottomNav');
    for (final label in ['Calendar', 'Dashboard', 'Ledger', 'More']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget, reason: label);
    }
    expect(find.descendant(of: bar, matching: find.text('Journal')), findsNothing);
    expect(find.byTooltip('Scan a memo or notes'), findsOneWidget);
    // A slim bar pinned to the bottom, not one that grows to fill the screen.
    expect(tester.getSize(bar).height, lessThan(90));
    expect(tester.getRect(bar).bottom, tester.view.physicalSize.height / tester.view.devicePixelRatio);
    // The + left the top bar for the bottom bar.
    expect(find.bySemanticsLabel('Scan a memo or notes'), findsOneWidget);
  });

  testWidgets('AI card: offer -> generate -> summary, then "new entries since" after data changes', (tester) async {
    final app = seeded();
    final calls = <(InsightTopic, Range, bool)>[];
    var saved = false;
    var stale = false;
    const insight = {
      'headline': 'Calmer week, lighter spending',
      'summary': 'You spent ৳4,180 so far this week.',
      'highlights': ['Shopping was 69% of spending.'],
      'suggestions': [
        {'title': 'Cap shopping', 'detail': 'Set a ৳1,500 limit for the rest of the week.'},
      ],
    };
    AiInsightsCard.request = ({required topic, required period, required start, required generate}) async {
      calls.add((topic, period, generate));
      if (generate) saved = true;
      return InsightResult.fromJson({
        'insight': saved ? insight : null,
        'generatedAt': saved ? DateTime.now().toIso8601String() : null,
        'stale': stale,
        'empty': false,
      });
    };

    await tester.pumpWidget(host(app, ListView(children: const [AiInsightsCard(topics: [InsightTopic.ledger])])));
    await tester.pumpAndSettle();
    expect(find.text('Summarize this week'), findsOneWidget);
    expect(calls.single, (InsightTopic.ledger, Range.week, false));

    await tester.tap(find.text('Summarize this week'));
    await tester.pumpAndSettle();
    expect(find.text('Calmer week, lighter spending'), findsOneWidget);
    expect(find.text('Cap shopping'), findsOneWidget);
    expect(find.text('MONEY MOVES'), findsOneWidget);
    expect(calls.last.$3, isTrue);

    // New data: the card re-checks quietly and offers an update.
    stale = true;
    app.logSomething();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('New entries since'), findsOneWidget);
    expect(find.text('UPDATE'), findsOneWidget);

    // Another period is a fresh load.
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(calls.last, (InsightTopic.ledger, Range.month, false));
  });

  testWidgets('AI card renders its tabs and periods without a server', (tester) async {
    final app = seeded();
    await tester.pumpWidget(host(app, ListView(children: const [AiInsightsCard(topics: [InsightTopic.mood, InsightTopic.ledger])])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('AI INSIGHTS'), findsOneWidget);
    expect(find.text('Mood'), findsOneWidget);
    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    // No Supabase here, so loading fails politely instead of throwing.
    expect(find.text("AI summaries aren't available right now."), findsOneWidget);
  });
}

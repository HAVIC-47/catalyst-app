import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/data/insights.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/boards_screen.dart';
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

/// The store without Supabase: data is set directly, and moves are recorded and
/// applied locally (what the real placeTicket does before its network write).
class _FakeApp extends AppState {
  final moves = <(String, String, List<String>)>[];

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
}

Ticket _ticket(String id, String column, int number, String title, double sort, {TicketPriority priority = TicketPriority.medium}) =>
    Ticket(id: id, boardId: 'b1', columnId: column, number: number, title: title, description: '', priority: priority, dueOn: null, amount: null, sort: sort);

_FakeApp _seeded() => _FakeApp()
  ..loading = false
  ..boards = [const Board(id: 'b1', name: 'Home', kind: BoardKind.todo, sort: 0)]
  ..boardColumns = [
    const BoardColumn(id: 'c1', boardId: 'b1', name: 'To do', sort: 0),
    const BoardColumn(id: 'c2', boardId: 'b1', name: 'In progress', sort: 1),
    const BoardColumn(id: 'c3', boardId: 'b1', name: 'Done', sort: 2),
  ]
  ..tickets = [
    _ticket('t1', 'c1', 1, 'Fix the kitchen tap', 1024, priority: TicketPriority.high),
    _ticket('t2', 'c1', 2, 'Call the landlord', 2048),
    _ticket('t4', 'c2', 4, 'Paint the balcony', 1024),
    _ticket('t5', 'c3', 5, 'Pay internet bill', 1024),
  ];

Widget _host(AppState app, Widget child) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Palette.night), home: Scaffold(body: child)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
      final a = _ticket('a', 'c', 2, 'a', 10), b = _ticket('b', 'c', 1, 'b', 10), c = _ticket('c', 'c', 3, 'c', 5);
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
      await tester.pumpWidget(_host(_seeded(), const BoardsScreen(kind: BoardKind.todo)));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets);
      expect(find.text('TO DO'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('Fix the kitchen tap'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('3 open · 1 done'), findsOneWidget);
    });

    testWidgets('long-press drag moves a ticket into another column', (tester) async {
      final app = _seeded();
      await tester.pumpWidget(_host(app, const BoardsScreen(kind: BoardKind.todo)));
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
      final app = _seeded();
      await tester.pumpWidget(_host(app, const BoardsScreen(kind: BoardKind.todo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fix the kitchen tap'));
      await tester.pumpAndSettle();
      expect(find.text('Edit ticket'), findsOneWidget);
      expect(find.text('#1 · HOME'), findsOneWidget);
      expect(app.moves, isEmpty);
    });

    testWidgets('first visit offers to create a board', (tester) async {
      final app = _FakeApp()..loading = false;
      await tester.pumpWidget(_host(app, const BoardsScreen(kind: BoardKind.shopping)));
      await tester.pumpAndSettle();
      expect(find.text('Start your first list'), findsOneWidget);
      expect(find.text('Starts with To buy · In cart · Bought — rename them or add more any time.'), findsOneWidget);
    });
  });

  testWidgets('bottom bar: Calendar · Dashboard · + · Ledger · More (Journal moved to More)', (tester) async {
    final theme = await ThemeController.load();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: theme), ChangeNotifierProvider<AppState>.value(value: _seeded())],
      child: MaterialApp(theme: buildTheme(Palette.night), home: const AppShell()),
    ));
    await tester.pumpAndSettle();
    final bar = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_BottomNav');
    for (final label in ['Calendar', 'Dashboard', 'Ledger', 'More']) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget, reason: label);
    }
    expect(find.descendant(of: bar, matching: find.text('Journal')), findsNothing);
    expect(find.byTooltip('Scan a memo'), findsOneWidget);
    // A slim bar pinned to the bottom, not one that grows to fill the screen.
    expect(tester.getSize(bar).height, lessThan(90));
    expect(tester.getRect(bar).bottom, tester.view.physicalSize.height / tester.view.devicePixelRatio);
    // The + left the top bar for the bottom bar.
    expect(find.bySemanticsLabel('Scan a memo'), findsOneWidget);
  });

  testWidgets('AI card: offer -> generate -> summary, then "new entries since" after data changes', (tester) async {
    final app = _seeded();
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
    addTearDown(() => AiInsightsCard.request = requestInsight);

    await tester.pumpWidget(_host(app, ListView(children: const [AiInsightsCard(topics: [InsightTopic.ledger])])));
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
    final app = _seeded();
    await tester.pumpWidget(_host(app, ListView(children: const [AiInsightsCard(topics: [InsightTopic.mood, InsightTopic.ledger])])));
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

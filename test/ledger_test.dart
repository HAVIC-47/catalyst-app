import 'package:catalyst/data/insights.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/dashboard_screen.dart';
import 'package:catalyst/screens/ledger_screen.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/widgets/ai_insights.dart';
import 'package:catalyst/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';

final _today = toDateKey(DateTime.now());

Txn _txn(String id, Kind kind, double amount, String category, {String? categoryId, String note = '', String created = ''}) => Txn(
      id: id,
      kind: kind,
      amount: amount,
      categoryId: categoryId,
      categoryName: category,
      place: '',
      note: note,
      occurredOn: _today,
      occurredAt: '${_today}T08:00:00.000Z',
      createdAt: created,
    );

/// This month: ৳1,193 spent (120 + 173 + 900) and ৳65,000 earned, all today.
FakeApp _app() => FakeApp()
  ..loading = false
  // Only the KPI tiles on the dashboard (no charts or AI card).
  ..dashboardHidden = ['trend', 'insights', 'spent', 'earned', 'mood', 'savings', 'moodTags', 'categories']
  ..categories = const [
    Category(id: 'food', name: 'Food', kind: Kind.expense, color: '#C06A33', sort: 0),
    Category(id: 'transport', name: 'Transport', kind: Kind.expense, color: '#3D80BC', sort: 1),
    Category(id: 'other', name: 'Other', kind: Kind.expense, color: '#7A746A', sort: 2),
    Category(id: 'salary', name: 'Salary', kind: Kind.income, color: '#2E8159', sort: 0),
    Category(id: 'other-in', name: 'Other', kind: Kind.income, color: '#7A746A', sort: 1),
  ]
  ..transactions = [
    _txn('t1', Kind.expense, 120, 'Food', categoryId: 'food', note: 'lunch', created: '2026-10-14T03:00:00Z'),
    _txn('t2', Kind.expense, 173, 'Food', note: 'groceries', created: '2026-10-14T02:00:00Z'), // older row: category by name only
    _txn('t3', Kind.expense, 900, 'Gadgets', note: 'headphones', created: '2026-10-14T01:00:00Z'), // its category was deleted
    _txn('t4', Kind.income, 65000, 'Salary', categoryId: 'salary', note: 'October pay', created: '2026-10-14T00:00:00Z'),
  ];

/// The pen on the row whose title is [title].
Finder _pen(String title) =>
    find.descendant(of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first, matching: find.byTooltip('Edit'));

Finder get _save => find.widgetWithText(PrimaryButton, 'Save changes');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AiInsightsCard.request = ({required topic, required period, required start, required generate}) async =>
        InsightResult.fromJson({'insight': null, 'generatedAt': null, 'stale': false, 'empty': true});
  });
  tearDown(() => AiInsightsCard.request = requestInsight);

  test('newestFirst: newest day first, then newest added', () {
    Txn t(String id, String on, String created) => Txn(
        id: id, kind: Kind.expense, amount: 1, categoryId: null, categoryName: 'x', place: '', note: '',
        occurredOn: on, occurredAt: '', createdAt: created);
    final list = [t('a', '2026-10-12', '1'), t('b', '2026-10-14', '1'), t('c', '2026-10-14', '2'), t('d', '2026-10-13', '9')]..sort(newestFirst);
    expect(list.map((x) => x.id), ['c', 'b', 'd', 'a']);
  });

  testWidgets('every row has a pen; an edit is saved and the totals follow, here and on the dashboard', (tester) async {
    final app = _app();
    await tester.pumpWidget(host(app, const LedgerScreen()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit'), findsNWidgets(4));
    expect(find.text('Out ৳1,193'), findsOneWidget);

    await tester.tap(_pen('lunch'));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaction'), findsOneWidget);
    expect(find.widgetWithText(TextField, '120'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(_save).onPressed, isNull); // nothing changed yet

    await tester.enterText(find.widgetWithText(TextField, '120'), '500');
    await tester.tap(find.text('Transport'));
    await tester.enterText(find.widgetWithText(TextField, 'lunch'), 'Team lunch');
    await tester.pump();
    expect(tester.widget<PrimaryButton>(_save).onPressed, isNotNull);
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(find.text('Edit transaction'), findsNothing);
    final t1 = app.transactions.firstWhere((t) => t.id == 't1');
    expect((t1.amount, t1.categoryId, t1.categoryName, t1.note), (500, 'transport', 'Transport', 'Team lunch'));
    expect(t1.occurredAt, '${_today}T08:00:00.000Z'); // date and time untouched -> kept exactly
    expect(find.text('Out ৳1,573'), findsOneWidget); // the day total followed
    expect(find.text('Team lunch'), findsOneWidget);

    // Numbers elsewhere are computed from the same list, so they follow too.
    await tester.pumpWidget(host(app, DashboardScreen(onCustomize: () {})));
    await tester.pumpAndSettle();
    expect(find.text('৳1,573'), findsOneWidget); // Spent this month
    expect(find.text('৳65,000'), findsOneWidget); // Earned
  });

  testWidgets('an older row keeps its category exactly as saved when only the amount changes', (tester) async {
    final app = _app();
    await tester.pumpWidget(host(app, const LedgerScreen()));
    await tester.pumpAndSettle();
    await tester.tap(_pen('groceries'));
    await tester.pumpAndSettle();
    expect(tester.widget<PrimaryButton>(_save).onPressed, isNull); // its category by name alone isn't a change

    await tester.enterText(find.widgetWithText(TextField, '173'), '200');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    final t2 = app.transactions.firstWhere((t) => t.id == 't2');
    expect((t2.amount, t2.categoryId, t2.categoryName), (200, null, 'Food'));
  });

  testWidgets('a deleted category stays on its row until another is picked', (tester) async {
    final app = _app();
    await tester.pumpWidget(host(app, const LedgerScreen()));
    await tester.pumpAndSettle();
    await tester.tap(_pen('headphones'));
    await tester.pumpAndSettle();
    // Its old category shows as its own tile, chosen.
    final kept = find.descendant(of: find.byType(GridView), matching: find.text('Gadgets'));
    expect(kept, findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '900'), '850');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    final t3 = app.transactions.firstWhere((t) => t.id == 't3');
    expect((t3.amount, t3.categoryId, t3.categoryName), (850, null, 'Gadgets'));
  });

  testWidgets('switching to Income files it under Other; Delete removes it after asking', (tester) async {
    final app = _app();
    await tester.pumpWidget(host(app, const LedgerScreen()));
    await tester.pumpAndSettle();

    await tester.tap(_pen('lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income'));
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    final t1 = app.transactions.firstWhere((t) => t.id == 't1');
    expect((t1.kind, t1.categoryId, t1.categoryName), (Kind.income, 'other-in', 'Other'));
    expect(find.text('In ৳65,120'), findsOneWidget);

    await tester.tap(_pen('October pay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this transaction?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
    await tester.pumpAndSettle();
    expect(app.transactions.map((t) => t.id), isNot(contains('t4')));
    expect(find.text('Edit transaction'), findsNothing);
    expect(find.text('In ৳120'), findsOneWidget);
  });
}

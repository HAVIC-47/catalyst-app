// 1.8.0: editing a dhar, dhar in the transactions (borrowing in, paying back out;
// the reverse for lending), and a calendar day's Dhar and Transactions tabs.
import 'package:catalyst/data/insights.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/dhar_screen.dart';
import 'package:catalyst/screens/entry_sheet.dart';
import 'package:catalyst/screens/ledger_screen.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/money.dart';
import 'package:catalyst/widgets/ai_insights.dart';
import 'package:catalyst/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';
import 'fake_money_db.dart';

const _cash = Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 1000, sort: 0, archived: false);

final _day = toDateKey(DateTime.now().subtract(const Duration(days: 2)));
final _later = toDateKey(DateTime.now().subtract(const Duration(days: 1)));

Debt _debt(String id, String person, DebtDirection dir, double amount, String on) =>
    Debt(id: id, person: person, direction: dir, amount: amount, note: '', walletId: 'cash', occurredOn: on, dueOn: null, closed: false, createdAt: '');

DebtPayment _pay(String id, String debt, double amount, String on) =>
    DebtPayment(id: id, debtId: debt, amount: amount, walletId: 'cash', paidOn: on, note: '', createdAt: '');

FakeApp _app(FakeMoneyDb db) => FakeApp()
  ..loading = false
  ..db = db
  ..walletsReady = true
  ..wallets = [_cash]
  ..categories = const [Category(id: 'food', name: 'Food', kind: Kind.expense, color: '#C06A33', sort: 0)]
  ..transactions = [
    Txn(
      id: 't1',
      kind: Kind.expense,
      amount: 120,
      categoryId: 'food',
      categoryName: 'Food',
      place: '',
      note: 'lunch',
      occurredOn: _day,
      occurredAt: '${_day}T08:00:00.000Z',
      createdAt: '',
    ),
  ]
  ..debts = [
    _debt('b', 'Karim', DebtDirection.borrowed, 500, _day),
    _debt('l', 'Rahim', DebtDirection.lent, 300, _day),
  ]
  ..debtPayments = [_pay('pb', 'b', 200, _later), _pay('pl', 'l', 100, _later)];

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
    AiInsightsCard.request = ({required topic, required period, required start, required generate}) async =>
        InsightResult.fromJson({'insight': null, 'generatedAt': null, 'stale': false, 'empty': true});
  });
  tearDown(() => AiInsightsCard.request = requestInsight);

  test('dhar moves: borrowing in, paying it back out; lending out, getting it back in', () {
    final app = _app(FakeMoneyDb());
    final moves = {for (final m in dharMoves(app.debts, app.debtPayments)) m.id: m};
    expect(moves['debt:b']!.amount, 500);
    expect(moves['pay:pb']!.amount, -200);
    expect(moves['debt:l']!.amount, -300);
    expect(moves['pay:pl']!.amount, 100);
    expect(moves['pay:pb']!.label, 'Paid back Karim');
    expect(moves['pay:pl']!.label, 'Rahim paid back');
    // The same signs as the wallet's balance: 1000 − 120 + 500 − 200 − 300 + 100.
    expect(walletBalances(app.wallets, app.transactions, const [], app.debts, app.debtPayments)['cash'], 980);
  });

  testWidgets('the pen on a dhar changes it, and the wallet follows', (tester) async {
    await _tall(tester);
    final db = FakeMoneyDb();
    final app = _app(db);
    await tester.pumpWidget(host(app, const DharScreen()));
    await tester.pump();
    final pens = find.byTooltip('Edit');
    expect(pens, findsNWidgets(2));
    await tester.tap(pens.first);
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextField, '500');
    expect(amount, findsOneWidget);
    await tester.enterText(amount, '800');
    await tester.pump();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save'));
    await tester.pumpAndSettle();
    expect(db.calls.where((c) => c.startsWith('updateDebt b')), hasLength(1));
    expect(db.calls.last, contains('amount: 800.0'));
    final b = app.debts.firstWhere((d) => d.id == 'b');
    expect((b.amount, b.person, b.direction, b.occurredOn), (800.0, 'Karim', DebtDirection.borrowed, _day));
    expect(walletBalances(app.wallets, app.transactions, const [], app.debts, app.debtPayments)['cash'], 1280);
    expect(find.widgetWithText(PrimaryButton, 'Save'), findsNothing); // the form closed
  });

  testWidgets('the ledger lists dhar with its sign, and leaves it out under an Expense filter', (tester) async {
    await _tall(tester);
    final app = _app(FakeMoneyDb());
    await tester.pumpWidget(host(app, const LedgerScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Borrowed from Karim'), findsOneWidget);
    expect(find.text('+৳500'), findsOneWidget);
    expect(find.text('Lent to Rahim'), findsOneWidget);
    expect(find.text('−৳300'), findsOneWidget);
    expect(find.text('Paid back Karim'), findsOneWidget);
    expect(find.text('−৳200'), findsOneWidget);
    expect(find.text('Rahim paid back'), findsOneWidget);
    expect(find.text('+৳100'), findsOneWidget);
    // Not income or spending: the day's totals are the entries' alone.
    expect(find.text('Out ৳120'), findsOneWidget);
    expect(find.textContaining('In ৳'), findsNothing);

    // Only dhar, no entries: the dhar shows, not "No transactions yet".
    app.transactions = [];
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Borrowed from Karim'), findsOneWidget);
    expect(find.textContaining('No transactions yet'), findsNothing);
  });

  testWidgets("a day's Transactions tab shows that day's entries and dhar; its Dhar tab adds one on that day", (tester) async {
    await _tall(tester);
    final db = FakeMoneyDb();
    final app = _app(db);
    await tester.pumpWidget(host(app, Builder(builder: (context) => TextButton(onPressed: () => openEntry(context, date: _day), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final tab in ['Money', 'Mood', 'Saving', 'Dhar', 'Transactions']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('lunch'), findsOneWidget);
    expect(find.text('Borrowed from Karim'), findsOneWidget);
    expect(find.text('Lent to Rahim'), findsOneWidget);
    expect(find.text('Paid back Karim'), findsNothing); // that was the next day

    await tester.tap(find.text('Dhar').first); // the tab (the dhar lines say Dhar too)
    await tester.pumpAndSettle();
    await tester.tap(find.text('I borrowed'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Name or shop'), 'Nasima');
    await tester.enterText(find.byType(TextField).at(1), '250');
    await tester.pump();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Add'));
    await tester.pumpAndSettle();
    expect(db.calls, contains('addDebt Nasima'));
    final added = app.debts.firstWhere((d) => d.person == 'Nasima');
    expect((added.direction, added.amount, added.occurredOn), (DebtDirection.borrowed, 250.0, _day));
    expect(find.byType(EntrySheet), findsNothing); // saved and closed
  });
}

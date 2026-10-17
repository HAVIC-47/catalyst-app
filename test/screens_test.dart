// The new pages: Wallets (balances, transfers with a fee), Dhar (people, part
// payments, settling), Bills (pay -> expense + next due date, Undo), Settings
// (language, currency, reminders), About the app and the what's-new pop-up.
import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/data/insights.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/about_screen.dart';
import 'package:catalyst/screens/bills_screen.dart';
import 'package:catalyst/screens/dhar_screen.dart';
import 'package:catalyst/screens/settings_screen.dart';
import 'package:catalyst/screens/shell.dart';
import 'package:catalyst/screens/wallets_screen.dart';
import 'package:catalyst/services/updates.dart';
import 'package:catalyst/services/whats_new.dart';
import 'package:catalyst/theme/app_theme.dart';
import 'package:catalyst/theme/palette.dart';
import 'package:catalyst/theme/theme_controller.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/i18n.dart';
import 'package:catalyst/util/money.dart';
import 'package:catalyst/widgets/ai_insights.dart';
import 'package:catalyst/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';
import 'fake_money_db.dart';

const _cash = Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 2000, sort: 0, archived: false);
const _bkash = Wallet(id: 'bk', name: 'bKash', kind: WalletKind.mobile, color: '#E2136E', openingBalance: 5000, sort: 1, archived: false);

FakeApp _app(FakeMoneyDb db) => FakeApp()
  ..loading = false
  ..db = db
  ..walletsReady = true
  ..wallets = [_cash, _bkash]
  ..categories = const [
    Category(id: 'util', name: 'Utilities', kind: Kind.expense, color: '#B59A3C', sort: 0),
    Category(id: 'other', name: 'Other', kind: Kind.expense, color: '#7A746A', sort: 1),
  ];

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
    await setAppLang('en');
    AiInsightsCard.request = ({required topic, required period, required start, required generate}) async =>
        InsightResult.fromJson({'insight': null, 'generatedAt': null, 'stale': false, 'empty': true});
    Updates.readVersion = () async => '1.3.0';
    Updates.fetchLatest = () async => null;
    WhatsNew.readInstall = () async => (version: '1.4.0', updated: false);
  });
  tearDown(() => AiInsightsCard.request = requestInsight);

  testWidgets('Wallets: balances, a total, and moving money with a fee', (tester) async {
    await _tall(tester);
    final db = FakeMoneyDb();
    final app = _app(db);
    await tester.pumpWidget(host(app, const WalletsScreen()));
    await tester.pump();
    expect(find.text('৳7,000 across your wallets'), findsOneWidget);
    expect(find.text('CASH · DEFAULT'), findsOneWidget); // a Label is upper case
    expect(find.text('Move'), findsWidgets);

    // From bKash to Cash: ৳1,000 with a ৳18.50 fee.
    await tester.tap(find.widgetWithText(AppDropdown, 'Cash').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('bKash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppDropdown, 'bKash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();
    final amounts = find.byType(AmountField);
    await tester.enterText(amounts.at(0), '1000');
    await tester.enterText(amounts.at(1), '18.50');
    await tester.pump();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Move'));
    await tester.pumpAndSettle();

    expect(db.calls, contains('addTransfer bk->cash 1000.0'));
    expect(app.transactions.single.amount, 18.5);
    expect(find.text('Moved ৳1,000 from bKash to Cash.'), findsOneWidget);
    // bKash 5000 - 1000 - 18.5; Cash 2000 + 1000.
    expect(find.text('৳3,981.5'), findsOneWidget);
    expect(find.text('৳3,000'), findsOneWidget);
    expect(find.text('৳6,981.5 across your wallets'), findsOneWidget);
  });

  testWidgets('Wallets before the database update explain what to run', (tester) async {
    final app = FakeApp()..loading = false;
    await tester.pumpWidget(host(app, const WalletsScreen()));
    await tester.pump();
    expect(find.textContaining('need a database update'), findsOneWidget);
  });

  testWidgets('Dhar: per person, part payments, settle', (tester) async {
    await _tall(tester);
    final db = FakeMoneyDb();
    final app = _app(db)
      ..debts = const [
        Debt(id: 'd1', person: 'Rahim', direction: DebtDirection.lent, amount: 1000, note: 'Phone', walletId: 'cash', occurredOn: '2026-10-01', dueOn: null, closed: false, createdAt: ''),
        Debt(id: 'd2', person: 'rahim', direction: DebtDirection.borrowed, amount: 300, note: '', walletId: 'bk', occurredOn: '2026-10-03', dueOn: null, closed: false, createdAt: ''),
      ]
      ..debtPayments = const [DebtPayment(id: 'p1', debtId: 'd1', amount: 400, walletId: 'cash', paidOn: '2026-10-05', note: '', createdAt: '')];
    await tester.pumpWidget(host(app, const DharScreen()));
    await tester.pump();
    expect(find.text('owes you ৳300'), findsOneWidget); // 600 still to get back - 300 owed, one person
    expect(find.textContaining('৳600 still to get back', findRichText: true), findsOneWidget);
    expect(find.text('1 payment'), findsOneWidget);

    await tester.tap(find.text('Settle').first);
    await tester.pumpAndSettle();
    expect(db.calls, contains('addDebtPayment d1 600.0'));
    expect(app.debts.firstWhere((d) => d.id == 'd1').closed, isTrue);
    expect(find.text('SETTLED · 1'), findsOneWidget);
  });

  testWidgets('Bills: paying logs the expense and moves the bill on, with Undo', (tester) async {
    await _tall(tester);
    final db = FakeMoneyDb();
    final due = DateTime.now().add(const Duration(days: 2));
    final app = _app(db)
      ..bills = [Bill(id: 'net', name: 'Internet', amount: 1200, dueOn: toDateKey(due), recurrence: 'monthly', isPaid: false)];
    await tester.pumpWidget(host(app, const BillsScreen()));
    await tester.pump();
    expect(find.text('৳1,200 outstanding'), findsOneWidget);
    expect(find.textContaining('Utilities'), findsWidgets);

    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Pay Internet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(app.transactions.single.amount, 1200);
    expect(app.transactions.single.categoryName, 'Utilities');
    expect(find.textContaining('Paid Internet — ৳1,200 added to the ledger.'), findsOneWidget);
    expect(app.bills.single.dueOn, nextDue(toDateKey(due), 'monthly'));

    await tester.pump(const Duration(milliseconds: 750)); // the snack bar slides in
    await tester.tap(find.text('UNDO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(app.transactions, isEmpty);
    expect(app.bills.single.dueOn, toDateKey(due));
  });

  testWidgets('Settings: language, currency and reminders', (tester) async {
    await _tall(tester);
    final app = _app(FakeMoneyDb());
    await tester.pumpWidget(host(app, const SettingsScreen()));
    await tester.pump();
    expect(find.text('Example: ৳1,25,000.5'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppDropdown, '৳ · Bangladeshi taka (BDT)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'C$ · Canadian dollar (CAD)').last);
    await tester.pumpAndSettle();
    expect(app.currency, 'CAD');
    expect(find.text(r'Example: C$125,000.5'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Bills').first);
    await tester.pump();
    expect(app.reminders.bills, isFalse);

    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();
    expect(app.lang, 'bn');
    expect(isBangla, isTrue);
    expect(find.textContaining('ভাষা ও শব্দ', findRichText: true), findsOneWidget);
    expect(find.text(r'উদাহরণ: C$১২৫,০০০.৫'), findsOneWidget);
  });

  testWidgets("Settings → About the app: what's new on top, then every feature", (tester) async {
    tester.view.physicalSize = const Size(1080, 10000); // what's new and the first features at once
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    Updates.current = '1.4.0';
    addTearDown(() => Updates.current = '');
    await tester.pumpWidget(host(_app(FakeMoneyDb()), const SettingsScreen()));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('About the app'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('About the app'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Version 1.4.0 · Android'), findsOneWidget);
    final news = find.text("WHAT'S NEW IN 1.4.0");
    expect(news, findsOneWidget);
    expect(tester.getTopLeft(find.text('Quick entry')).dy, greaterThan(tester.getTopLeft(news).dy));
    final list = find.descendant(of: find.byType(AboutScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('One account, two apps'), 400, scrollable: list);
    expect(find.textContaining('catalyst-hishab.vercel.app'), findsOneWidget);
    // The app's own features (the widget, the SMS reader) — the web lists its own.
    expect(find.text('Home-screen widget'), findsWidgets);
    expect(find.text('bKash / Nagad messages'), findsWidgets);

    await tester.scrollUntilVisible(find.byTooltip('Back'), -400, scrollable: list);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsNothing);
  });

  testWidgets("after an update the shell says what's new once; All features opens About", (tester) async {
    await _tall(tester);
    Updates.current = '1.4.0';
    addTearDown(() => Updates.current = '');
    WhatsNew.readInstall = () async => (version: '1.4.0', updated: true);
    // Not opened from the widget (an unanswered channel would stall the start-up).
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('catalyst/widget'), (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel('catalyst/widget'), null));
    final theme = await ThemeController.load();
    final app = _app(FakeMoneyDb());
    Widget shell() => MultiProvider(
          providers: [ChangeNotifierProvider.value(value: theme), ChangeNotifierProvider<AppState>.value(value: app)],
          child: MaterialApp(theme: buildTheme(Palette.night), home: const AppShell()),
        );

    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewDialog), findsOneWidget);
    expect(find.text('Catalyst 1.4.0'), findsOneWidget);
    expect(find.text('Wallets'), findsWidgets);
    await tester.tap(find.text('All features'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewDialog), findsNothing);
    expect(find.byType(AboutScreen), findsOneWidget);

    // The next launch: already said.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewDialog), findsNothing);
    expect(find.byType(AboutScreen), findsNothing);
  });
}

// 1.5's screens: Recurring (the list, adding one), Streaks & challenges (the
// streak, starting a challenge), Zakat (nisab, what's due, logging it), Settings →
// Notifications (each kind on or off), the dashboard's net worth and streak
// sections, and the new sections in the More sheet.
import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/data/insights.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/about_screen.dart';
import 'package:catalyst/screens/challenges_screen.dart';
import 'package:catalyst/screens/dashboard_screen.dart';
import 'package:catalyst/screens/recurring_screen.dart';
import 'package:catalyst/screens/settings_screen.dart';
import 'package:catalyst/screens/shell.dart';
import 'package:catalyst/screens/zakat_screen.dart';
import 'package:catalyst/services/updates.dart';
import 'package:catalyst/services/whats_new.dart';
import 'package:catalyst/theme/app_theme.dart';
import 'package:catalyst/theme/palette.dart';
import 'package:catalyst/theme/theme_controller.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/i18n.dart';
import 'package:catalyst/util/recurring.dart';
import 'package:catalyst/widgets/ai_insights.dart';
import 'package:catalyst/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';
import 'fake_money_db.dart';

final _now = DateTime.now();
String _day(int ago) => toDateKey(DateTime(_now.year, _now.month, _now.day - ago));

Txn _tx(String id, int ago, double amount, {Kind kind = Kind.expense, String category = 'Food'}) => Txn(
      id: id,
      kind: kind,
      amount: amount,
      categoryId: null,
      categoryName: category,
      place: '',
      note: '',
      occurredOn: _day(ago),
      occurredAt: '',
      createdAt: '',
    );

FakeApp _app(FakeMoneyDb db) => FakeApp()
  ..loading = false
  ..db = db
  ..recurringReady = true
  ..walletsReady = true
  ..wallets = const [Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 150000, sort: 0, archived: false)]
  ..categories = const [
    Category(id: 'salary', name: 'Salary', kind: Kind.income, color: '#2E8159', sort: 0),
    Category(id: 'rent', name: 'Rent', kind: Kind.expense, color: '#7A4E86', sort: 0),
    Category(id: 'food', name: 'Food', kind: Kind.expense, color: '#C06A33', sort: 1),
    Category(id: 'other', name: 'Other', kind: Kind.expense, color: '#7A746A', sort: 2),
  ]
  ..dashboardHidden = [];

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
    await setAppLang('en');
    AppState.deviceTimezone = () async => 'Asia/Dhaka';
    AiInsightsCard.request = ({required topic, required period, required start, required generate}) async =>
        InsightResult.fromJson({'insight': null, 'generatedAt': null, 'stale': false, 'empty': true});
    Updates.readVersion = () async => '1.5.0';
    Updates.fetchLatest = () async => null;
    WhatsNew.readInstall = () async => (version: '1.5.0', updated: false);
  });
  tearDown(() => AiInsightsCard.request = requestInsight);

  testWidgets('Recurring: the list says when each comes next; adding one', (tester) async {
    await _tall(tester);
    final db = FakeMoneyDb();
    final app = _app(db)
      ..recurring = [
        RecurringRule(
          id: 'r1',
          name: 'Salary',
          kind: Kind.income,
          amount: 50000,
          schedule: Schedule(frequency: Frequency.monthly, day1: 1, time: '09:00', startOn: _day(40)),
          nextOn: '2099-01-01',
        ),
      ];
    await tester.pumpWidget(host(app, const RecurringScreen()));
    await tester.pump();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.textContaining('Every month on day 1 · 9:00 AM', findRichText: true), findsOneWidget);
    expect(find.textContaining('next Thu, Jan 1', findRichText: true), findsOneWidget);
    expect(find.text('+৳50,000'), findsOneWidget);
    expect(find.text('About ৳50,000 in and ৳0 out a month'), findsOneWidget);

    await tester.tap(find.text('Add a recurring entry'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringSheet), findsOneWidget);
    await tester.tap(find.text('Expense').last);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Name (e.g. Rent, Netflix)'), 'Netflix');
    await tester.enterText(find.byType(AmountField), '1200');
    await tester.pump();
    expect(find.textContaining('Next:'), findsOneWidget);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.byType(RecurringSheet), findsNothing);
    expect(db.calls.where((c) => c.startsWith('addRecurring Netflix')), hasLength(1));
    final made = app.recurring.last;
    expect((made.kind, made.amount, made.schedule.frequency, made.schedule.day1, made.tz), (Kind.expense, 1200.0, Frequency.monthly, 1, 'Asia/Dhaka'));
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('−৳1,200'), findsOneWidget);
  });

  testWidgets('Streaks & challenges: the streak, and starting a challenge', (tester) async {
    await _tall(tester);
    final db = FakeMoneyDb();
    final app = _app(db)..transactions = [_tx('a', 0, 100), _tx('b', 1, 100), _tx('c', 2, 100)];
    await tester.pumpWidget(host(app, const ChallengesScreen()));
    await tester.pump();
    expect(find.text('3-day streak'), findsOneWidget);
    expect(find.text("Today's logged — see you tomorrow."), findsOneWidget);
    expect(find.text('No challenges yet. A week of no-spend days is a good start.'), findsOneWidget);

    await tester.tap(find.text('Start a challenge'));
    await tester.pumpAndSettle();
    expect(find.byType(ChallengeSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Start'));
    await tester.pumpAndSettle();
    expect(db.calls, contains('addChallenge no_spend'));
    expect(find.text('4 no-spend days in 7 days'), findsOneWidget);
    expect(find.text('0 of 4 no-spend days'), findsOneWidget);
    expect(find.text('7 days left'), findsOneWidget);
  });

  testWidgets('Zakat: the nisab from the silver price, what is due, and logging it', (tester) async {
    await _tall(tester);
    final app = _app(FakeMoneyDb());
    await tester.pumpWidget(host(app, const ZakatScreen()));
    await tester.pump();
    expect(find.text('Add the price above to check it against the nisab.'), findsOneWidget);
    expect(find.text('52.5 bhori of silver'), findsOneWidget);

    final silverPrice = find.descendant(of: find.widgetWithText(FieldBlock, "TODAY'S PRICE PER BHORI").last, matching: find.byType(TextField));
    await tester.enterText(silverPrice, '2000');
    await tester.pump();
    expect(app.zakat.silverPrice, 2000);
    expect(find.text('52.5 bhori of silver = ৳1,05,000'), findsOneWidget);
    expect(find.text('৳3,750'), findsOneWidget); // 2.5% of the wallets' ৳1,50,000
    expect(find.text("At or above the nisab — due once you've held it for a lunar year."), findsOneWidget);

    await tester.tap(find.text('Log it as paid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    final t = app.transactions.single;
    expect((t.amount, t.categoryName, t.note), (3750.0, 'Other', 'Zakat'));
    expect(find.text('Zakat of ৳3,750 added to the ledger.'), findsOneWidget);
  });

  testWidgets('Settings → Notifications: every kind, each on or off', (tester) async {
    await _tall(tester);
    final app = _app(FakeMoneyDb());
    await tester.pumpWidget(host(app, const SettingsScreen()));
    await tester.pump();
    expect(find.text('9 of 9 on · check-in at 9:00 PM'), findsOneWidget);
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    for (final label in ['Evening check-in', 'Bills', 'Budgets', 'Dhar', 'Recurring entries', 'Mood & money', 'Streaks', 'Challenges', 'App updates']) {
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label), findsOneWidget, reason: label);
    }
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Mood & money'));
    await tester.pump();
    expect(app.reminders.moodSpend, isFalse);
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'App updates'));
    await tester.pump();
    expect(app.reminders.updates, isFalse);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('7 of 9 on · check-in at 9:00 PM'), findsOneWidget);
  });

  testWidgets('the dashboard: net worth over time, and the streak with the challenges going', (tester) async {
    await _tall(tester);
    final app = _app(FakeMoneyDb())
      ..transactions = [_tx('in', 40, 20000, kind: Kind.income, category: 'Salary'), _tx('a', 0, 500), _tx('b', 1, 300)]
      ..challenges = [Challenge(id: 'c', kind: ChallengeKind.spendUnder, target: 5000, startOn: _day(1), days: 7)];
    await tester.pumpWidget(host(app, DashboardScreen(onCustomize: () {})));
    await tester.pump();
    expect(find.textContaining('Net worth', findRichText: true), findsWidgets);
    expect(find.text('৳1,69,200'), findsNWidgets(2)); // the one wallet's balance, and net worth: 1,50,000 + 20,000 − 800
    expect(find.text('Wallets ৳1,69,200'), findsOneWidget);
    expect(find.text('2-day streak'), findsOneWidget);
    expect(find.text('Spend under ৳5,000 in 7 days'), findsOneWidget);
    expect(find.text('6 days left'), findsOneWidget);
  });

  testWidgets('the More sheet has Recurring, Challenges and Zakat; the update pop-up can be turned off', (tester) async {
    await _tall(tester);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('catalyst/widget'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('catalyst/sms'), (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('catalyst/widget'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('catalyst/sms'), null);
      Updates.available.value = null;
      Updates.current = '';
    });
    Updates.fetchLatest = () async => {'tag_name': 'v9.9.9', 'draft': false, 'prerelease': false, 'assets': const []};
    final app = _app(FakeMoneyDb())..reminders = const ReminderPrefs(updates: false);
    final theme = await ThemeController.load();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: theme), ChangeNotifierProvider<AppState>.value(value: app)],
      child: MaterialApp(theme: buildTheme(Palette.night), home: const AppShell()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing); // App updates off: no pop-up

    for (final (section, marker) in [('Recurring', 'repeat.'), ('Challenges', 'going.'), ('Zakat', 'worked out.')]) {
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(section).last);
      await tester.pumpAndSettle();
      expect(find.textContaining(marker, findRichText: true), findsOneWidget, reason: section);
    }
  });
}

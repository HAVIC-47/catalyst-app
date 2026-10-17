// Every screen on a small phone (360 dp wide), in Bangla and English: Bengali
// text runs longer, so this catches anything that would overflow or clip.
import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/data/features.dart';
import 'package:catalyst/data/insights.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/about_screen.dart';
import 'package:catalyst/screens/bills_screen.dart';
import 'package:catalyst/screens/boards_screen.dart';
import 'package:catalyst/screens/budgets_screen.dart';
import 'package:catalyst/screens/calendar_screen.dart';
import 'package:catalyst/screens/dashboard_screen.dart';
import 'package:catalyst/screens/dhar_screen.dart';
import 'package:catalyst/screens/entry_sheet.dart';
import 'package:catalyst/screens/goals_screen.dart';
import 'package:catalyst/screens/journal_screen.dart';
import 'package:catalyst/screens/ledger_screen.dart';
import 'package:catalyst/screens/settings_screen.dart';
import 'package:catalyst/screens/shell.dart';
import 'package:catalyst/screens/sms_review_sheet.dart';
import 'package:catalyst/services/sms.dart';
import 'package:catalyst/screens/wallets_screen.dart';
import 'package:catalyst/services/updates.dart';
import 'package:catalyst/services/whats_new.dart';
import 'package:catalyst/theme/app_theme.dart';
import 'package:catalyst/theme/palette.dart';
import 'package:catalyst/theme/theme_controller.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/i18n.dart';
import 'package:catalyst/widgets/ai_insights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';

final _today = DateTime.now();
String _day(int ago) => toDateKey(_today.subtract(Duration(days: ago)));

Txn _txn(String id, Kind kind, double amount, String cat, int ago, {String note = '', String? wallet}) => Txn(
      id: id,
      kind: kind,
      amount: amount,
      categoryId: null,
      categoryName: cat,
      place: ago.isEven ? 'Agora' : '',
      note: note,
      occurredOn: _day(ago),
      occurredAt: '${_day(ago)}T08:00:00.000Z',
      createdAt: '',
      walletId: wallet,
    );

/// A busy month: entries, moods, budgets, goals, bills, wallets, dhar, a board.
FakeApp _app() {
  final app = seeded()
    ..walletsReady = true
    ..categories = [
      for (final (i, c) in defaultExpenseCategories.indexed) Category(id: 'e$i', name: c.$1, kind: Kind.expense, color: c.$2, sort: i),
      for (final (i, c) in defaultIncomeCategories.indexed) Category(id: 'i$i', name: c.$1, kind: Kind.income, color: c.$2, sort: i),
    ]
    ..transactions = [
      for (var i = 0; i < 24; i++) _txn('t$i', Kind.expense, 120.0 + i * 37, defaultExpenseCategories[i % 10].$1, i % 20, note: i % 3 == 0 ? 'lunch with friends' : '', wallet: i.isEven ? 'cash' : 'bk'),
      _txn('in1', Kind.income, 65000, 'Salary', 3, note: 'October pay', wallet: 'bk'),
      _txn('sv1', Kind.saving, 5000, 'Saving', 5),
    ]
    ..moods = [
      for (var i = 0; i < 12; i++)
        MoodLog(id: 'm$i', mood: 1 + i % 5, note: '', tags: [moodTags[i % moodTags.length]], loggedOn: _day(i), loggedAt: '${_day(i)}T15:00:00.000Z', createdAt: ''),
    ]
    ..budgets = const [Budget(id: 'b1', categoryId: 'e0', categoryName: 'Food', amount: 3000, period: 'monthly')]
    ..goals = [Goal(id: 'g1', title: 'New laptop', targetAmount: 120000, savedAmount: 35000, dueOn: _day(-90))]
    ..bills = [
      Bill(id: 'bl1', name: 'Internet', amount: 1200, dueOn: _day(2), recurrence: 'monthly', isPaid: false, walletId: 'bk'),
      Bill(id: 'bl2', name: 'Electricity', amount: 2450, dueOn: _day(-1), recurrence: 'monthly', isPaid: false),
    ]
    ..wallets = const [
      Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 12000, sort: 0, archived: false),
      Wallet(id: 'bk', name: 'bKash', kind: WalletKind.mobile, color: '#E2136E', openingBalance: 3400, sort: 1, archived: false),
      Wallet(id: 'ng', name: 'Nagad', kind: WalletKind.mobile, color: '#F26522', openingBalance: 0, sort: 2, archived: false),
      Wallet(id: 'bank', name: 'Bank', kind: WalletKind.bank, color: '#3D80BC', openingBalance: 250000, sort: 3, archived: false),
    ]
    ..transfers = [
      Transfer(id: 'tr1', fromWallet: 'bk', toWallet: 'cash', amount: 1000, note: 'Cash out', occurredOn: _day(4), occurredAt: '', createdAt: ''),
    ]
    ..debts = [
      Debt(id: 'd1', person: 'Rafi', direction: DebtDirection.lent, amount: 2000, note: 'Phone repair', walletId: 'cash', occurredOn: _day(9), dueOn: _day(-1), closed: false, createdAt: ''),
      Debt(id: 'd2', person: 'Mitu', direction: DebtDirection.borrowed, amount: 800, note: '', walletId: 'bk', occurredOn: _day(3), dueOn: null, closed: false, createdAt: ''),
    ]
    ..debtPayments = [DebtPayment(id: 'p1', debtId: 'd1', amount: 500, walletId: 'bk', paidOn: _day(2), note: '', createdAt: '')]
    ..dashboardHidden = [];
  return app;
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _host(AppState app, Widget child) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Palette.light), home: Scaffold(body: child)),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
    await setAppLang('bn');
    AiInsightsCard.request = ({required topic, required period, required start, required generate}) async => InsightResult.fromJson({
          'insight': {
            'headline': 'খরচ নিয়ন্ত্রণে আছে',
            'summary': 'এ মাসে খাবারে সবচেয়ে বেশি খরচ হয়েছে, তবে মোটামুটি ঠিক আছে।',
            'highlights': ['বাজারে খরচ কমেছে'],
            'suggestions': [
              {'title': 'বাইরে খাওয়া কমান', 'detail': 'সপ্তাহে দুই দিন কম খেলেই অনেকটা বাঁচবে।'},
            ],
          },
          'generatedAt': DateTime.now().toIso8601String(),
          'stale': false,
          'empty': false,
        });
    Updates.current = '';
    Updates.readVersion = () async => '1.4.0';
    Updates.fetchLatest = () async => null;
    WhatsNew.readInstall = () async => (version: '1.4.0', updated: false);
  });
  tearDown(() async {
    AiInsightsCard.request = requestInsight;
    await setAppLang('en');
  });

  final screens = <String, Widget Function()>{
    'calendar': () => const CalendarScreen(),
    'dashboard': () => DashboardScreen(onCustomize: () {}),
    'ledger': () => const LedgerScreen(),
    'journal': () => const JournalScreen(),
    'to-do board': () => const BoardsScreen(kind: BoardKind.todo),
    'budgets': () => const BudgetsScreen(),
    'goals': () => const GoalsScreen(),
    'bills': () => const BillsScreen(),
    'wallets': () => const WalletsScreen(),
    'dhar': () => const DharScreen(),
    'settings': () => const SettingsScreen(),
    'about the app': () => const AboutScreen(),
  };

  for (final lang in ['bn', 'en']) {
    for (final MapEntry(key: name, value: build) in screens.entries) {
      testWidgets('$name fits a small phone (${lang == 'bn' ? 'Bangla' : 'English'})', (tester) async {
        await setAppLang(lang);
        await _phone(tester);
        await tester.pumpWidget(_host(_app(), build()));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(seconds: 1));
        // Scroll through the whole page so everything below the fold lays out too.
        final list = find.byType(Scrollable);
        if (list.evaluate().isNotEmpty) {
          for (var i = 0; i < 12; i++) {
            await tester.drag(list.first, const Offset(0, -500), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 50));
          }
        }
        final error = tester.takeException();
        if (error is FlutterError) debugPrint(error.toStringDeep()); // which widget, if one overflows
        expect(error, isNull);
      });
    }
  }

  for (final lang in ['bn', 'en']) {
    testWidgets("every settings page fits a small phone (${lang == 'bn' ? 'Bangla' : 'English'})", (tester) async {
      await setAppLang(lang);
      await _phone(tester);
      await tester.pumpWidget(_host(_app(), const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 50));
      for (final page in SettingsPage.values) {
        openSettingsPage(tester.element(find.byType(SettingsScreen)), page);
        await tester.pumpAndSettle();
        for (var i = 0; i < 8; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -500), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 50));
        }
        final error = tester.takeException();
        if (error is FlutterError) debugPrint('$page: ${error.toStringDeep()}');
        expect(error, isNull, reason: '$page');
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets("the what's-new pop-up fits a small phone (${lang == 'bn' ? 'Bangla' : 'English'})", (tester) async {
      await setAppLang(lang);
      await _phone(tester);
      late BuildContext context;
      await tester.pumpWidget(_host(_app(), Builder(builder: (c) {
        context = c;
        return const SizedBox();
      })));
      showWhatsNew(context, releases());
      await tester.pumpAndSettle();
      expect(find.byType(WhatsNewDialog), findsOneWidget);
      final list = find.descendant(of: find.byType(WhatsNewDialog), matching: find.byType(Scrollable)).first;
      for (var i = 0; i < 6; i++) {
        await tester.drag(list, const Offset(0, -400), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 50));
      }
      final error = tester.takeException();
      if (error is FlutterError) debugPrint(error.toStringDeep());
      expect(error, isNull);
      expect(find.text(lang == 'bn' ? 'সব ফিচার' : 'All features'), findsOneWidget);
    });
  }

  testWidgets('the shell, the More sheet and the new-entry sheet in Bangla', (tester) async {
    await _phone(tester);
    final theme = await ThemeController.load();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: theme), ChangeNotifierProvider<AppState>.value(value: _app())],
      child: MaterialApp(theme: buildTheme(Palette.night), home: const AppShell()),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('ক্যালেন্ডার'), findsOneWidget);
    await tester.tap(find.text('আরও'));
    await tester.pumpAndSettle();
    expect(find.text('ওয়ালেট'), findsOneWidget);
    expect(find.text('ধার'), findsOneWidget);
    await tester.tap(find.text('নতুন এন্ট্রি'));
    await tester.pumpAndSettle();
    expect(find.text('পরিমাণ'), findsWidgets);
    for (final tab in ['মুড', 'সঞ্চয়']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(EntrySheet), findsOneWidget);
  });

  testWidgets('the sheets in Bangla: add wallet, edit bill, dhar payment, SMS review', (tester) async {
    await _phone(tester);
    final app = _app();
    Future<void> settle() async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // A fresh app for each screen (a sheet left open would otherwise stay on top).
    Future<void> show(Widget screen) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(app, screen));
      await settle();
    }

    await show(const WalletsScreen());
    // Below the four wallet cards: scroll it into view first.
    await tester.scrollUntilVisible(find.text('ওয়ালেট যোগ করুন'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('ওয়ালেট যোগ করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ওয়ালেট যোগ করুন'));
    await settle();
    expect(find.text('নতুন ওয়ালেট'), findsOneWidget);

    await show(const BillsScreen());
    await tester.scrollUntilVisible(find.byTooltip('Internet এডিট করুন'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byTooltip('Internet এডিট করুন'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Internet এডিট করুন'));
    await settle();
    expect(find.text('বিল এডিট'), findsOneWidget);

    await show(const DharScreen());
    await tester.scrollUntilVisible(find.text('কিছু ফেরত পেয়েছি'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('কিছু ফেরত পেয়েছি'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('কিছু ফেরত পেয়েছি'));
    await settle();
    expect(find.text('লিখে রাখুন'), findsOneWidget);

    final now = DateTime.now();
    final messages = [
      parseSms('Payment Tk 350.00 to Daraz successful. Fee Tk 0.00. TrxID BJ72AB3C4D at ${fmt(now, 'dd/MM/yyyy HH:mm')}', address: 'bKash', received: now, smsId: '1')!,
      parseSms('Cash Out Tk 1,000.00 to 01612345678 successful. Fee Tk 18.50. TrxID BJ74QR7S8T at ${fmt(now, 'dd/MM/yyyy HH:mm')}', address: 'bKash', received: now, smsId: '2')!,
      parseSms('Money Received.\nAmount: Tk 300.00\nSender: 01812345678\nTxnID: 7A2B3C4D\nBalance: Tk 1,050.00', address: 'NAGAD', received: now, smsId: '3')!,
    ];
    await show(Builder(builder: (context) => TextButton(onPressed: () => openSmsReview(context, messages), child: const Text('open'))));
    await tester.tap(find.text('open'));
    await settle();
    expect(find.text('৩টি যোগ করুন'), findsOneWidget);
  });
}

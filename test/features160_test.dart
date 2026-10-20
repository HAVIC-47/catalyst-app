// 1.6: category icons, the dashboard's and the categories' order, the wallet a
// scan was paid from, live gold and silver prices, the light palette (moods,
// vivid colors, contrast), Remember me and the password eye.
import 'dart:math';

import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/data/metal_prices.dart';
import 'package:catalyst/data/remember.dart';
import 'package:catalyst/data/scan.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/auth_screen.dart';
import 'package:catalyst/screens/dashboard_screen.dart';
import 'package:catalyst/screens/memo_sheet.dart';
import 'package:catalyst/screens/settings_screen.dart';
import 'package:catalyst/screens/zakat_screen.dart';
import 'package:catalyst/theme/app_theme.dart';
import 'package:catalyst/theme/palette.dart';
import 'package:catalyst/theme/theme_controller.dart';
import 'package:catalyst/util/category_icons.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/money.dart';
import 'package:catalyst/util/zakat.dart';
import 'package:catalyst/widgets/net_worth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';

Wallet _wallet(String id, String name, WalletKind kind, {bool archived = false}) =>
    Wallet(id: id, name: name, kind: kind, color: '#3D80BC', openingBalance: 0, sort: 0, archived: archived);

const _wallets = [
  Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 5000, sort: 0, archived: false),
  Wallet(id: 'bk', name: 'bKash', kind: WalletKind.mobile, color: '#E2136E', openingBalance: 2000, sort: 1, archived: false),
  Wallet(id: 'ng', name: 'Nagad', kind: WalletKind.mobile, color: '#F26522', openingBalance: 0, sort: 2, archived: false),
  Wallet(id: 'bank', name: 'City Bank', kind: WalletKind.bank, color: '#3D80BC', openingBalance: 90000, sort: 3, archived: false),
];

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// The settings page [page], opened from the hub as the app does.
Future<void> _openSettings(WidgetTester tester, AppState app, SettingsPage page) async {
  await tester.pumpWidget(host(app, const SettingsScreen()));
  openSettingsPage(tester.element(find.byType(SettingsScreen)), page);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
  });

  group('category icons', () {
    test('picked from the name, in English and Bangla', () {
      expect(categoryIconName('Food'), 'utensils');
      expect(categoryIconName('Transport'), 'bus'); // not "sport"
      expect(categoryIconName('Personal Care'), 'sparkles'); // not a car
      expect(categoryIconName('Rent'), 'house');
      expect(categoryIconName('Salary'), 'briefcase');
      expect(categoryIconName(breakSaving), 'piggy-bank');
      expect(categoryIconName('বাজার'), 'shopping-basket');
      expect(categoryIconName('যাতায়াত'), 'bus');
      expect(categoryIconName('Others'), 'circle-ellipsis');
      expect(categoryIconName('Xyz'), 'tag');
    });

    test("a chosen icon wins; a name that isn't one of ours falls back to the name's", () {
      expect(categoryIconName('Food', 'gamepad-2'), 'gamepad-2');
      expect(categoryIconName('Food', 'not-an-icon'), 'utensils');
      expect(categoryIcon('Food'), LucideIcons.utensils);
    });

    test('every default category gets a real icon', () {
      for (final (name, _) in [...defaultExpenseCategories, ...defaultIncomeCategories]) {
        expect(categoryIconName(name), isNot('tag'), reason: name);
      }
    });
  });

  test("the dashboard's order: known sections only, and new ones after their usual neighbour", () {
    final all = [for (final s in dashboardSections) s.$1];
    expect(orderDashboardSections(null), all);
    expect(orderDashboardSections('nonsense'), all);
    final custom = orderDashboardSections(['categories', 'kpis', 'bogus', 'kpis']);
    expect(custom.length, all.length);
    expect(custom.take(2), ['categories', 'kpis']);
    // An order saved before "netWorth" existed: it goes right after "wallets".
    final saved = ([...all]..remove('netWorth')).reversed.toList();
    final placed = orderDashboardSections(saved);
    expect(placed.indexOf('netWorth'), placed.indexOf('wallets') + 1);
  });

  test('the wallet a scan was paid from: by name, or by kind', () {
    final wallets = [..._wallets, _wallet('old', 'Rocket', WalletKind.mobile, archived: true)];
    expect(walletForPayment('bkash', wallets)?.id, 'bk');
    expect(walletForPayment('nagad', wallets)?.id, 'ng');
    expect(walletForPayment('cash', wallets)?.id, 'cash');
    expect(walletForPayment('bank', wallets)?.id, 'bank');
    expect(walletForPayment('card', wallets)?.id, 'bank'); // no card: the bank account it's drawn on
    expect(walletForPayment('rocket', wallets), isNull); // archived
    expect(walletForPayment('upay', wallets), isNull);
    expect(walletForPayment('', wallets), isNull);
    expect(walletForPayment(null, wallets), isNull);
    expect(walletForPayment('bkash', [_wallet('b', 'বিকাশ', WalletKind.mobile)])?.id, 'b');
    expect(walletForPayment('card', [..._wallets, _wallet('visa', 'My Visa', WalletKind.card)])?.id, 'visa');
  });

  group('zakat at live prices', () {
    const live = (gold: 15000.0, silver: 180.0); // per gram

    test('per unit, from per-gram prices — or the typed ones', () {
      const z = ZakatInputs();
      expect(pricesOf(z, live).gold, closeTo(15000 * 11.664, 0.01));
      expect(pricesOf(z.copyWith(unit: 'g'), live).silver, 180);
      expect(pricesOf(z.copyWith(autoPrices: false, goldPrice: 99), live).gold, 99);
      expect(pricesOf(z, null).silver, 0); // not loaded yet
    });

    test('gold counts by its purity; the nisab is pure metal', () {
      const z = ZakatInputs(unit: 'g', gold: 10, karat: 22, basis: 'gold', useWallets: false, useDhar: false);
      final r = zakatOf(z, wallets: 0, owedToYou: 0, youOwe: 0, live: live);
      expect(r.goldValue, closeTo(10 * 15000 * 22 / 24, 0.01));
      expect(r.nisab, closeTo(87.48 * 15000, 0.01));
      expect(r.above, isFalse);
      final rich = zakatOf(z.copyWith(gold: 100, karat: 24), wallets: 0, owedToYou: 0, youOwe: 0, live: live);
      expect(rich.above, isTrue);
      expect(rich.due, closeTo(100 * 15000 * 0.025, 0.01));
    });

    test('figures saved by 1.5 get live prices and 22K; bad purities are dropped', () {
      final z = ZakatInputs.fromJson({'goldPrice': 185000, 'gold': 2});
      expect((z.autoPrices, z.karat, z.goldPrice), (true, 22, 185000.0));
      expect(ZakatInputs.fromJson({'karat': 21, 'autoPrices': false}).karat, 21);
      expect(ZakatInputs.fromJson({'karat': 23}).karat, 22);
      expect(ZakatInputs.fromJson(z.toJson()).toJson(), z.toJson());
    });
  });

  group('the light palette', () {
    test('moods per theme', () {
      expect(Palette.light.mood(1), const Color(0xFFE11D48));
      expect(Palette.night.mood(5), const Color(0xFF2E8159));
      expect(Palette.light.mood(0), Palette.light.mood(1));
      expect(Palette.light.mood(9), Palette.light.mood(5));
    });

    test('stored colors get livelier on light paper, and stay as they are at night', () {
      const brick = Color(0xFFC06A33);
      expect(Palette.night.vivid(brick), brick);
      expect(HSLColor.fromColor(Palette.light.vivid(brick)).saturation, greaterThan(HSLColor.fromColor(brick).saturation));
    });

    test('readable: text 4.5:1, moods and marks 3:1', () {
      final p = Palette.light;
      expect(_contrast(p.ink, p.paper), greaterThanOrEqualTo(4.5));
      expect(_contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
      for (final c in [p.income, p.expense, p.saving, p.violetText]) {
        expect(_contrast(c, p.card), greaterThanOrEqualTo(4.5), reason: '$c');
      }
      for (var m = 1; m <= 5; m++) {
        expect(_contrast(p.mood(m), p.card), greaterThanOrEqualTo(3), reason: 'mood $m');
      }
    });
  });

  test('Remember me off: forgotten after five minutes away, never while on', () async {
    expect(await RememberMe.isOn(), isTrue);
    await RememberMe.away();
    expect(await RememberMe.expired(), isFalse);
    await RememberMe.set(false);
    await RememberMe.away();
    expect(await RememberMe.expired(), isFalse); // back at once
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('awaySince', DateTime.now().subtract(const Duration(minutes: 6)).millisecondsSinceEpoch);
    expect(await RememberMe.expired(), isTrue);
    expect(await RememberMe.expired(), isTrue); // until the next sign-in
    await RememberMe.set(false);
    expect(await RememberMe.expired(), isFalse);
    await RememberMe.set(true);
    await RememberMe.away();
    expect(prefs.getInt('awaySince'), isNull);
  });

  testWidgets('the login screen: Remember me as last chosen, and the eye shows the password', (tester) async {
    SharedPreferences.setMockInitialValues({'remember': false});
    final theme = await ThemeController.load();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: theme), ChangeNotifierProvider<AppState>.value(value: FakeApp()..loading = false)],
      child: MaterialApp(theme: buildTheme(Palette.light), home: const AuthScreen()),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    await tester.tap(find.text('Remember me'));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    final password = find.byType(TextField).at(1);
    await tester.enterText(password, 'secret123');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isTrue);
  });

  testWidgets('Settings → Dashboard: arrows and dragging put the sections in order; Default order puts them back', (tester) async {
    await _tall(tester);
    final app = FakeApp()
      ..loading = false
      ..dashboardHidden = [];
    await _openSettings(tester, app, SettingsPage.dashboard);
    expect(find.text('DEFAULT ORDER'), findsNothing);

    await tester.tap(find.byTooltip('Move Monthly summary down'));
    await tester.pumpAndSettle();
    expect(app.dashboardOrder.take(2), ['trend', 'kpis']);
    await tester.tap(find.byTooltip('Move Monthly summary up'));
    await tester.pumpAndSettle();
    expect(app.dashboardOrder.first, 'kpis');

    // Drag the first row down by its handle, past the next two.
    final gesture = await tester.startGesture(tester.getCenter(find.byIcon(LucideIcons.gripVertical).first));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 14));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(app.dashboardOrder.indexOf('kpis'), greaterThan(0));
    expect(app.dashboardOrder.toSet(), {for (final s in dashboardSections) s.$1});

    await tester.tap(find.text('DEFAULT ORDER'));
    await tester.pumpAndSettle();
    expect(app.dashboardOrder, [for (final s in dashboardSections) s.$1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dashboard follows the order', (tester) async {
    await _tall(tester);
    final app = FakeApp()
      ..loading = false
      ..walletsReady = true
      ..wallets = _wallets
      // Just the two compared, so both are on screen.
      ..dashboardHidden = [for (final s in dashboardSections) if (s.$1 != 'habits' && s.$1 != 'netWorth') s.$1]
      ..dashboardOrder = orderDashboardSections(['habits', 'netWorth']);
    await tester.pumpWidget(host(app, DashboardScreen(onCustomize: () {})));
    await tester.pump();
    expect(tester.getTopLeft(find.byType(HabitsStrip)).dy, lessThan(tester.getTopLeft(find.byType(NetWorthCard)).dy));
    app.dashboardOrder = orderDashboardSections(null);
    app.notifyListeners();
    await tester.pump();
    expect(tester.getTopLeft(find.byType(NetWorthCard)).dy, lessThan(tester.getTopLeft(find.byType(HabitsStrip)).dy));
  });

  testWidgets('Settings → Expense categories: an icon from the picker, back to Auto, and the arrows', (tester) async {
    await _tall(tester);
    final app = FakeApp()
      ..loading = false
      ..categories = const [
        Category(id: 'a', name: 'Food', kind: Kind.expense, color: '#C06A33', sort: 0),
        Category(id: 'b', name: 'Rent', kind: Kind.expense, color: '#2E8159', sort: 1),
      ];
    await _openSettings(tester, app, SettingsPage.expenseCategories);
    // Until one is chosen, the icon comes from the name.
    expect(find.byIcon(LucideIcons.utensils), findsOneWidget);
    expect(find.byIcon(LucideIcons.house), findsOneWidget);

    await tester.tap(find.byTooltip('Change the icon of Food'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('gamepad 2'));
    await tester.tap(find.byTooltip('gamepad 2'));
    await tester.pumpAndSettle();
    expect(app.categories.firstWhere((c) => c.id == 'a').icon, 'gamepad-2');
    expect(find.byIcon(LucideIcons.gamepad2), findsOneWidget); // the picker closed; the badge shows it

    await tester.tap(find.byTooltip('Change the icon of Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Auto — from the name'));
    await tester.pumpAndSettle();
    expect(app.categories.firstWhere((c) => c.id == 'a').icon, isNull);

    await tester.tap(find.byTooltip('Move Rent up'));
    await tester.pumpAndSettle();
    expect([for (final c in app.categories) c.name], ['Rent', 'Food']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bKash screenshot starts in the bKash wallet, and says so', (tester) async {
    await _tall(tester);
    final pick = Scan.pick, send = Scan.send;
    addTearDown(() {
      Scan.pick = pick;
      Scan.send = send;
    });
    final app = seeded()
      ..walletsReady = true
      ..wallets = _wallets
      ..categories = const [Category(id: 'other', name: 'Other', kind: Kind.expense, color: '#7A746A', sort: 0)];
    Scan.pick = (_) async => png;
    Scan.send = (path, body) async => {
          'memo': {
            'merchant': 'Daraz',
            'date': '',
            'time': '',
            'currency': 'BDT',
            'paidWith': 'bkash',
            'items': [
              {'name': 'Payment', 'amount': 1200, 'category': 'Other'},
            ],
            'extras': [],
            'discount': 0,
            'total': 1200,
          },
        };
    await tester.pumpWidget(host(app, Builder(builder: (c) => TextButton(onPressed: () => openMemoScanner(c), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo or screenshot'));
    await tester.pumpAndSettle();
    expect(find.text('Paid with bKash — picked from the image.'), findsOneWidget);
    await tester.tap(find.text('Add 1 expense'));
    await tester.pumpAndSettle();
    expect(app.transactions.single.walletId, 'bk');
  });

  testWidgets("Zakat: today's prices fill in, gold counts by its purity", (tester) async {
    await _tall(tester);
    metalPrices = (_) async => (prices: (gold: 15000.0, silver: 180.0), updatedAt: DateTime(2026, 10, 20, 9, 30));
    addTearDown(() => metalPrices = fetchMetalPrices);
    final app = FakeApp()
      ..loading = false
      ..zakat = const ZakatInputs(unit: 'g', gold: 10, useWallets: false, useDhar: false);
    await tester.pumpWidget(host(app, const ZakatScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.text('Gold (24K) and silver, updated Oct 20, 9:30 AM.'), findsOneWidget);
    expect(find.text('Live'), findsNWidgets(2));
    expect(find.text(formatCurrency(15000)), findsOneWidget); // gold, per gram
    expect(find.text(formatCurrency(180)), findsOneWidget); // silver
    // 10 g of 22K gold is worth 22/24 of pure gold's price.
    expect(find.text(formatCurrency(10 * 15000 * 22 / 24)), findsWidgets); // what you have, and what's counted
    await tester.ensureVisible(find.text('24K'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24K'));
    await tester.pump();
    expect(app.zakat.karat, 24);
    expect(find.text(formatCurrency(150000)), findsWidgets);

    // Off: the typed prices again.
    await tester.ensureVisible(find.text("Today's international prices"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Today's international prices"));
    await tester.pump();
    expect(app.zakat.autoPrices, isFalse);
    expect(find.text('Live'), findsNothing);
    expect(find.text('Off — you type the prices below.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // the save to the account
  });
}

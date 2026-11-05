// Settings → Account → Signed-in devices: what each login is called, removing one,
// signing out of all of them, and the login screen saying why it's there.
import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/data/devices.dart';
import 'package:catalyst/screens/auth_screen.dart';
import 'package:catalyst/screens/settings_screen.dart';
import 'package:catalyst/theme/app_theme.dart';
import 'package:catalyst/theme/palette.dart';
import 'package:catalyst/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';

Map<String, dynamic> _row(String id, {String name = '', String platform = '', String agent = '', bool current = false}) => {
      'session_id': id,
      'name': name,
      'platform': platform,
      'user_agent': agent,
      'signed_in_at': '2026-10-01T08:00:00Z',
      'last_seen': '2026-11-04T08:00:00Z',
      'is_current': current,
    };

class _App extends FakeApp {
  int everywhere = 0;
  int here = 0;
  Object? fails;

  @override
  Future<void> signOutEverywhere() async {
    if (fails != null) throw fails!;
    everywhere++;
  }

  @override
  Future<void> signOut() async => here++;
}

void main() {
  final list = Devices.list, remove = Devices.remove, touch = Devices.touch;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    Devices.list = list;
    Devices.remove = remove;
    Devices.touch = touch;
    Devices.removedHere = false;
  });

  group('what a login is called', () {
    test('a browser is named from its user agent', () {
      const cases = {
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36': 'Chrome · Windows',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0': 'Edge · Windows',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15': 'Safari · Mac',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1': 'Safari · iPhone',
        'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36': 'Chrome · Android',
        'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/25.0 Chrome/121.0.0.0 Mobile Safari/537.36': 'Samsung Internet · Android',
        'Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0': 'Firefox · Linux',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 OPR/115.0.0.0': 'Opera · Windows',
        'node': '',
        'Dart/3.13 (dart:io)': '',
        '': '',
      };
      cases.forEach((ua, name) => expect(browserName(ua), name, reason: ua));
    });

    test('a login goes by its own name first', () {
      final d = DeviceLogin.fromRow(_row('a', name: 'Samsung SM-S918B', platform: 'android', agent: 'node', current: true));
      expect((d.id, d.label, d.onPhone, d.current), ('a', 'Samsung SM-S918B', true, true));
      expect(d.signedInAt.isUtc, isFalse); // shown in local time
    });

    test('one that never named itself goes by what its user agent says', () {
      expect(DeviceLogin.fromRow(_row('a', agent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/130.0 Safari/537.36')).label, 'Chrome · Windows');
      final old = DeviceLogin.fromRow(_row('b', agent: 'Dart/3.11 (dart:io)'));
      expect((old.label, old.onPhone), ('Android phone', true));
      final phone = DeviceLogin.fromRow(_row('c', agent: 'Mozilla/5.0 (Linux; Android 14) Chrome/130.0 Mobile Safari/537.36'));
      expect((phone.label, phone.onPhone), ('Chrome · Android', true));
      final none = DeviceLogin.fromRow(_row('d', agent: 'node'));
      expect((none.label, none.onPhone), ('Unknown device', false));
    });

    test('a named login with a server\'s user agent keeps its name', () {
      final d = DeviceLogin.fromRow(_row('a', name: 'Edge · Windows', platform: 'web', agent: 'node'));
      expect((d.label, d.onPhone), ('Edge · Windows', false));
    });
  });

  group('the list', () {
    final rows = [
      DeviceLogin.fromRow(_row('me', name: 'Samsung SM-S918B', platform: 'android', current: true)),
      DeviceLogin.fromRow(_row('web', name: 'Chrome · Windows', platform: 'web')),
      DeviceLogin.fromRow(_row('old', agent: 'node')),
    ];

    Future<_App> open(WidgetTester tester, {Future<List<DeviceLogin>> Function()? load}) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Devices.touch = () async {};
      Devices.list = load ?? () async => [...rows];
      final app = _App()..loading = false;
      await tester.pumpWidget(host(app, Builder(builder: (c) => TextButton(onPressed: () => openSettingsPage(c, SettingsPage.account), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return app;
    }

    Finder rowOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(Row)).first;

    testWidgets('shows every login, this one marked, each with its way out', (tester) async {
      var touched = 0;
      await open(tester, load: () async {
        touched++;
        return [...rows];
      });
      expect(touched, 1);
      expect(find.text('Signed-in devices'), findsOneWidget);
      expect(find.text('Samsung SM-S918B'), findsOneWidget);
      expect(find.text('Chrome · Windows'), findsOneWidget);
      expect(find.text('Unknown device'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.textContaining('Active now'), findsOneWidget);
      expect(find.textContaining('Last active Nov 4'), findsNWidgets(2));
      expect(find.text('Remove'), findsNWidgets(2));
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Sign out of all devices'), findsOneWidget);
    });

    testWidgets('names itself before listing, so its own row is never unknown', (tester) async {
      final order = <String>[];
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Devices.touch = () async => order.add('touch');
      Devices.list = () async {
        order.add('list');
        return [...rows];
      };
      await tester.pumpWidget(host(_App()..loading = false, Builder(builder: (c) => TextButton(onPressed: () => openSettingsPage(c, SettingsPage.account), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(order, ['touch', 'list']);
    });

    testWidgets('Remove asks first, and only that login goes', (tester) async {
      final removed = <String>[];
      Devices.remove = (id) async => removed.add(id);
      await open(tester);
      await tester.tap(find.descendant(of: rowOf('Chrome · Windows'), matching: find.text('Remove')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out of Chrome · Windows? It will have to log in again.'), findsOneWidget);
      expect(removed, isEmpty);
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(removed, ['web']);
      expect(find.text('Chrome · Windows'), findsNothing);
      expect(find.text('Samsung SM-S918B'), findsOneWidget);
      expect(find.text('Unknown device'), findsOneWidget);
    });

    testWidgets('saying no keeps it', (tester) async {
      final removed = <String>[];
      Devices.remove = (id) async => removed.add(id);
      await open(tester);
      await tester.tap(find.descendant(of: rowOf('Chrome · Windows'), matching: find.text('Remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(removed, isEmpty);
      expect(find.text('Chrome · Windows'), findsOneWidget);
    });

    testWidgets('a removal that fails says so, and the row stays', (tester) async {
      Devices.remove = (_) async => throw Exception('no');
      await open(tester);
      await tester.tap(find.descendant(of: rowOf('Chrome · Windows'), matching: find.text('Remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't remove Chrome · Windows — try again."), findsOneWidget);
      expect(find.text('Chrome · Windows'), findsOneWidget);
    });

    testWidgets('this device\'s own Sign out is just this one, without asking', (tester) async {
      final app = await open(tester);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect((app.here, app.everywhere), (1, 0));
    });

    testWidgets('Sign out of all devices asks first', (tester) async {
      final app = await open(tester);
      await tester.tap(find.text('Sign out of all devices'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out of all devices, including this one?'), findsOneWidget);
      expect(app.everywhere, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.everywhere, 0);

      await tester.tap(find.text('Sign out of all devices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      expect((app.here, app.everywhere), (0, 1));
    });

    testWidgets('with no connection it says so, and stays signed in', (tester) async {
      final app = await open(tester);
      app.fails = Exception('Failed host lookup');
      await tester.tap(find.text('Sign out of all devices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't sign out — check your connection and try again."), findsOneWidget);
      expect(find.text('Remove'), findsNWidgets(2)); // usable again
    });

    testWidgets('before the database update it says so, and signing out of everything still works', (tester) async {
      final app = await open(tester, load: () async => throw Exception('Could not find the function public.my_devices in the schema cache'));
      expect(find.text('This list needs the database update — run db/supabase.sql.'), findsOneWidget);
      await tester.tap(find.text('Sign out of all devices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      expect(app.everywhere, 1);
    });

    testWidgets('a list that can\'t load says so, and Try again tries again', (tester) async {
      var tries = 0;
      await open(tester, load: () async {
        if (++tries == 1) throw Exception('Failed host lookup');
        return [...rows];
      });
      expect(find.text("Couldn't load your devices."), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your devices."), findsNothing);
      expect(find.text('Samsung SM-S918B'), findsOneWidget);
    });
  });

  group('the login screen', () {
    Future<Widget> screen() async {
      final theme = await ThemeController.load();
      return MultiProvider(
        providers: [ChangeNotifierProvider.value(value: theme), ChangeNotifierProvider<AppState>.value(value: FakeApp()..loading = false)],
        child: MaterialApp(theme: buildTheme(Palette.night), home: const AuthScreen()),
      );
    }

    const why = 'You were signed out of this device.';

    testWidgets('says why after this device was removed, once', (tester) async {
      Devices.removedHere = true;
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();
      expect(find.text(why), findsOneWidget);
      expect(Devices.removedHere, isFalse);
    });

    testWidgets('says nothing otherwise', (tester) async {
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();
      expect(find.text(why), findsNothing);
    });
  });
}

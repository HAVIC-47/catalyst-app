// Phone-side helpers: the update check, which reminders get scheduled, the
// home-screen widget's figures, and offline use (the saved copy and the outbox).
import 'dart:async';
import 'dart:io';

import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/data/features.dart';
import 'package:catalyst/data/offline.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/services/notifications.dart';
import 'package:catalyst/services/updates.dart';
import 'package:catalyst/services/whats_new.dart';
import 'package:catalyst/services/widget_sync.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'fake_app.dart';

Map<String, dynamic> _release(String tag, {List<String> assets = const ['Catalyst.apk', 'Catalyst-arm64.apk']}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/HAVIC-47/catalyst-app/releases/tag/$tag',
      'draft': false,
      'prerelease': false,
      'assets': [for (final a in assets) {'name': a, 'browser_download_url': 'https://github.com/HAVIC-47/catalyst-app/releases/download/$tag/$a'}],
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
  });

  group('updates', () {
    tearDown(() {
      Updates.available.value = null;
      Updates.current = '';
    });

    test('versions compare by number, not text', () {
      expect(Updates.isNewer('1.4.0', '1.3.0'), isTrue);
      expect(Updates.isNewer('1.10.0', '1.9.3'), isTrue);
      expect(Updates.isNewer('1.3.0', '1.3.0'), isFalse);
      expect(Updates.isNewer('1.2.9', '1.3.0'), isFalse);
      expect(Updates.isNewer('2.0.0', '1.99.99+7'), isTrue);
    });

    test('a release gives its version and the universal APK', () {
      final u = Updates.parseRelease(_release('v1.4.0'))!;
      expect(u.version, '1.4.0');
      expect(u.url, endsWith('/v1.4.0/Catalyst.apk'));
      expect(Updates.parseRelease({..._release('v1.5.0'), 'prerelease': true}), isNull);
      expect(Updates.parseRelease(_release('nightly')), isNull);
      expect(Updates.parseRelease(_release('v1.4.1', assets: const []))!.url, latestApkUrl);
    });

    test('a newer release shows once, notifies once, and stays dismissed for that version', () async {
      Updates.readVersion = () async => '1.3.0';
      Updates.fetchLatest = () async => _release('v1.4.0');
      final seen = <String>[];
      expect((await Updates.check(force: true, onNew: (u) => seen.add(u.version)))?.version, '1.4.0');
      expect(Updates.available.value?.version, '1.4.0');
      await Updates.check(force: true, onNew: (u) => seen.add(u.version));
      expect(seen, ['1.4.0']);

      await Updates.dismiss(Updates.available.value!);
      expect(Updates.available.value, isNull);
      await Updates.check(); // within the hour: nothing new is fetched, the banner stays away
      expect(Updates.available.value, isNull);
    });

    test('on the latest version there is nothing to show', () async {
      Updates.readVersion = () async => '1.4.0';
      Updates.fetchLatest = () async => _release('v1.4.0');
      expect(await Updates.check(force: true), isNull);
      expect(Updates.available.value, isNull);
    });
  });

  group('update pop-up', () {
    tearDown(() {
      Updates.available.value = null;
      Updates.current = '';
    });

    test('a found update is remembered after a restart, between checks', () async {
      Updates.readVersion = () async => '1.3.0';
      Updates.fetchLatest = () async => _release('v9.9.9');
      expect((await Updates.check(force: true))?.version, '9.9.9');
      // The app restarts within the check interval: nothing is fetched, the update is still known.
      Updates.available.value = null;
      Updates.current = '';
      Updates.fetchLatest = () async => throw StateError('not fetched again so soon');
      expect((await Updates.check())?.version, '9.9.9');
      expect(Updates.available.value?.version, '9.9.9');
    });

    test('it pops up once per version, and again a few days after "Later"', () async {
      const u = UpdateInfo(version: '9.9.9', url: 'https://example.com/a.apk', page: 'https://example.com');
      expect(await Updates.shouldPrompt(u), isTrue);
      await Updates.markPrompted(u);
      expect(await Updates.shouldPrompt(u), isFalse);
      expect(await Updates.shouldPrompt(const UpdateInfo(version: '9.9.10', url: '', page: '')), isTrue);
      final fourDaysAgo = DateTime.now().subtract(const Duration(days: 4)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({'update:prompted': '9.9.9|$fourDaysAgo'});
      expect(await Updates.shouldPrompt(u), isTrue);
    });
  });

  group("what's new", () {
    Future<List<String>> due(String version, {bool updated = true}) async {
      WhatsNew.readInstall = () async => (version: version, updated: updated);
      return [for (final r in await WhatsNew.due()) r.version];
    }

    test('a fresh install has nothing to announce, and remembers its version', () async {
      expect(await due('1.4.0', updated: false), isEmpty);
      expect((await SharedPreferences.getInstance()).getString('whatsnew:seen'), '1.4.0');
      expect(await due('1.4.0'), isEmpty);
    });

    test('an update from a version that kept no record shows its notes once', () async {
      expect(await due('1.4.1'), ['1.4.1', '1.4.0']); // from 1.3.0, which didn't remember a version
      expect(await due('1.4.1'), isEmpty);
    });

    // The patch release after [v] ("1.4.3" -> "1.4.4"): a version with no notes.
    String nextFix(String v) {
      final p = v.split('.');
      return '${p[0]}.${p[1]}.${int.parse(p[2]) + 1}';
    }

    test('only releases since the version last opened, newest first', () async {
      final all = [for (final r in releases()) r.version];
      SharedPreferences.setMockInitialValues({'whatsnew:seen': '1.3.0'});
      expect(await due('1.4.0'), ['1.4.0']);
      for (var i = all.length - 1; i > 0; i--) {
        SharedPreferences.setMockInitialValues({'whatsnew:seen': all[i]});
        expect(await due(all[i - 1]), [all[i - 1]]);
      }
      SharedPreferences.setMockInitialValues({'whatsnew:seen': all.first});
      expect(await due(nextFix(all.first)), isEmpty); // a fix with no notes
      SharedPreferences.setMockInitialValues({'whatsnew:seen': '9.0.0'});
      expect(await due('1.4.0'), isEmpty); // going back a version
    });

    test('About shows the notes of the installed version', () {
      for (final r in releases()) {
        expect(releaseFor(r.version)?.version, r.version);
      }
      final newest = releases().first.version;
      expect(releaseFor(nextFix(newest))?.version, newest);
      expect(releaseFor('')?.version, newest);
      expect(releaseFor('1.3.0'), isNull);
    });

    test('releases are newest first and each says something', () {
      final all = releases();
      for (var i = 0; i + 1 < all.length; i++) {
        expect(Updates.isNewer(all[i].version, all[i + 1].version), isTrue);
      }
      expect(all.every((r) => r.notes.isNotEmpty), isTrue);
      expect(appFeatures().expand((g) => g.features).length, greaterThan(20));
    });

    test("the version in pubspec.yaml has its what's new", () {
      final version = RegExp(r'^version:\s*([\d.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())![1];
      expect(releases().first.version, version, reason: "add the release's notes to lib/data/features.dart");
    });
  });

  group('reminders', () {
    final now = DateTime(2026, 10, 17, 18, 0);

    AppState app({bool loggedToday = false}) => FakeApp()
      ..loading = false
      ..moods = [
        if (loggedToday) MoodLog(id: 'm', mood: 4, note: '', tags: const [], loggedOn: toDateKey(now), loggedAt: '', createdAt: ''),
      ]
      ..bills = const [
        Bill(id: 'b1', name: 'Internet', amount: 1200, dueOn: '2026-10-20', recurrence: 'monthly', isPaid: false),
        Bill(id: 'b2', name: 'Rent', amount: 15000, dueOn: '2026-10-18', recurrence: 'monthly', isPaid: true), // paid
        Bill(id: 'b3', name: 'Gas', amount: 900, dueOn: '2026-10-17', recurrence: 'monthly', isPaid: false), // the day before has passed
      ]
      ..debts = const [
        Debt(id: 'd1', person: 'Rahim', direction: DebtDirection.lent, amount: 500, note: '', walletId: null, occurredOn: '2026-10-01', dueOn: '2026-10-19', closed: false, createdAt: ''),
        Debt(id: 'd2', person: 'Karim', direction: DebtDirection.borrowed, amount: 300, note: '', walletId: null, occurredOn: '2026-10-01', dueOn: '2026-10-25', closed: true, createdAt: ''),
      ];

    test('two weeks of evening check-ins, bills and dhar the day before', () {
      final plan = Notifications.plan(app(), now);
      final checkins = plan.where((n) => n.target == NoticeTarget.mood).toList();
      expect(checkins.length, 14);
      expect(checkins.first.at, DateTime(2026, 10, 17, 21, 0)); // today, still ahead
      final bills = plan.where((n) => n.target == NoticeTarget.bills).toList();
      expect(bills.map((n) => n.title), ['Internet is due tomorrow']);
      expect(bills.single.at, DateTime(2026, 10, 19, 10));
      final dhar = plan.where((n) => n.target == NoticeTarget.dhar).toList();
      expect(dhar.single.title, startsWith('Rahim owes you'));
      expect(dhar.single.at, DateTime(2026, 10, 18, 10));
    });

    test("today's check-in is skipped once a mood is logged; switches turn each kind off", () {
      final a = app(loggedToday: true);
      expect(Notifications.plan(a, now).where((n) => n.target == NoticeTarget.mood).first.at, DateTime(2026, 10, 18, 21, 0));
      a.reminders = const ReminderPrefs(checkin: false, bills: false, dhar: false, checkinTime: '20:30');
      expect(Notifications.plan(a, now), isEmpty);
      a.reminders = const ReminderPrefs(bills: false, dhar: false, checkinTime: '20:30');
      expect(Notifications.plan(a, now).first.at, DateTime(2026, 10, 18, 20, 30));
    });

    test('reminder settings read safely from the account', () {
      final r = ReminderPrefs.fromJson({'checkin': false, 'checkinTime': '25:99', 'bills': 'yes'});
      expect(r.checkin, isFalse);
      expect(r.checkinTime, '21:00');
      expect(r.bills, isTrue);
      expect(ReminderPrefs.fromJson(r.toJson()).checkin, isFalse);
    });
  });

  test("the widgets: spent today, this month, wallets, bills due and today's mood", () {
    final today = DateTime(2026, 10, 17, 9);
    Bill bill(String id, String name, double amount, String due, {bool paid = false}) =>
        Bill(id: id, name: name, amount: amount, dueOn: due, recurrence: 'monthly', isPaid: paid);
    final a = FakeApp()
      ..loading = false
      ..walletsReady = true
      ..wallets = const [
        Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 1000, sort: 0, archived: false),
        Wallet(id: 'bk', name: 'bKash', kind: WalletKind.mobile, color: '#E2136E', openingBalance: 500, sort: 1, archived: false),
        Wallet(id: 'old', name: 'Old', kind: WalletKind.other, color: '#7A746A', openingBalance: 99, sort: 2, archived: true),
      ]
      ..transactions = [
        for (final (id, kind, amount, day, wallet) in [
          ('1', Kind.expense, 120.0, '2026-10-17', 'bk'),
          ('2', Kind.expense, 80.0, '2026-10-17', null),
          ('3', Kind.income, 5000.0, '2026-10-01', null),
          ('4', Kind.expense, 999.0, '2026-09-30', null),
        ])
          Txn(id: id, kind: kind, amount: amount, categoryId: null, categoryName: 'Food', place: '', note: '', occurredOn: day, occurredAt: '', createdAt: '', walletId: wallet),
      ]
      ..bills = [bill('r', 'Rent', 15000, '2026-11-01'), bill('i', 'Internet', 1200, '2026-10-15'), bill('w', 'Water', 300, '2026-10-10', paid: true)]
      ..moods = const [MoodLog(id: 'm', mood: 4, note: '', tags: [], loggedOn: '2026-10-17', loggedAt: '2026-10-17T08:00:00Z', createdAt: '')];
    final f = HomeWidget.figures(a, today);
    // spent today
    expect(f['date'], '2026-10-17');
    expect(f['amount'], '৳200');
    expect(f['sub'], '2 expenses · Oct 17');
    expect(HomeWidget.figures(FakeApp(), today)['sub'], 'Nothing yet · Oct 17');
    // this month (last month's expense doesn't count)
    expect([f['m_month'], f['m_spent'], f['m_earned'], f['m_saved'], f['m_saved_neg']], ['2026-10', '৳200', '৳5,000', '৳4,800', '0']);
    // wallets: entries without one count in the default (Cash); archived ones stay off
    expect([f['w1_name'], f['w1_amount'], f['w2_name'], f['w2_amount'], f['w3_name']], ['Cash', '৳4,921', 'bKash', '৳380', '']);
    expect(f['w_total'], '৳5,301');
    // bills: unpaid, earliest first; the widget colours the overdue one from its date
    expect([f['b1_name'], f['b1_when'], f['b1_due'], f['b2_name'], f['b3_name']], ['Internet', 'Oct 15', '2026-10-15', 'Rent', '']);
    // mood
    expect([f['md_date'], f['md_sub'], f['md1'], f['md5']], ['2026-10-17', 'Today: Good', 'Awful', 'Great']);
    expect(HomeWidget.figures(FakeApp(), today)['md_sub'], 'Not logged yet');
  });

  group('offline', () {
    test('ids are v4 UUIDs', () {
      final id = uuidV4();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
      expect(uuidV4(), isNot(id));
    });

    test('no connection vs the server saying no', () {
      expect(isOffline(const SocketException('Failed host lookup: x.supabase.co')), isTrue);
      expect(isOffline(TimeoutException('slow')), isTrue);
      expect(isOffline(Exception('ClientException: Connection closed before full header was received')), isTrue);
      expect(isOffline(const PostgrestException(message: 'new row violates row-level security policy', code: '42501')), isFalse);
    });

    test('the saved copy round-trips, per account', () async {
      final dir = await Directory.systemTemp.createTemp('catalyst-offline');
      OfflineCopy.folder = () async => dir;
      await OfflineCopy.save('u1', {
        'transactions': [
          {'id': 't1', 'kind': 'expense', 'amount': 120, 'category_name': 'Food', 'occurred_on': '2026-10-17', 'occurred_at': '2026-10-17T03:00:00Z'},
        ],
      }, walletsReady: true);
      final copy = (await OfflineCopy.read('u1'))!;
      expect(copy.walletsReady, isTrue);
      expect(Txn.fromRow(copy.tables['transactions']!.single).amount, 120);
      expect(await OfflineCopy.read('someone-else'), isNull);
      await OfflineCopy.clear('u1');
      expect(await OfflineCopy.read('u1'), isNull);
      await dir.delete(recursive: true);
    });

    group('outbox', () {
      final sent = <String>[];
      late Outbox box;

      setUp(() async {
        sent.clear();
        box = Outbox.instance;
        await box.clear();
        await box.load('u1');
        Outbox.send = (op) async => sent.add('${op.op} ${op.id} ${op.row['amount'] ?? ''}'.trim());
      });

      test('an edit to an unsent entry changes the entry itself; deleting it sends nothing', () async {
        await box.add(const OutboxOp('addTxn', 'a', {'amount': 100}));
        await box.edit('a', {'amount': 150});
        expect(box.ops.single.row['amount'], 150);
        await box.add(const OutboxOp('addTxn', 'b', {'amount': 7}));
        await box.delete('b');
        await box.edit('server-row', {'amount': 9});
        await box.delete('server-row-2');
        expect(await box.flush(), 3);
        expect(sent, ['addTxn a 150', 'editTxn server-row 9', 'deleteTxn server-row-2']);
        expect(box.ops, isEmpty);
      });

      test('stops at a connection problem and keeps the rest; drops what the server refuses', () async {
        await box.add(const OutboxOp('addTxn', 'a', {'amount': 1}));
        await box.add(const OutboxOp('addMood', 'm', {'mood': 4}));
        await box.add(const OutboxOp('addTxn', 'c', {'amount': 3}));
        var calls = 0;
        Outbox.send = (op) async {
          calls++;
          if (op.id == 'a') throw const PostgrestException(message: 'invalid input', code: '22P02');
          if (op.id == 'c') throw const SocketException('Network is unreachable');
        };
        final refused = <String>[];
        expect(await box.flush(onRefused: refused.add), 1);
        expect(calls, 3);
        expect(refused, ['invalid input']);
        expect(box.ops.map((o) => o.id), ['c']);
      });

      test('the queue survives a restart and belongs to one account', () async {
        await box.add(const OutboxOp('addTxn', 'a', {'amount': 1}));
        await box.load('u2');
        expect(box.ops, isEmpty);
        await box.load('u1');
        expect(box.ops.single.id, 'a');
      });
    });
  });
}

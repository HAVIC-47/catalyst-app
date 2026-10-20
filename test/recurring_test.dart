// 1.5: recurring dates (the same cases as the web's src/lib/recurring.ts), streaks,
// challenges, mood-spend alerts, net worth and zakat — and the AppState flows on
// top: a due date is logged once and the rule moves on, back-filling a past start,
// pausing, editing, deleting; alerts said once; what Notifications schedules.
import 'package:catalyst/data/app_state.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/services/notifications.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/habits.dart';
import 'package:catalyst/util/i18n.dart';
import 'package:catalyst/util/networth.dart';
import 'package:catalyst/util/recurring.dart';
import 'package:catalyst/util/zakat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';
import 'fake_money_db.dart';

Schedule _s({
  Frequency frequency = Frequency.monthly,
  int every = 1,
  int day1 = 1,
  int? day2,
  String time = '09:00',
  String startOn = '2026-10-18',
  String? endOn,
}) =>
    Schedule(frequency: frequency, every: every, day1: day1, day2: day2, time: time, startOn: startOn, endOn: endOn);

List<String> _walk(Schedule s, String from, int count) {
  final out = <String>[];
  for (var d = occurrenceOnOrAfter(s, from); d != null && out.length < count; d = occurrenceAfter(s, d)) {
    out.add(d);
  }
  return out;
}

Txn _tx(String day, double amount, {Kind kind = Kind.expense, String category = 'Food', String? recurring, String? categoryId}) => Txn(
      id: '$day-$amount-${kind.name}',
      kind: kind,
      amount: amount,
      categoryId: categoryId,
      categoryName: category,
      place: '',
      note: '',
      occurredOn: day,
      occurredAt: '',
      createdAt: '',
      recurringId: recurring,
    );

MoodLog _mood(String day, int m) => MoodLog(id: 'm$day$m', mood: m, note: '', tags: const [], loggedOn: day, loggedAt: '${day}T12:00:00Z', createdAt: '');

Challenge _challenge(ChallengeKind kind, {double target = 3, String category = '', String startOn = '2026-10-12', int days = 7}) =>
    Challenge(id: 'c', kind: kind, target: target, categoryName: category, startOn: startOn, days: days);

const _today = '2026-10-18';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
    await setAppLang('en');
    AppState.deviceTimezone = () async => 'Asia/Dhaka';
  });

  group('recurring dates (same as the web)', () {
    test('monthly, the 31st, every 3 months, every year', () {
      expect(_walk(_s(), '2026-10-18', 3), ['2026-11-01', '2026-12-01', '2027-01-01']);
      expect(_walk(_s(day1: 31, startOn: '2026-01-15'), '2026-01-15', 4), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
      expect(_walk(_s(day1: 31, startOn: '2028-02-01'), '2028-02-01', 1), ['2028-02-29']);
      expect(_walk(_s(every: 3, day1: 15, startOn: '2026-11-15'), '2026-11-15', 3), ['2026-11-15', '2027-02-15', '2027-05-15']);
      expect(_walk(_s(every: 3, day1: 15, startOn: '2026-11-15'), '2027-01-01', 1), ['2027-02-15']);
      expect(_walk(_s(every: 12, day1: 10, startOn: '2027-03-10'), '2026-10-18', 2), ['2027-03-10', '2028-03-10']);
    });

    test('twice a month, either order, short months', () {
      expect(_walk(_s(frequency: Frequency.twiceMonthly, day1: 1, day2: 15), '2026-10-18', 3), ['2026-11-01', '2026-11-15', '2026-12-01']);
      expect(_walk(_s(frequency: Frequency.twiceMonthly, day1: 31, day2: 15, startOn: '2027-02-01'), '2027-02-01', 3),
          ['2027-02-15', '2027-02-28', '2027-03-15']);
      expect(_walk(_s(frequency: Frequency.twiceMonthly, day1: 15, day2: 15, startOn: '2027-02-01'), '2027-02-01', 2), ['2027-02-15', '2027-03-15']);
    });

    test('weekly and every two weeks keep their rhythm', () {
      expect(isoWeekday('2026-10-18'), 7);
      expect(_walk(_s(frequency: Frequency.weekly, day1: 5), '2026-10-18', 2), ['2026-10-23', '2026-10-30']);
      final fortnight = _s(frequency: Frequency.weekly, day1: 1, every: 2);
      expect(_walk(fortnight, '2026-10-18', 3), ['2026-10-19', '2026-11-02', '2026-11-16']);
      expect(_walk(fortnight, '2026-10-20', 1), ['2026-11-02']);
      expect(_walk(fortnight, '2026-11-02', 1), ['2026-11-02']);
    });

    test('an end date stops it; what is due; a cap per run', () {
      final ending = _s(startOn: '2026-10-01', endOn: '2026-12-15');
      expect(_walk(ending, '2026-10-01', 9), ['2026-10-01', '2026-11-01', '2026-12-01']);
      expect(nextAfterLogged(ending, '2026-12-01'), '2026-12-16');
      expect(hasEnded(ending, '2026-12-16'), isTrue);
      expect(hasEnded(ending, '2026-12-01'), isFalse);
      final s = _s(startOn: '2026-08-01');
      expect(dueDates(s, nextOn: '2026-08-01', paused: false, today: '2026-10-01', now: '08:59'), ['2026-08-01', '2026-09-01']);
      expect(dueDates(s, nextOn: '2026-08-01', paused: false, today: '2026-10-01', now: '09:00'), ['2026-08-01', '2026-09-01', '2026-10-01']);
      expect(dueDates(s, nextOn: '2026-08-01', paused: true, today: '2026-10-01', now: '23:00'), isEmpty);
      expect(dueDates(s, nextOn: '2026-11-01', paused: false, today: '2026-10-01', now: '23:00'), isEmpty);
      expect(dueDates(_s(frequency: Frequency.weekly, day1: 3, startOn: '2026-08-01'), nextOn: '2026-08-01', paused: false, today: '2027-12-31', now: '23:00').length, 60);
      expect(firstNextOn(_s(startOn: '2026-09-01'), '2026-09-01'), '2026-09-01');
      expect(firstNextOn(_s(startOn: '2026-09-01'), '2026-10-18'), '2026-11-01');
      expect(occurrenceOnOrAfter(_s(startOn: ''), '2026-10-18'), isNull);
      expect(_s().sameAs(_s()), isTrue);
      expect(_s().sameAs(_s(time: '10:00')), isFalse);
      expect(_s(day2: 5).sameAs(_s(day2: 9)), isTrue);
    });
  });

  group('streaks, challenges, mood & money', () {
    test('a streak counts days logged by hand, and stays alive while today is open', () {
      final days = loggedDays([_tx('2026-10-18', 10), _tx('2026-10-17', 5), _tx('2026-10-16', 5, recurring: 'r1')], [_mood('2026-10-16', 3), _mood('2026-10-15', 4)]);
      expect(streakOf(days, _today), (current: 4, best: 4, todayDone: true, since: '2026-10-15'));
      expect(streakOf(loggedDays([_tx('2026-10-17', 5), _tx('2026-10-16', 5)], []), _today), (current: 2, best: 2, todayDone: false, since: '2026-10-16'));
      expect(streakOf(loggedDays([_tx('2026-10-16', 5), _tx('2026-10-01', 1), _tx('2026-10-02', 1), _tx('2026-10-03', 1)], []), _today),
          (current: 0, best: 3, todayDone: false, since: null));
      expect([for (final n in [2, 3, 13, 14, 399, 512]) streakMilestone(n)], [0, 3, 7, 14, 365, 500]);
    });

    test('challenges: no-spend, spend under, skip a category, save, log daily', () {
      final txs = [_tx('2026-10-13', 300), _tx('2026-10-15', 200, category: 'Coffee'), _tx('2026-10-14', 9000, recurring: 'rent'), _tx('2026-10-18', 50)];
      final p = challengeProgress(_challenge(ChallengeKind.noSpend), txs, [], _today);
      expect((p.status, p.value, p.goal, p.endOn, p.daysLeft), (ChallengeStatus.won, 4.0, 3.0, '2026-10-18', 1));
      expect(challengeProgress(_challenge(ChallengeKind.noSpend, target: 6), txs, [], _today).status, ChallengeStatus.lost);
      expect(challengeProgress(_challenge(ChallengeKind.noSpend, target: 5), txs, [], _today).status, ChallengeStatus.active);
      expect(challengeProgress(_challenge(ChallengeKind.noSpend, target: 5), txs, [], '2026-10-19').status, ChallengeStatus.lost);
      final under = challengeProgress(_challenge(ChallengeKind.spendUnder, target: 600), txs, [], _today);
      expect((under.status, under.value, under.goal), (ChallengeStatus.active, 550.0, 600.0));
      expect(challengeProgress(_challenge(ChallengeKind.spendUnder, target: 600), txs, [], '2026-10-19').status, ChallengeStatus.won);
      expect(challengeProgress(_challenge(ChallengeKind.spendUnder, target: 500), txs, [], _today).status, ChallengeStatus.lost);
      expect(challengeProgress(_challenge(ChallengeKind.skipCategory, category: 'coffee'), txs, [], _today).status, ChallengeStatus.lost);
      expect(challengeProgress(_challenge(ChallengeKind.skipCategory, category: 'Taxi'), txs, [], _today).status, ChallengeStatus.active);
      expect(challengeProgress(_challenge(ChallengeKind.skipCategory, category: 'Taxi'), txs, [], '2026-10-25').status, ChallengeStatus.won);
      final saves = [_tx('2026-10-12', 400, kind: Kind.saving), _tx('2026-10-16', 700, kind: Kind.saving)];
      expect(challengeProgress(_challenge(ChallengeKind.save, target: 1000), saves, [], _today).status, ChallengeStatus.won);
      expect(challengeProgress(_challenge(ChallengeKind.save, target: 2000), saves, [], _today).status, ChallengeStatus.active);
      expect(challengeProgress(_challenge(ChallengeKind.save, target: 2000), saves, [], '2026-10-20').status, ChallengeStatus.lost);
      final daily = [for (final d in [12, 13, 14, 15, 16, 17]) _tx('2026-10-$d', 1)];
      expect(challengeProgress(_challenge(ChallengeKind.logDaily), daily, [], _today).status, ChallengeStatus.active);
      expect(challengeProgress(_challenge(ChallengeKind.logDaily), daily, [_mood('2026-10-18', 4)], _today).status, ChallengeStatus.won);
      expect(challengeProgress(_challenge(ChallengeKind.logDaily), daily.where((t) => t.occurredOn != '2026-10-14').toList(), [], _today).status,
          ChallengeStatus.lost);
      expect(challengeProgress(_challenge(ChallengeKind.noSpend, startOn: '2026-10-20'), txs, [], _today).status, ChallengeStatus.upcoming);
      expect(challengeTitle(_challenge(ChallengeKind.spendUnder, target: 5000), tr, formatCurrency), 'Spend under ৳5,000 in 7 days');
    });

    test('a low day with 1.5× the usual spending, once there is history', () {
      final history = [
        for (var i = 1; i <= 30; i++) _tx('2026-09-${'$i'.padLeft(2, '0')}', 200),
        for (var i = 1; i <= 17; i++) _tx('2026-10-${'$i'.padLeft(2, '0')}', 200),
      ];
      final big = [...history, _tx(_today, 700), _tx(_today, 5000, recurring: 'rent')];
      expect(moodSpendAlert(big, [_mood(_today, 2)], _today), (spent: 700.0, usual: 200.0, ratio: 3.5, mood: 2.0));
      expect(moodSpendAlert(big, [_mood(_today, 4)], _today), isNull);
      expect(moodSpendAlert(big, [_mood(_today, 2), _mood(_today, 4)], _today), isNull);
      expect(moodSpendAlert([...history, _tx(_today, 250)], [_mood(_today, 1)], _today), isNull);
      expect(moodSpendAlert([_tx('2026-10-15', 100), _tx(_today, 900)], [_mood(_today, 1)], _today), isNull);
      expect(moodSpendAlert(big, [], _today), isNull);
      final moods = [for (final (i, m) in [1, 2, 2, 4, 5, 4].indexed) _mood('2026-10-${10 + i}', m)];
      final spend = [for (final (i, d) in [10, 11, 12, 13, 14, 15].indexed) _tx('2026-10-$d', i < 3 ? 900 : 300)];
      expect(moodSpendPattern(spend, moods, _today), (low: 900.0, good: 300.0, lowDays: 3, goodDays: 3));
      expect(moodSpendPattern(spend, moods.sublist(1), _today), isNull);
    });
  });

  test('net worth: wallets plus owed to you minus you owe, at each month end', () {
    const wallets = [
      Wallet(id: 'a', name: 'Cash', kind: WalletKind.cash, color: '#000000', openingBalance: 1000, sort: 0, archived: false),
      Wallet(id: 'b', name: 'Bank', kind: WalletKind.bank, color: '#000000', openingBalance: 500, sort: 1, archived: false),
    ];
    final txs = [_tx('2026-09-01', 50000, kind: Kind.income), _tx('2026-09-10', 20000), _tx('2026-09-11', 5000, kind: Kind.saving), _tx('2026-10-05', 1000)];
    Debt debt(String id, DebtDirection dir, double amount, String on, {bool closed = false}) =>
        Debt(id: id, person: 'X', direction: dir, amount: amount, note: '', walletId: null, occurredOn: on, dueOn: null, closed: closed, createdAt: '');
    final debts = [debt('d1', DebtDirection.lent, 3000, '2026-09-15'), debt('d2', DebtDirection.borrowed, 10000, '2026-10-01'), debt('d3', DebtDirection.lent, 800, '2026-08-01', closed: true)];
    const pays = [
      DebtPayment(id: 'p1', debtId: 'd1', amount: 1000, walletId: null, paidOn: '2026-10-10', note: '', createdAt: ''),
      DebtPayment(id: 'p2', debtId: 'd3', amount: 300, walletId: null, paidOn: '2026-08-20', note: '', createdAt: ''),
    ];
    expect(netWorthOn('2026-09-30', wallets, txs, debts, pays), (date: '2026-09-30', cash: 28000.0, owedToYou: 3000.0, youOwe: 0.0, total: 31000.0));
    expect(netWorthOn(_today, wallets, txs, debts, pays), (date: _today, cash: 38000.0, owedToYou: 2000.0, youOwe: 10000.0, total: 30000.0));
    expect([for (final p in netWorthSeries(_today, 12, wallets, txs, debts, pays)) p.date], ['2026-08-31', '2026-09-30', _today]);
    expect([for (final p in netWorthSeries('2026-03-05', 12, const [], [_tx('2025-12-31', 1, kind: Kind.income)], const [], const [])) p.date],
        ['2025-12-31', '2026-01-31', '2026-02-28', '2026-03-05']);
  });

  test('zakat: 2.5% at or above the nisab', () {
    expect(nisabWeight('silver', 'bhori'), closeTo(52.5, 1e-9));
    expect(nisabWeight('gold', 'bhori'), closeTo(7.5, 1e-9));
    // Typed prices and pure gold (live prices and 22K are tested in features160_test.dart).
    const inputs = ZakatInputs(autoPrices: false, karat: 24, silverPrice: 2000, goldPrice: 150000, gold: 1, cash: 10000, debts: 5000);
    final r = zakatOf(inputs, wallets: 100000, owedToYou: 20000, youOwe: 15000);
    expect((r.nisab, r.assets, r.liabilities, r.net, r.above, r.due), (105000.0, 280000.0, 20000.0, 260000.0, true, 6500.0));
    expect(zakatOf(inputs.copyWith(basis: 'gold'), wallets: 100000, owedToYou: 20000, youOwe: 15000).due, 0);
    expect(zakatOf(inputs.copyWith(silverPrice: 0), wallets: 100000, owedToYou: 0, youOwe: 0).due, 0);
    expect(zakatOf(inputs.copyWith(useWallets: false, useDhar: false), wallets: 100000, owedToYou: 20000, youOwe: 15000).net, 155000);
    final parsed = ZakatInputs.fromJson({'basis': 'gold', 'unit': 'g', 'gold': -3, 'cash': '12', 'useDhar': false});
    expect((parsed.basis, parsed.unit, parsed.gold, parsed.cash, parsed.useDhar, parsed.useWallets), ('gold', 'g', 0.0, 0.0, false, true));
    expect(ZakatInputs.fromJson(inputs.toJson()).toJson(), inputs.toJson());
  });

  test('notification settings: every kind on by default, and kept round trip (the web keeps the app-only one)', () {
    const r = ReminderPrefs();
    expect(r.onCount, ReminderPrefs.kinds);
    final back = ReminderPrefs.fromJson(r.copyWith(moodSpend: false, updates: false, checkinTime: '20:30').toJson());
    expect((back.moodSpend, back.updates, back.recurring, back.checkinTime), (false, false, true, '20:30'));
    // What an older app (1.4.3) saved: the new kinds start on.
    final old = ReminderPrefs.fromJson({'checkin': true, 'checkinTime': '21:00', 'bills': false, 'budgets': true, 'dhar': true});
    expect((old.bills, old.recurring, old.streaks, old.challenges), (false, true, true, true));
  });

  group('AppState', () {
    late FakeApp app;
    late FakeMoneyDb db;
    final now = DateTime.now();
    String day(int ago) => toDateKey(DateTime(now.year, now.month, now.day - ago));

    setUp(() {
      db = FakeMoneyDb();
      app = FakeApp()
        ..loading = false
        ..db = db
        ..recurringReady = true
        ..walletsReady = true
        ..wallets = const [Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 0, sort: 0, archived: false)]
        ..categories = const [
          Category(id: 'salary', name: 'Salary', kind: Kind.income, color: '#2E8159', sort: 0),
          Category(id: 'other-in', name: 'Other', kind: Kind.income, color: '#7A746A', sort: 1),
          Category(id: 'rent', name: 'Rent', kind: Kind.expense, color: '#7A4E86', sort: 0),
          Category(id: 'other', name: 'Other', kind: Kind.expense, color: '#7A746A', sort: 1),
        ];
    });

    /// Weekly from 21 days ago on its weekday, at midnight: four dates are due today.
    RecurringRule weekly({String id = 'r1', String? nextOn, bool paused = false}) => RecurringRule(
          id: id,
          name: 'Rent',
          kind: Kind.expense,
          amount: 2500,
          schedule: Schedule(frequency: Frequency.weekly, day1: isoWeekday(day(21)), time: '00:00', startOn: day(21)),
          nextOn: nextOn ?? day(21),
          paused: paused,
        );

    test('every due date is logged once, under its category and wallet, and the rule moves on', () async {
      final notices = <String>[];
      final sub = app.notices.stream.listen(notices.add);
      app.recurring = [weekly()];
      await app.runRecurring();
      expect([for (final t in app.transactions) t.occurredOn]..sort(), [day(21), day(14), day(7), day(0)]);
      final t = app.transactions.first;
      expect((t.kind, t.amount, t.categoryName, t.categoryId, t.walletId, t.note, t.recurringId), (Kind.expense, 2500.0, 'Rent', 'rent', 'cash', 'Rent', 'r1'));
      expect(app.recurring.single.nextOn, day(-7));
      expect(db.calls, contains('advanceRecurring r1 ${day(-7)}'));
      // Again: nothing more is due.
      await app.runRecurring();
      expect(app.transactions.length, 4);
      await Future<void>.delayed(Duration.zero);
      expect(notices.single, '4 recurring entries added: Rent');
      await sub.cancel();
    });

    test('a date another device logged first is not added again', () async {
      db.loggedElsewhere.add('r1 ${day(7)}');
      app.recurring = [weekly(nextOn: day(7))];
      await app.runRecurring();
      expect([for (final t in app.transactions) t.occurredOn], [day(0)]);
      expect(db.calls, contains('logRecurring r1 ${day(7)} (already there)'));
      expect(app.recurring.single.nextOn, day(-7));
    });

    test('paused rules log nothing; resuming starts from today; a new one back-fills from its start', () async {
      app.recurring = [weekly(paused: true)];
      await app.runRecurring();
      expect(app.transactions, isEmpty);
      await app.pauseRecurring('r1', false);
      await Future<void>.delayed(Duration.zero);
      expect(app.recurring.single.paused, isFalse);
      expect([for (final t in app.transactions) t.occurredOn], [day(0)]); // missed weeks stay missed

      final made = await app.createRecurring((
        name: 'Salary',
        kind: Kind.income,
        amount: 50000,
        categoryId: null,
        walletId: null,
        schedule: Schedule(frequency: Frequency.weekly, day1: isoWeekday(day(14)), time: '00:00', startOn: day(14)),
      ));
      await Future<void>.delayed(Duration.zero);
      await app.runRecurring();
      expect(made.tz, 'Asia/Dhaka');
      expect(db.calls, contains('addRecurring Salary next ${day(14)}'));
      final salary = app.transactions.where((t) => t.recurringId == made.id).toList();
      expect([for (final t in salary) t.occurredOn]..sort(), [day(14), day(7), day(0)]);
      expect(salary.first.categoryName, 'Salary'); // matched by name
    });

    test('a changed schedule carries on from today (nothing back-filled); deleting keeps its entries', () async {
      app.recurring = [weekly(nextOn: day(-7))];
      final monthly = Schedule(frequency: Frequency.monthly, day1: DateTime(now.year, now.month, now.day + 1).day, time: '09:00', startOn: day(21));
      await app.editRecurring('r1', (name: 'Rent', kind: Kind.expense, amount: 2600, categoryId: 'rent', walletId: null, schedule: monthly));
      await Future<void>.delayed(Duration.zero);
      expect(app.recurring.single.amount, 2600);
      expect(app.recurring.single.nextOn, day(-1)); // tomorrow — not the start date three weeks ago
      expect(db.calls.where((c) => c.startsWith('updateRecurring r1')).single, contains('next_on: ${day(-1)}'));
      expect(app.transactions, isEmpty);

      app.transactions = [_tx(day(1), 2500, recurring: 'r1')];
      await app.removeRecurring('r1');
      expect(app.recurring, isEmpty);
      expect(app.transactions.single.recurringId, isNull);
      expect(db.calls, contains('deleteRecurring r1'));
    });

    test('mood-spend: an alert once a day, only when it is on', () async {
      final alerts = <AppAlert>[];
      final sub = app.alerts.stream.listen(alerts.add);
      app
        ..transactions = [for (var i = 1; i <= 20; i++) _tx(day(i), 200), _tx(day(0), 900)]
        ..moods = [_mood(day(0), 1)];
      await app.checkMoodSpend();
      await app.checkMoodSpend();
      await Future<void>.delayed(Duration.zero);
      expect(alerts.single.title, 'Mood & money');
      expect(alerts.single.body, "You've spent ৳900 today on a low day — about 4.5× your usual.");

      SharedPreferences.setMockInitialValues({});
      app.reminders = app.reminders.copyWith(moodSpend: false);
      await app.checkMoodSpend();
      await Future<void>.delayed(Duration.zero);
      expect(alerts.length, 1);
      await sub.cancel();
    });

    test('a fresh streak milestone and a challenge won are each said once', () async {
      final alerts = <AppAlert>[];
      final sub = app.alerts.stream.listen(alerts.add);
      app
        ..transactions = [for (var i = 0; i < 7; i++) _tx(day(i), 10)]
        ..challenges = [Challenge(id: 'c1', kind: ChallengeKind.save, target: 100, startOn: day(2), days: 7)];
      app.transactions = [...app.transactions, _tx(day(1), 150, kind: Kind.saving)];
      await app.checkHabits();
      await app.checkHabits();
      await Future<void>.delayed(Duration.zero);
      expect([for (final a in alerts) a.title], ['7-day streak!', 'Challenge done!']);
      expect(alerts.last.body, 'Save ৳100 in 7 days. Well done!');
      await sub.cancel();
    });
  });

  group('what the phone schedules', () {
    final now = DateTime.now();
    final noon = DateTime(now.year, now.month, now.day, 12);
    String day(int ago) => toDateKey(DateTime(noon.year, noon.month, noon.day - ago));

    FakeApp app() => FakeApp()
      ..loading = false
      ..recurringReady = true
      ..categories = const [Category(id: 'salary', name: 'Salary', kind: Kind.income, color: '#2E8159', sort: 0)];

    test('each recurring entry at its time, and nothing when that kind is off', () {
      final a = app()
        ..recurring = [
          RecurringRule(
            id: 'r1',
            name: 'Salary',
            kind: Kind.income,
            amount: 50000,
            schedule: Schedule(frequency: Frequency.weekly, day1: isoWeekday(day(-1)), time: '09:00', startOn: day(-1)),
            nextOn: day(-1),
          ),
        ];
      final plan = Notifications.plan(a, noon).where((n) => n.id >= 4000 && n.id < 5000).toList();
      expect(plan.length, 4);
      final first = plan.first;
      expect(first.at, DateTime(noon.year, noon.month, noon.day + 1, 9));
      expect((first.title, first.body, first.target), ('Added automatically: Salary', '+৳50,000 · Salary', NoticeTarget.recurring));
      a.reminders = a.reminders.copyWith(recurring: false);
      expect(Notifications.plan(a, noon).where((n) => n.id >= 4000 && n.id < 5000), isEmpty);
    });

    test("a streak about to end: in tonight's check-in, or on its own", () {
      final a = app()
        ..reminders = const ReminderPrefs(checkinTime: '21:00')
        ..transactions = [_tx(day(1), 10), _tx(day(2), 10)];
      final checkin = Notifications.plan(a, noon).firstWhere((n) => n.id == 1000);
      expect(checkin.body, 'Log your mood — and keep your 2-day streak.');
      a.reminders = a.reminders.copyWith(checkin: false);
      final alone = Notifications.plan(a, noon).firstWhere((n) => n.id == 5000);
      expect(alone.title, 'Keep your 2-day streak');
      a.reminders = a.reminders.copyWith(streaks: false);
      expect(Notifications.plan(a, noon).where((n) => n.id == 5000), isEmpty);
    });

    test("a challenge's last day, in the morning", () {
      final a = app()..challenges = [Challenge(id: 'c', kind: ChallengeKind.spendUnder, target: 1000, startOn: day(5), days: 7)];
      final last = Notifications.plan(a, noon).firstWhere((n) => n.id == 6000);
      expect(last.at, DateTime(noon.year, noon.month, noon.day + 1, 10));
      expect((last.title, last.body), ('Last day of your challenge', 'Spend under ৳1,000 in 7 days'));
      a.reminders = a.reminders.copyWith(challenges: false);
      expect(Notifications.plan(a, noon).where((n) => n.id >= 6000 && n.id < 7000), isEmpty);
    });
  });
}

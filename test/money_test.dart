// Money rules (util/money.dart) and the AppState flows built on them: paying a
// bill logs the expense and rolls the bill on (with Undo), transfers with a fee,
// dhar part payments that close and reopen a debt, budget alerts.
import 'package:catalyst/models.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';
import 'fake_money_db.dart';

const _cash = Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 1000, sort: 0, archived: false);
const _bkash = Wallet(id: 'bkash', name: 'bKash', kind: WalletKind.mobile, color: '#E2136E', openingBalance: 500, sort: 1, archived: false);

Txn _txn(String id, Kind kind, double amount, {String? wallet, String category = 'Food', String? day}) => Txn(
      id: id,
      kind: kind,
      amount: amount,
      categoryId: null,
      categoryName: category,
      place: '',
      note: '',
      occurredOn: day ?? toDateKey(DateTime.now()),
      occurredAt: '',
      createdAt: '',
      walletId: wallet,
    );

Debt _debt(String id, DebtDirection dir, double amount, {String? wallet, bool closed = false}) => Debt(
      id: id,
      person: 'Rahim',
      direction: dir,
      amount: amount,
      note: '',
      walletId: wallet,
      occurredOn: '2026-10-01',
      dueOn: null,
      closed: closed,
      createdAt: '',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
  });

  group('wallet balances', () {
    test('opening + income - expenses, transfers, and dhar both ways', () {
      final b = walletBalances(
        [_cash, _bkash],
        [
          _txn('1', Kind.income, 2000, wallet: 'bkash'),
          _txn('2', Kind.expense, 300, wallet: 'cash'),
          _txn('3', Kind.expense, 50), // no wallet: the default (Cash)
          _txn('4', Kind.saving, 999, wallet: 'cash'), // savings don't touch wallets
        ],
        [const Transfer(id: 't', fromWallet: 'bkash', toWallet: 'cash', amount: 1000, note: '', occurredOn: '2026-10-02', occurredAt: '', createdAt: '')],
        [_debt('lent', DebtDirection.lent, 400, wallet: 'cash'), _debt('borrowed', DebtDirection.borrowed, 250, wallet: 'bkash')],
        [const DebtPayment(id: 'p', debtId: 'lent', amount: 100, walletId: 'bkash', paidOn: '2026-10-05', note: '', createdAt: '')],
      );
      // Cash: 1000 - 300 - 50 + 1000 - 400 = 1250. bKash: 500 + 2000 - 1000 + 250 + 100 = 1850.
      expect(b['cash'], 1250);
      expect(b['bkash'], 1850);
    });

    test('an entry whose wallet was deleted counts in the default wallet', () {
      final b = walletBalances([_cash, _bkash], [_txn('1', Kind.expense, 10, wallet: 'gone')], const [], const [], const []);
      expect(b['cash'], 990);
      expect(walletNamer([_cash, _bkash])(_txn('1', Kind.expense, 10, wallet: 'gone'))?.name, 'Cash');
    });

    test('the default wallet is the first one that is not archived', () {
      expect(defaultWallet([_cash.copyWith(archived: true), _bkash])?.id, 'bkash');
      expect(defaultWallet(const []), isNull);
    });
  });

  group('next due date', () {
    test('monthly keeps the day, pulled back at the end of a short month', () {
      expect(nextDue('2026-01-31', 'monthly'), '2026-02-28');
      expect(nextDue('2028-01-31', 'monthly'), '2028-02-29');
      expect(nextDue('2026-10-15', 'monthly'), '2026-11-15');
      expect(nextDue('2026-12-10', 'monthly'), '2027-01-10');
    });

    test('weekly, yearly (29 Feb -> 28 Feb), and once', () {
      expect(nextDue('2026-10-15', 'weekly'), '2026-10-22');
      expect(nextDue('2028-02-29', 'yearly'), '2029-02-28');
      expect(nextDue('2026-10-15', 'once'), isNull);
    });
  });

  test('a bill is logged under its own category, one named like it, Utilities, then Other', () {
    const cats = [
      Category(id: 'net', name: 'Internet', kind: Kind.expense, color: '#000000', sort: 0),
      Category(id: 'util', name: 'Utilities', kind: Kind.expense, color: '#000000', sort: 1),
      Category(id: 'other', name: 'Other', kind: Kind.expense, color: '#000000', sort: 2),
      Category(id: 'salary', name: 'Rent', kind: Kind.income, color: '#000000', sort: 0),
    ];
    Bill bill(String name, [String? cat]) => Bill(id: 'b', name: name, amount: 1, dueOn: '2026-10-01', recurrence: 'monthly', isPaid: false, categoryId: cat);
    expect(billCategory(bill('Gas', 'other'), cats)?.id, 'other');
    expect(billCategory(bill('internet'), cats)?.id, 'net');
    expect(billCategory(bill('Rent'), cats)?.id, 'util'); // an income category of that name doesn't count
    expect(billCategory(bill('Gym'), cats.where((c) => c.id != 'util').toList())?.id, 'other');
  });

  test('what is left on a debt, and when it counts as open', () {
    final d = _debt('d', DebtDirection.lent, 500);
    const pays = [DebtPayment(id: 'p', debtId: 'd', amount: 200, walletId: null, paidOn: '2026-10-02', note: '', createdAt: '')];
    expect(debtRemaining(d, pays), 300);
    expect(debtIsOpen(d, pays), isTrue);
    expect(debtIsOpen(d.copyWith(closed: true), pays), isFalse);
    expect(debtRemaining(d, [...pays, const DebtPayment(id: 'q', debtId: 'd', amount: 400, walletId: null, paidOn: '2026-10-03', note: '', createdAt: '')]), 0);
  });

  test('budget use counts this month by category id or name', () {
    const budget = Budget(id: 'b', categoryId: 'food', categoryName: 'Food', amount: 1000, period: 'monthly');
    final now = DateTime(2026, 10, 17);
    final use = budgetUse(budget, [
      _txn('1', Kind.expense, 300, day: '2026-10-02'),
      _txn('2', Kind.expense, 500, day: '2026-10-16', category: 'food'), // name match is case-insensitive
      _txn('3', Kind.expense, 900, day: '2026-09-30'), // last month
      _txn('4', Kind.income, 900, day: '2026-10-03'),
    ], now);
    expect(use.spent, 800);
    expect(use.ratio, closeTo(0.8, 1e-9));
  });

  group('AppState', () {
    late FakeApp app;
    late FakeMoneyDb db;

    setUp(() {
      db = FakeMoneyDb();
      app = FakeApp()
        ..loading = false
        ..db = db
        ..walletsReady = true
        ..wallets = [_cash, _bkash]
        ..categories = const [
          Category(id: 'util', name: 'Utilities', kind: Kind.expense, color: '#000000', sort: 0),
          Category(id: 'other', name: 'Other', kind: Kind.expense, color: '#000000', sort: 1),
          Category(id: 'fees', name: 'Fees', kind: Kind.expense, color: '#000000', sort: 2),
          Category(id: 'food', name: 'Food', kind: Kind.expense, color: '#000000', sort: 3),
        ];
    });

    test('paying a monthly bill logs the expense and moves the bill on; Undo puts both back', () async {
      app.bills = [const Bill(id: 'net', name: 'Internet', amount: 1200, dueOn: '2026-10-20', recurrence: 'monthly', isPaid: false, walletId: 'bkash')];
      final p = await app.payBill('net');
      final txn = app.transactions.single;
      expect(txn.kind, Kind.expense);
      expect(txn.amount, 1200);
      expect(txn.categoryName, 'Utilities');
      expect(txn.walletId, 'bkash');
      expect(txn.note, 'Internet');
      expect(app.bills.single.dueOn, '2026-11-20');
      expect(app.bills.single.isPaid, isFalse);
      expect(app.bills.single.lastPaidTxn, txn.id);

      await app.undoBillPayment(p);
      expect(app.transactions, isEmpty);
      expect(app.bills.single.dueOn, '2026-10-20');
      expect(app.bills.single.lastPaidTxn, isNull);
    });

    test('a one-off bill is marked paid; unpaying it takes the expense back off', () async {
      app.bills = [const Bill(id: 'fee', name: 'Exam fee', amount: 3000, dueOn: '2026-10-25', recurrence: 'once', isPaid: false)];
      await app.payBill('fee');
      expect(app.bills.single.isPaid, isTrue);
      expect(app.transactions.single.walletId, 'cash'); // no wallet set: the default
      expect(app.transactions.single.categoryName, 'Utilities');

      await app.unpayBill('fee');
      expect(app.bills.single.isPaid, isFalse);
      expect(app.transactions, isEmpty);
    });

    test('a transfer with a fee logs the fee as an expense from the first wallet', () async {
      await app.createTransfer(fromWallet: 'bkash', toWallet: 'cash', amount: 1000, note: 'Cash out', occurredOn: '2026-10-17', occurredAt: '', fee: 18.5);
      expect(app.transfers.single.amount, 1000);
      final fee = app.transactions.single;
      expect(fee.amount, 18.5);
      expect(fee.walletId, 'bkash');
      expect(fee.categoryName, 'Fees');
      expect(fee.note, 'bKash fee');
    });

    test('a paid-off debt closes itself; taking a payment back reopens it', () async {
      final d = await app.createDebt(person: 'Rahim', direction: DebtDirection.lent, amount: 500, note: '', walletId: 'cash', occurredOn: '2026-10-01', dueOn: null);
      await app.recordDebtPayment(debtId: d.id, amount: 200, walletId: 'cash', paidOn: '2026-10-05');
      expect(app.debts.single.closed, isFalse);
      await app.recordDebtPayment(debtId: d.id, amount: 300, walletId: 'bkash', paidOn: '2026-10-09');
      expect(app.debts.single.closed, isTrue);
      expect(db.calls, contains('updateDebt ${d.id} {closed: true}'));

      await app.removeDebtPayment(app.debtPayments.last.id);
      expect(app.debts.single.closed, isFalse);
    });

    test('budget alerts at 80% and 100%, each once a month', () async {
      app
        ..reminders = app.reminders.copyWith(budgets: true)
        ..budgets = const [Budget(id: 'b', categoryId: 'food', categoryName: 'Food', amount: 1000, period: 'monthly')];
      final notices = <String>[];
      final sub = app.notices.stream.listen(notices.add);
      final today = toDateKey(DateTime.now());
      Future<void> spend(double amount) async {
        // FakeApp's addMoney skips the alert check; run the real one on the same change.
        final before = app.transactions;
        await app.addMoney(NewTxn(kind: Kind.expense, amount: amount, categoryId: 'food', categoryName: 'Food', occurredOn: today, occurredAt: ''));
        await app.checkBudgets(before);
      }

      await spend(500);
      await spend(350); // 85%
      await spend(10); // still 86%: no repeat
      await spend(200); // 106%
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(notices.length, 2);
      expect(notices.first, contains('85% used'));
      expect(notices.last, contains('used up'));
    });
  });
}

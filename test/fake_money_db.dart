// The money tables in memory, for tests: each call is recorded, and rows come
// back the way the database returns them.
import 'package:catalyst/data/money_db.dart';
import 'package:catalyst/models.dart';

class FakeMoneyDb implements MoneyDb {
  final calls = <String>[];
  var _id = 0;

  String _next(String prefix) => '$prefix${++_id}';

  @override
  Future<Bill> addBill({
    required String name,
    required double amount,
    required String dueOn,
    required String recurrence,
    String? categoryId,
    String? walletId,
  }) async {
    calls.add('addBill $name');
    return Bill(id: _next('bill'), name: name, amount: amount, dueOn: dueOn, recurrence: recurrence, isPaid: false, categoryId: categoryId, walletId: walletId);
  }

  @override
  Future<void> setBillPaid(String id, bool paid) async => calls.add('setBillPaid $id $paid');

  @override
  Future<void> updateBill(String id, Map<String, dynamic> patch) async => calls.add('updateBill $id $patch');

  @override
  Future<void> deleteBill(String id) async => calls.add('deleteBill $id');

  @override
  Future<Wallet> addWallet({required String name, required WalletKind kind, required String color, required double openingBalance, required int sort}) async {
    calls.add('addWallet $name');
    return Wallet(id: _next('w'), name: name, kind: kind, color: color, openingBalance: openingBalance, sort: sort, archived: false);
  }

  @override
  Future<void> updateWallet(String id, Map<String, dynamic> patch) async => calls.add('updateWallet $id $patch');

  @override
  Future<void> deleteWallet(String id) async => calls.add('deleteWallet $id');

  @override
  Future<Transfer> addTransfer({
    required String fromWallet,
    required String toWallet,
    required double amount,
    required String note,
    required String occurredOn,
    required String occurredAt,
  }) async {
    calls.add('addTransfer $fromWallet->$toWallet $amount');
    return Transfer(
      id: _next('tr'),
      fromWallet: fromWallet,
      toWallet: toWallet,
      amount: amount,
      note: note,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
      createdAt: '',
    );
  }

  @override
  Future<void> deleteTransfer(String id) async => calls.add('deleteTransfer $id');

  @override
  Future<Debt> addDebt({
    required String person,
    required DebtDirection direction,
    required double amount,
    required String note,
    required String? walletId,
    required String occurredOn,
    required String? dueOn,
  }) async {
    calls.add('addDebt $person');
    return Debt(
      id: _next('d'),
      person: person,
      direction: direction,
      amount: amount,
      note: note,
      walletId: walletId,
      occurredOn: occurredOn,
      dueOn: dueOn,
      closed: false,
      createdAt: '',
    );
  }

  @override
  Future<void> updateDebt(String id, Map<String, dynamic> patch) async => calls.add('updateDebt $id $patch');

  @override
  Future<void> deleteDebt(String id) async => calls.add('deleteDebt $id');

  @override
  Future<DebtPayment> addDebtPayment({required String debtId, required double amount, required String? walletId, required String paidOn}) async {
    calls.add('addDebtPayment $debtId $amount');
    return DebtPayment(id: _next('p'), debtId: debtId, amount: amount, walletId: walletId, paidOn: paidOn, note: '', createdAt: '');
  }

  @override
  Future<void> deleteDebtPayment(String id) async => calls.add('deleteDebtPayment $id');

  // ---- recurring entries: one entry per rule and date, like the database's unique pair
  final logged = <String>{};

  /// Dates another device logged first (the insert comes back refused).
  final loggedElsewhere = <String>{};

  @override
  Future<RecurringRule> addRecurring(Map<String, dynamic> row) async {
    calls.add('addRecurring ${row['name']} next ${row['next_on']}');
    return RecurringRule.fromRow({...row, 'id': _next('r'), 'created_at': ''});
  }

  @override
  Future<void> updateRecurring(String id, Map<String, dynamic> patch) async => calls.add('updateRecurring $id $patch');

  @override
  Future<void> deleteRecurring(String id) async => calls.add('deleteRecurring $id');

  @override
  Future<Txn?> logRecurring(String ruleId, String date, NewTxn t) async {
    if (loggedElsewhere.contains('$ruleId $date') || !logged.add('$ruleId $date')) {
      calls.add('logRecurring $ruleId $date (already there)');
      return null;
    }
    calls.add('logRecurring $ruleId $date');
    return Txn.fromRow({...t.toRow(), 'id': _next('tx'), 'created_at': '', 'recurring_id': ruleId, 'recurring_on': date});
  }

  @override
  Future<void> advanceRecurring(String id, String nextOn) async => calls.add('advanceRecurring $id $nextOn');

  @override
  Future<Challenge> addChallenge(Challenge c) async {
    calls.add('addChallenge ${challengeKindNames[c.kind]}');
    return Challenge.fromRow({...c.toRow(), 'id': _next('ch'), 'created_at': ''});
  }

  @override
  Future<void> deleteChallenge(String id) async => calls.add('deleteChallenge $id');
}

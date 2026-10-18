// The database calls behind bills, wallets, transfers, dhar, recurring entries
// and challenges, as one object AppState holds — so tests can stand in a fake and
// check the rules (a bill payment rolls the bill on, a paid-off debt closes
// itself, a recurring date is logged once…) without a server.
import '../models.dart';
import 'repo.dart';

class MoneyDb {
  const MoneyDb();

  Future<Bill> addBill({
    required String name,
    required double amount,
    required String dueOn,
    required String recurrence,
    String? categoryId,
    String? walletId,
  }) =>
      Repo.addBill(name: name, amount: amount, dueOn: dueOn, recurrence: recurrence, categoryId: categoryId, walletId: walletId);

  Future<void> setBillPaid(String id, bool paid) => Repo.setBillPaid(id, paid);
  Future<void> updateBill(String id, Map<String, dynamic> patch) => Repo.updateBill(id, patch);
  Future<void> deleteBill(String id) => Repo.deleteBill(id);

  Future<Wallet> addWallet({
    required String name,
    required WalletKind kind,
    required String color,
    required double openingBalance,
    required int sort,
  }) =>
      Repo.addWallet(name: name, kind: kind, color: color, openingBalance: openingBalance, sort: sort);

  Future<void> updateWallet(String id, Map<String, dynamic> patch) => Repo.updateWallet(id, patch);
  Future<void> deleteWallet(String id) => Repo.deleteWallet(id);

  Future<Transfer> addTransfer({
    required String fromWallet,
    required String toWallet,
    required double amount,
    required String note,
    required String occurredOn,
    required String occurredAt,
  }) =>
      Repo.addTransfer(fromWallet: fromWallet, toWallet: toWallet, amount: amount, note: note, occurredOn: occurredOn, occurredAt: occurredAt);

  Future<void> deleteTransfer(String id) => Repo.deleteTransfer(id);

  Future<Debt> addDebt({
    required String person,
    required DebtDirection direction,
    required double amount,
    required String note,
    required String? walletId,
    required String occurredOn,
    required String? dueOn,
  }) =>
      Repo.addDebt(person: person, direction: direction, amount: amount, note: note, walletId: walletId, occurredOn: occurredOn, dueOn: dueOn);

  Future<void> updateDebt(String id, Map<String, dynamic> patch) => Repo.updateDebt(id, patch);
  Future<void> deleteDebt(String id) => Repo.deleteDebt(id);

  Future<DebtPayment> addDebtPayment({required String debtId, required double amount, required String? walletId, required String paidOn}) =>
      Repo.addDebtPayment(debtId: debtId, amount: amount, walletId: walletId, paidOn: paidOn);

  Future<void> deleteDebtPayment(String id) => Repo.deleteDebtPayment(id);

  Future<RecurringRule> addRecurring(Map<String, dynamic> row) => Repo.addRecurring(row);
  Future<void> updateRecurring(String id, Map<String, dynamic> patch) => Repo.updateRecurring(id, patch);
  Future<void> deleteRecurring(String id) => Repo.deleteRecurring(id);

  /// Null when the date was already logged (by the web, the reminders job or another phone).
  Future<Txn?> logRecurring(String ruleId, String date, NewTxn t) => Repo.logRecurring(ruleId, date, t);
  Future<void> advanceRecurring(String id, String nextOn) => Repo.advanceRecurring(id, nextOn);

  Future<Challenge> addChallenge(Challenge c) => Repo.addChallenge(c);
  Future<void> deleteChallenge(String id) => Repo.deleteChallenge(id);
}

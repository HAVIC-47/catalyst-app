// Supabase data access — mirrors src/lib/db/* of the web app (same tables,
// columns and ordering). Every table is RLS-scoped to auth.uid().
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

SupabaseClient get _db => Supabase.instance.client;

class Repo {
  /// The rows each list call last returned, by table — the offline copy
  /// (data/offline.dart) is made from these, and read back with the same fromRow.
  static final lastRows = <String, List<Map<String, dynamic>>>{};

  static T Function(Map<String, dynamic>) _keep<T>(String table, T Function(Map<String, dynamic>) fromRow) {
    final rows = lastRows[table] = [];
    return (r) {
      rows.add(r);
      return fromRow(r);
    };
  }

  // ---- categories
  static Future<List<Category>> listCategories() async {
    final rows = await _db
        .from('categories')
        .select()
        .order('kind', ascending: true)
        .order('sort', ascending: true)
        .order('name', ascending: true);
    return rows.map(_keep('categories', Category.fromRow)).toList();
  }

  static Future<Category> addCategory({required String name, required Kind kind, required String color, required int sort}) async {
    final row = await _db
        .from('categories')
        .insert({'name': name, 'kind': kind.name, 'color': color, 'sort': sort})
        .select()
        .single();
    return Category.fromRow(row);
  }

  static Future<void> updateCategory(String id, {String? name, String? color}) async {
    await _db.from('categories').update({'name': ?name, 'color': ?color}).eq('id', id);
  }

  static Future<void> deleteCategory(String id) => _db.from('categories').delete().eq('id', id);

  /// Seed the default category set for a brand-new user (only when they have none).
  static Future<List<Category>> seedDefaultCategories() async {
    final rows = [
      for (final (i, c) in defaultExpenseCategories.indexed) {'name': c.$1, 'kind': 'expense', 'color': c.$2, 'sort': i},
      for (final (i, c) in defaultIncomeCategories.indexed) {'name': c.$1, 'kind': 'income', 'color': c.$2, 'sort': i},
    ];
    final data = await _db.from('categories').insert(rows).select();
    return data.map(Category.fromRow).toList();
  }

  // ---- transactions
  static Future<List<Txn>> listTransactions() async {
    final rows = await _db
        .from('transactions')
        .select()
        .order('occurred_on', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(_keep('transactions', Txn.fromRow)).toList();
  }

  /// [id] lets an entry made offline keep its own id, so a retried sync never adds it twice.
  static Future<Txn> addTransaction(NewTxn t, {String? id}) async =>
      Txn.fromRow(await _db.from('transactions').insert({...t.toRow(), 'id': ?id}).select().single());

  /// Replaces every editable field of a transaction (the ledger's edit button).
  static Future<Txn> updateTransaction(String id, NewTxn t) async =>
      Txn.fromRow(await _db.from('transactions').update(t.toRow()).eq('id', id).select().single());

  static Future<void> deleteTransaction(String id) => _db.from('transactions').delete().eq('id', id);

  // ---- moods
  static Future<List<MoodLog>> listMoods() async {
    final rows = await _db.from('mood_logs').select().order('created_at', ascending: false);
    return rows.map(_keep('mood_logs', MoodLog.fromRow)).toList();
  }

  /// Multiple moods per day allowed — each save is a new timestamped log.
  static Future<MoodLog> addMood({
    required int mood,
    required String note,
    required List<String> tags,
    required String loggedOn,
    required String loggedAt,
    String? id, // see addTransaction
  }) async {
    final row = await _db
        .from('mood_logs')
        .insert({'mood': mood, 'note': note, 'tags': tags, 'logged_on': loggedOn, 'logged_at': loggedAt, 'id': ?id})
        .select()
        .single();
    return MoodLog.fromRow(row);
  }

  // ---- budgets
  static Future<List<Budget>> listBudgets() async =>
      (await _db.from('budgets').select()).map(_keep('budgets', Budget.fromRow)).toList();

  static Future<Budget> addBudget({required String? categoryId, required String categoryName, required double amount}) async {
    final row = await _db
        .from('budgets')
        .insert({'category_id': categoryId, 'category_name': categoryName, 'amount': amount, 'period': 'monthly'})
        .select()
        .single();
    return Budget.fromRow(row);
  }

  static Future<void> updateBudget(String id, double amount) => _db.from('budgets').update({'amount': amount}).eq('id', id);

  static Future<void> deleteBudget(String id) => _db.from('budgets').delete().eq('id', id);

  // ---- goals
  static Future<List<Goal>> listGoals() async =>
      (await _db.from('goals').select().order('created_at', ascending: true)).map(_keep('goals', Goal.fromRow)).toList();

  static Future<Goal> addGoal({required String title, required double target, required String? dueOn}) async {
    final row = await _db
        .from('goals')
        .insert({'title': title, 'target_amount': target, 'saved_amount': 0, 'due_on': dueOn})
        .select()
        .single();
    return Goal.fromRow(row);
  }

  static Future<void> updateGoalSaved(String id, double saved) =>
      _db.from('goals').update({'saved_amount': saved}).eq('id', id);

  static Future<void> deleteGoal(String id) => _db.from('goals').delete().eq('id', id);

  // ---- bills
  static Future<List<Bill>> listBills() async =>
      (await _db.from('bills').select().order('due_on', ascending: true)).map(_keep('bills', Bill.fromRow)).toList();

  static Future<Bill> addBill({
    required String name,
    required double amount,
    required String dueOn,
    required String recurrence,
    String? categoryId,
    String? walletId,
  }) async {
    final row = await _db
        .from('bills')
        // Newer columns only when set, so bills still save before the wallets update.
        .insert({
          'name': name,
          'amount': amount,
          'due_on': dueOn,
          'recurrence': recurrence,
          'is_paid': false,
          'category_id': ?categoryId,
          'wallet_id': ?walletId,
        })
        .select()
        .single();
    return Bill.fromRow(row);
  }

  static Future<void> setBillPaid(String id, bool paid) => _db.from('bills').update({'is_paid': paid}).eq('id', id);

  static Future<void> updateBill(String id, Map<String, dynamic> patch) => _db.from('bills').update(patch).eq('id', id);

  static Future<void> deleteBill(String id) => _db.from('bills').delete().eq('id', id);

  // ---- journal
  static Future<List<JournalEntry>> listJournal() async => (await _db
          .from('journal_entries')
          .select()
          .order('entry_on', ascending: false)
          .order('created_at', ascending: false))
      .map(_keep('journal_entries', JournalEntry.fromRow))
      .toList();

  static Future<JournalEntry> addJournal({required String entryOn, required int? mood, required String title, required String body}) async {
    final row = await _db
        .from('journal_entries')
        .insert({'entry_on': entryOn, 'mood': mood, 'title': title, 'body': body})
        .select()
        .single();
    return JournalEntry.fromRow(row);
  }

  static Future<void> deleteJournal(String id) => _db.from('journal_entries').delete().eq('id', id);

  // ---- activities (custom daily habits) + their logs
  static Future<List<Activity>> listActivities() async =>
      (await _db.from('activities').select().order('sort', ascending: true)).map(_keep('activities', Activity.fromRow)).toList();

  static Future<Activity> addActivity({required String name, required String color, required int sort}) async {
    final row = await _db.from('activities').insert({'name': name, 'color': color, 'sort': sort}).select().single();
    return Activity.fromRow(row);
  }

  static Future<void> deleteActivity(String id) => _db.from('activities').delete().eq('id', id);

  static Future<List<ActivityLog>> listActivityLogs() async =>
      (await _db.from('activity_logs').select()).map(_keep('activity_logs', ActivityLog.fromRow)).toList();

  static Future<ActivityLog> addActivityLog(String activityId, String loggedOn) async {
    final row = await _db
        .from('activity_logs')
        .insert({'user_id': _db.auth.currentUser?.id, 'activity_id': activityId, 'logged_on': loggedOn, 'value': 'done'})
        .select()
        .single();
    return ActivityLog.fromRow(row);
  }

  static Future<void> deleteActivityLog(String id) => _db.from('activity_logs').delete().eq('id', id);

  // ---- boards (to-do + to-buy), their columns and tickets
  static Future<List<Board>> listBoards() async => (await _db
          .from('boards')
          .select()
          .order('sort', ascending: true)
          .order('created_at', ascending: true))
      .map(_keep('boards', Board.fromRow))
      .toList();

  static Future<Board> addBoard({required String name, required BoardKind kind, required int sort}) async =>
      Board.fromRow(await _db.from('boards').insert({'name': name, 'kind': kind.name, 'sort': sort}).select().single());

  static Future<void> renameBoard(String id, String name) => _db.from('boards').update({'name': name}).eq('id', id);

  /// The database removes the board's columns and tickets too.
  static Future<void> deleteBoard(String id) => _db.from('boards').delete().eq('id', id);

  static Future<List<BoardColumn>> listBoardColumns() async =>
      (await _db.from('board_columns').select().order('sort', ascending: true)).map(_keep('board_columns', BoardColumn.fromRow)).toList();

  static Future<List<BoardColumn>> addBoardColumns(String boardId, List<(String, int)> columns) async {
    final rows = await _db
        .from('board_columns')
        .insert([for (final (name, sort) in columns) {'board_id': boardId, 'name': name, 'sort': sort}])
        .select();
    return rows.map(BoardColumn.fromRow).toList()..sort((a, b) => a.sort.compareTo(b.sort));
  }

  static Future<void> updateBoardColumn(String id, {String? name, int? sort}) =>
      _db.from('board_columns').update({'name': ?name, 'sort': ?sort}).eq('id', id);

  /// The database removes the column's tickets too.
  static Future<void> deleteBoardColumn(String id) => _db.from('board_columns').delete().eq('id', id);

  static Future<List<Ticket>> listTickets() async =>
      (await _db.from('tickets').select().order('sort', ascending: true)).map(_keep('tickets', Ticket.fromRow)).toList();

  static Future<Ticket> addTicket(Map<String, dynamic> row) async =>
      Ticket.fromRow(await _db.from('tickets').insert(row).select().single());

  /// Several at once (a scanned list), in number order.
  static Future<List<Ticket>> addTickets(List<Map<String, dynamic>> rows) async =>
      (await _db.from('tickets').insert(rows).select()).map(Ticket.fromRow).toList()..sort((a, b) => a.number.compareTo(b.number));

  static Future<void> updateTicket(String id, Map<String, dynamic> patch) => _db.from('tickets').update(patch).eq('id', id);

  static Future<void> deleteTicket(String id) => _db.from('tickets').delete().eq('id', id);

  static Future<void> deleteTickets(List<String> ids) => _db.from('tickets').delete().inFilter('id', ids);

  // ---- wallets + transfers (need the database's wallets update)
  static Future<List<Wallet>> listWallets() async => (await _db
          .from('wallets')
          .select()
          .order('sort', ascending: true)
          .order('created_at', ascending: true))
      .map(_keep('wallets', Wallet.fromRow))
      .toList();

  static Future<Wallet> addWallet({
    required String name,
    required WalletKind kind,
    required String color,
    required double openingBalance,
    required int sort,
  }) async =>
      Wallet.fromRow(await _db
          .from('wallets')
          .insert({'name': name, 'kind': kind.name, 'color': color, 'opening_balance': openingBalance, 'sort': sort})
          .select()
          .single());

  /// Cash, bKash, Nagad and Bank, for an account that has no wallets yet.
  static Future<List<Wallet>> seedDefaultWallets() async {
    final rows = await _db
        .from('wallets')
        .insert([for (final (i, w) in defaultWallets.indexed) {'name': w.$1, 'kind': w.$2.name, 'color': w.$3, 'sort': i}])
        .select();
    return rows.map(Wallet.fromRow).toList()..sort((a, b) => a.sort.compareTo(b.sort));
  }

  static Future<void> updateWallet(String id, Map<String, dynamic> patch) => _db.from('wallets').update(patch).eq('id', id);

  /// Its entries move to the default wallet; its transfers go with it.
  static Future<void> deleteWallet(String id) => _db.from('wallets').delete().eq('id', id);

  static Future<List<Transfer>> listTransfers() async => (await _db
          .from('transfers')
          .select()
          .order('occurred_on', ascending: false)
          .order('created_at', ascending: false))
      .map(_keep('transfers', Transfer.fromRow))
      .toList();

  static Future<Transfer> addTransfer({
    required String fromWallet,
    required String toWallet,
    required double amount,
    required String note,
    required String occurredOn,
    required String occurredAt,
  }) async =>
      Transfer.fromRow(await _db
          .from('transfers')
          .insert({
            'from_wallet': fromWallet,
            'to_wallet': toWallet,
            'amount': amount,
            'note': note,
            'occurred_on': occurredOn,
            'occurred_at': occurredAt,
          })
          .select()
          .single());

  static Future<void> deleteTransfer(String id) => _db.from('transfers').delete().eq('id', id);

  // ---- dhar / baki
  static Future<List<Debt>> listDebts() async =>
      (await _db.from('debts').select().order('created_at', ascending: false)).map(_keep('debts', Debt.fromRow)).toList();

  static Future<Debt> addDebt({
    required String person,
    required DebtDirection direction,
    required double amount,
    required String note,
    required String? walletId,
    required String occurredOn,
    required String? dueOn,
  }) async =>
      Debt.fromRow(await _db
          .from('debts')
          .insert({
            'person': person,
            'direction': direction.name,
            'amount': amount,
            'note': note,
            'wallet_id': walletId,
            'occurred_on': occurredOn,
            'due_on': dueOn,
          })
          .select()
          .single());

  static Future<void> updateDebt(String id, Map<String, dynamic> patch) => _db.from('debts').update(patch).eq('id', id);

  /// Its payments go with it.
  static Future<void> deleteDebt(String id) => _db.from('debts').delete().eq('id', id);

  static Future<List<DebtPayment>> listDebtPayments() async =>
      (await _db.from('debt_payments').select().order('paid_on', ascending: true)).map(_keep('debt_payments', DebtPayment.fromRow)).toList();

  static Future<DebtPayment> addDebtPayment({
    required String debtId,
    required double amount,
    required String? walletId,
    required String paidOn,
  }) async =>
      DebtPayment.fromRow(await _db
          .from('debt_payments')
          .insert({'debt_id': debtId, 'amount': amount, 'wallet_id': walletId, 'paid_on': paidOn})
          .select()
          .single());

  static Future<void> deleteDebtPayment(String id) => _db.from('debt_payments').delete().eq('id', id);

  // ---- recurring income and expenses, challenges (need the 1.5 database update)
  static Future<List<RecurringRule>> listRecurring() async =>
      (await _db.from('recurring').select().order('created_at', ascending: true)).map(_keep('recurring', RecurringRule.fromRow)).toList();

  static Future<RecurringRule> addRecurring(Map<String, dynamic> row) async =>
      RecurringRule.fromRow(await _db.from('recurring').insert(row).select().single());

  static Future<void> updateRecurring(String id, Map<String, dynamic> patch) => _db.from('recurring').update(patch).eq('id', id);

  /// Its entries stay; the database forgets which rule logged them.
  static Future<void> deleteRecurring(String id) => _db.from('recurring').delete().eq('id', id);

  /// Logs one of a rule's dates. Null when that date is already in the ledger —
  /// the database keeps one entry per rule and date, whoever logs it first.
  static Future<Txn?> logRecurring(String ruleId, String date, NewTxn t) async {
    try {
      return Txn.fromRow(await _db.from('transactions').insert({...t.toRow(), 'recurring_id': ruleId, 'recurring_on': date}).select().single());
    } on PostgrestException catch (e) {
      if (e.code == '23505') return null;
      rethrow;
    }
  }

  /// Moves a rule on to [nextOn] — never back, if another device got further first.
  static Future<void> advanceRecurring(String id, String nextOn) =>
      _db.from('recurring').update({'next_on': nextOn}).eq('id', id).lt('next_on', nextOn);

  static Future<List<Challenge>> listChallenges() async => (await _db
          .from('challenges')
          .select()
          .order('start_on', ascending: false)
          .order('created_at', ascending: false))
      .map(_keep('challenges', Challenge.fromRow))
      .toList();

  static Future<Challenge> addChallenge(Challenge c) async => Challenge.fromRow(await _db.from('challenges').insert(c.toRow()).select().single());

  static Future<void> deleteChallenge(String id) => _db.from('challenges').delete().eq('id', id);

  // ---- UI preferences (auth user metadata — shared with the web app)
  static Future<Map<String, dynamic>> loadPrefs() async {
    final res = await _db.auth.getUser();
    return res.user?.userMetadata ?? const {};
  }

  static Future<void> savePrefs(Map<String, dynamic> patch) async {
    await _db.auth.updateUser(UserAttributes(data: patch));
  }
}

// Supabase data access — mirrors src/lib/db/* of the web app (same tables,
// columns and ordering). Every table is RLS-scoped to auth.uid().
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

SupabaseClient get _db => Supabase.instance.client;

class Repo {
  // ---- categories
  static Future<List<Category>> listCategories() async {
    final rows = await _db
        .from('categories')
        .select()
        .order('kind', ascending: true)
        .order('sort', ascending: true)
        .order('name', ascending: true);
    return rows.map(Category.fromRow).toList();
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
    return rows.map(Txn.fromRow).toList();
  }

  static Future<Txn> addTransaction(NewTxn t) async =>
      Txn.fromRow(await _db.from('transactions').insert(t.toRow()).select().single());

  static Future<void> deleteTransaction(String id) => _db.from('transactions').delete().eq('id', id);

  // ---- moods
  static Future<List<MoodLog>> listMoods() async {
    final rows = await _db.from('mood_logs').select().order('created_at', ascending: false);
    return rows.map(MoodLog.fromRow).toList();
  }

  /// Multiple moods per day allowed — each save is a new timestamped log.
  static Future<MoodLog> addMood({
    required int mood,
    required String note,
    required List<String> tags,
    required String loggedOn,
    required String loggedAt,
  }) async {
    final row = await _db
        .from('mood_logs')
        .insert({'mood': mood, 'note': note, 'tags': tags, 'logged_on': loggedOn, 'logged_at': loggedAt})
        .select()
        .single();
    return MoodLog.fromRow(row);
  }

  // ---- budgets
  static Future<List<Budget>> listBudgets() async =>
      (await _db.from('budgets').select()).map(Budget.fromRow).toList();

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
      (await _db.from('goals').select().order('created_at', ascending: true)).map(Goal.fromRow).toList();

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
      (await _db.from('bills').select().order('due_on', ascending: true)).map(Bill.fromRow).toList();

  static Future<Bill> addBill({required String name, required double amount, required String dueOn, required String recurrence}) async {
    final row = await _db
        .from('bills')
        .insert({'name': name, 'amount': amount, 'due_on': dueOn, 'recurrence': recurrence, 'is_paid': false})
        .select()
        .single();
    return Bill.fromRow(row);
  }

  static Future<void> setBillPaid(String id, bool paid) => _db.from('bills').update({'is_paid': paid}).eq('id', id);

  static Future<void> deleteBill(String id) => _db.from('bills').delete().eq('id', id);

  // ---- journal
  static Future<List<JournalEntry>> listJournal() async => (await _db
          .from('journal_entries')
          .select()
          .order('entry_on', ascending: false)
          .order('created_at', ascending: false))
      .map(JournalEntry.fromRow)
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
      (await _db.from('activities').select().order('sort', ascending: true)).map(Activity.fromRow).toList();

  static Future<Activity> addActivity({required String name, required String color, required int sort}) async {
    final row = await _db.from('activities').insert({'name': name, 'color': color, 'sort': sort}).select().single();
    return Activity.fromRow(row);
  }

  static Future<void> deleteActivity(String id) => _db.from('activities').delete().eq('id', id);

  static Future<List<ActivityLog>> listActivityLogs() async =>
      (await _db.from('activity_logs').select()).map(ActivityLog.fromRow).toList();

  static Future<ActivityLog> addActivityLog(String activityId, String loggedOn) async {
    final row = await _db
        .from('activity_logs')
        .insert({'user_id': _db.auth.currentUser?.id, 'activity_id': activityId, 'logged_on': loggedOn, 'value': 'done'})
        .select()
        .single();
    return ActivityLog.fromRow(row);
  }

  static Future<void> deleteActivityLog(String id) => _db.from('activity_logs').delete().eq('id', id);

  // ---- UI preferences (auth user metadata — shared with the web app)
  static Future<Map<String, dynamic>> loadPrefs() async {
    final res = await _db.auth.getUser();
    return res.user?.userMetadata ?? const {};
  }

  static Future<void> savePrefs(Map<String, dynamic> patch) async {
    await _db.auth.updateUser(UserAttributes(data: patch));
  }
}

// Central client store — port of the web app's AppDataProvider (use-app-data.tsx).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'repo.dart';

// Key for the hidden dashboard sections, both locally and in user metadata.
const _dashboardHiddenKey = 'dashboardHidden';
final _sectionIds = {for (final s in dashboardSections) s.$1};

class AppState extends ChangeNotifier {
  bool loading = true;
  bool _started = false;

  List<Category> categories = [];
  List<Txn> transactions = [];
  List<MoodLog> moods = [];
  List<Budget> budgets = [];
  List<Goal> goals = [];
  List<Bill> bills = [];
  List<JournalEntry> journal = [];
  List<Activity> activities = [];
  List<ActivityLog> activityLogs = [];

  /// Vault Mode: every income also adds to the savings pool and every expense
  /// draws from it, so savings reflect true net flow. (Per device, like the web.)
  bool vaultMode = false;

  /// Dashboard sections hidden in Settings (null until read). Hiding only
  /// changes what the dashboard renders — the data behind it is untouched.
  List<String>? dashboardHidden;
  bool _dashboardTouched = false;
  Future<void> _dashboardSave = Future.value();

  /// Load everything once per signed-in session.
  Future<void> ensureLoaded() async {
    if (_started) return;
    _started = true;
    await load();
  }

  Future<T> _safe<T>(Future<T> Function() fn, T fallback, String name) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('[catalyst] could not load $name: $e');
      return fallback;
    }
  }

  /// (Re)load every collection — each one independently, so one missing table
  /// degrades gracefully instead of breaking the whole app.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    vaultMode = prefs.getBool('vaultMode') ?? false;
    if (dashboardHidden == null) {
      dashboardHidden = _parseHidden(_decode(prefs.getString(_dashboardHiddenKey))) ?? [];
      notifyListeners();
      unawaited(_loadRemotePrefs(prefs));
    }

    final results = await Future.wait<Object>([
      _safe(Repo.listCategories, <Category>[], 'categories'),
      _safe(Repo.listTransactions, <Txn>[], 'transactions'),
      _safe(Repo.listMoods, <MoodLog>[], 'moods'),
      _safe(Repo.listBudgets, <Budget>[], 'budgets'),
      _safe(Repo.listGoals, <Goal>[], 'goals'),
      _safe(Repo.listBills, <Bill>[], 'bills'),
      _safe(Repo.listJournal, <JournalEntry>[], 'journal'),
      _safe(Repo.listActivities, <Activity>[], 'activities'),
      _safe(Repo.listActivityLogs, <ActivityLog>[], 'activityLogs'),
    ]);

    var cats = results[0] as List<Category>;
    if (cats.isEmpty) cats = await _safe(Repo.seedDefaultCategories, <Category>[], 'seedCategories');
    // Defensive de-dupe by kind+name (hides duplicate rows from older double-seeds).
    final seen = <String>{};
    cats = cats.where((c) => seen.add('${c.kind.name}:${c.name.toLowerCase()}')).toList();
    // Ensure the special "Break saving" expense category exists.
    final hasBreak = cats.any((c) => c.kind == Kind.expense && c.name.toLowerCase() == breakSaving.toLowerCase());
    if (!hasBreak) {
      try {
        cats = [
          ...cats,
          await Repo.addCategory(
            name: breakSaving,
            kind: Kind.expense,
            color: '#3D80BC',
            sort: cats.where((c) => c.kind == Kind.expense).length,
          ),
        ];
      } catch (e) {
        debugPrint('[catalyst] could not ensure Break saving category: $e');
      }
    }

    categories = cats;
    transactions = results[1] as List<Txn>;
    moods = results[2] as List<MoodLog>;
    budgets = results[3] as List<Budget>;
    goals = results[4] as List<Goal>;
    bills = results[5] as List<Bill>;
    journal = results[6] as List<JournalEntry>;
    activities = results[7] as List<Activity>;
    activityLogs = results[8] as List<ActivityLog>;
    loading = false;
    notifyListeners();
  }

  /// Forget everything (sign-out).
  void reset() {
    _started = false;
    loading = true;
    categories = [];
    transactions = [];
    moods = [];
    budgets = [];
    goals = [];
    bills = [];
    journal = [];
    activities = [];
    activityLogs = [];
    dashboardHidden = null;
    _dashboardTouched = false;
    notifyListeners();
  }

  // ---- preferences
  Future<void> setVaultMode(bool on) async {
    vaultMode = on;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('vaultMode', on);
  }

  Future<void> _loadRemotePrefs(SharedPreferences prefs) async {
    try {
      final meta = await Repo.loadPrefs();
      if (_dashboardTouched) return;
      final remote = _parseHidden(meta[_dashboardHiddenKey]) ?? [];
      dashboardHidden = remote;
      prefs.setString(_dashboardHiddenKey, jsonEncode(remote));
      notifyListeners();
    } catch (e) {
      debugPrint('[catalyst] could not load preferences: $e');
    }
  }

  void setDashboardHidden(List<String> ids) {
    _dashboardTouched = true;
    dashboardHidden = ids;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString(_dashboardHiddenKey, jsonEncode(ids)));
    // Chain saves so rapid toggles reach the server in order (last write wins).
    _dashboardSave = _dashboardSave
        .then((_) => Repo.savePrefs({_dashboardHiddenKey: ids}))
        .catchError((Object e) => debugPrint('[catalyst] could not save preferences: $e'));
  }

  static Object? _decode(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static List<String>? _parseHidden(Object? raw) =>
      raw is List ? raw.whereType<String>().where(_sectionIds.contains).toList() : null;

  // ---- money / mood
  Future<void> addMoney(NewTxn t) async {
    final c = await Repo.addTransaction(t);
    transactions = [c, ...transactions]..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    notifyListeners();
  }

  Future<void> removeMoney(String id) async {
    await Repo.deleteTransaction(id);
    transactions = transactions.where((t) => t.id != id).toList();
    notifyListeners();
  }

  Future<void> saveMood({required int mood, required String note, required List<String> tags, required String loggedOn, required String loggedAt}) async {
    final s = await Repo.addMood(mood: mood, note: note, tags: tags, loggedOn: loggedOn, loggedAt: loggedAt);
    moods = [s, ...moods]..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    notifyListeners();
  }

  List<MoodLog> moodsForDate(String key) =>
      moods.where((m) => m.loggedOn == key).toList()..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

  // ---- categories
  Future<void> createCategory({required String name, required Kind kind, required String color, required int sort}) async {
    final x = await Repo.addCategory(name: name, kind: kind, color: color, sort: sort);
    categories = [...categories, x];
    notifyListeners();
  }

  Future<void> editCategory(String id, {String? name, String? color}) async {
    await Repo.updateCategory(id, name: name, color: color);
    categories = [for (final c in categories) c.id == id ? c.copyWith(name: name, color: color) : c];
    notifyListeners();
  }

  Future<void> removeCategory(String id) async {
    await Repo.deleteCategory(id);
    categories = categories.where((c) => c.id != id).toList();
    notifyListeners();
  }

  // ---- budgets
  Future<void> createBudget(Category cat, double amount) async {
    final x = await Repo.addBudget(categoryId: cat.id, categoryName: cat.name, amount: amount);
    budgets = [...budgets, x];
    notifyListeners();
  }

  Future<void> editBudget(String id, double amount) async {
    await Repo.updateBudget(id, amount);
    budgets = [for (final b in budgets) b.id == id ? b.copyWith(amount: amount) : b];
    notifyListeners();
  }

  Future<void> removeBudget(String id) async {
    await Repo.deleteBudget(id);
    budgets = budgets.where((b) => b.id != id).toList();
    notifyListeners();
  }

  // ---- goals
  Future<void> createGoal(String title, double target, String? dueOn) async {
    final x = await Repo.addGoal(title: title, target: target, dueOn: dueOn);
    goals = [...goals, x];
    notifyListeners();
  }

  Future<void> addToGoal(Goal g, double amount) async {
    final saved = (g.savedAmount + amount).clamp(0, double.infinity).toDouble();
    await Repo.updateGoalSaved(g.id, saved);
    goals = [for (final x in goals) x.id == g.id ? x.copyWith(savedAmount: saved) : x];
    notifyListeners();
  }

  Future<void> removeGoal(String id) async {
    await Repo.deleteGoal(id);
    goals = goals.where((g) => g.id != id).toList();
    notifyListeners();
  }

  // ---- bills
  Future<void> createBill(String name, double amount, String dueOn, String recurrence) async {
    final x = await Repo.addBill(name: name, amount: amount, dueOn: dueOn, recurrence: recurrence);
    bills = [...bills, x]..sort((a, b) => a.dueOn.compareTo(b.dueOn));
    notifyListeners();
  }

  Future<void> toggleBillPaid(Bill b) async {
    await Repo.setBillPaid(b.id, !b.isPaid);
    bills = [for (final x in bills) x.id == b.id ? x.copyWith(isPaid: !b.isPaid) : x];
    notifyListeners();
  }

  Future<void> removeBill(String id) async {
    await Repo.deleteBill(id);
    bills = bills.where((b) => b.id != id).toList();
    notifyListeners();
  }

  // ---- journal
  Future<void> createJournal({required String entryOn, required int? mood, required String title, required String body}) async {
    final x = await Repo.addJournal(entryOn: entryOn, mood: mood, title: title, body: body);
    journal = [x, ...journal]..sort((a, b) => b.entryOn.compareTo(a.entryOn));
    notifyListeners();
  }

  Future<void> removeJournal(String id) async {
    await Repo.deleteJournal(id);
    journal = journal.where((j) => j.id != id).toList();
    notifyListeners();
  }

  // ---- activities
  Future<void> createActivity(String name, String color) async {
    final x = await Repo.addActivity(name: name, color: color, sort: activities.length);
    activities = [...activities, x];
    notifyListeners();
  }

  Future<void> removeActivity(String id) async {
    await Repo.deleteActivity(id);
    activities = activities.where((a) => a.id != id).toList();
    activityLogs = activityLogs.where((l) => l.activityId != id).toList();
    notifyListeners();
  }

  Future<void> toggleActivity(String activityId, String dateKey) async {
    final existing = activityLogs.where((l) => l.activityId == activityId && l.loggedOn == dateKey).firstOrNull;
    if (existing != null) {
      await Repo.deleteActivityLog(existing.id);
      activityLogs = activityLogs.where((l) => l.id != existing.id).toList();
    } else {
      final x = await Repo.addActivityLog(activityId, dateKey);
      activityLogs = [...activityLogs, x];
    }
    notifyListeners();
  }
}

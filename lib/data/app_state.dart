// Central client store — port of the web app's AppDataProvider (use-app-data.tsx).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../models.dart';
import '../util/currency.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/money.dart';
import 'money_db.dart';
import 'offline.dart';
import 'repo.dart';

// Key for the hidden dashboard sections, both locally and in user metadata.
const _dashboardHiddenKey = 'dashboardHidden';
final _sectionIds = {for (final s in dashboardSections) s.$1};

/// Categories in the database's order: by kind, then their sort number, then
/// name. A new category gets the lowest number of its kind, so it comes first.
List<Category> orderCategories(Iterable<Category> list) => [...list]
  ..sort((a, b) {
    final kind = a.kind.name.compareTo(b.kind.name);
    if (kind != 0) return kind;
    final sort = a.sort.compareTo(b.sort);
    return sort != 0 ? sort : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// Reminder settings — in the account's preferences, so the web, this app and
/// the web's reminders job all follow the same ones (the web's lib/reminders.ts).
class ReminderPrefs {
  const ReminderPrefs({this.checkin = true, this.checkinTime = '21:00', this.bills = true, this.budgets = true, this.dhar = true});

  final bool checkin; // evening "how was today?"
  final String checkinTime; // HH:mm, local
  final bool bills; // the day before a bill is due
  final bool budgets; // at 80% and 100% of a monthly budget
  final bool dhar; // the day before money lent or borrowed is due back

  factory ReminderPrefs.fromJson(Object? raw) {
    final r = raw is Map ? raw : const {};
    bool flag(String k, bool d) => r[k] is bool ? r[k] as bool : d;
    final t = r['checkinTime'];
    return ReminderPrefs(
      checkin: flag('checkin', true),
      checkinTime: t is String && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t) ? t : '21:00',
      bills: flag('bills', true),
      budgets: flag('budgets', true),
      dhar: flag('dhar', true),
    );
  }

  Map<String, dynamic> toJson() => {'checkin': checkin, 'checkinTime': checkinTime, 'bills': bills, 'budgets': budgets, 'dhar': dhar};

  ReminderPrefs copyWith({bool? checkin, String? checkinTime, bool? bills, bool? budgets, bool? dhar}) => ReminderPrefs(
        checkin: checkin ?? this.checkin,
        checkinTime: checkinTime ?? this.checkinTime,
        bills: bills ?? this.bills,
        budgets: budgets ?? this.budgets,
        dhar: dhar ?? this.dhar,
      );
}

/// What paying a bill changed, so Undo can put it back.
typedef BillPayment = ({String billId, String txnId, String dueOn, bool isPaid, String? lastPaidTxn});

class AppState extends ChangeNotifier {
  /// The database calls behind bills, wallets, transfers and dhar (tests swap it).
  MoneyDb db = const MoneyDb();

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
  List<Board> boards = [];
  List<BoardColumn> boardColumns = [];
  List<Ticket> tickets = [];
  List<Wallet> wallets = [];
  List<Transfer> transfers = [];
  List<Debt> debts = [];
  List<DebtPayment> debtPayments = [];

  /// False until the database has the wallets update (db/supabase.sql).
  bool walletsReady = false;

  /// The account's currency (BDT unless changed in Settings — shared with the web).
  String currency = 'BDT';

  /// Reminder settings (shared with the web).
  ReminderPrefs reminders = const ReminderPrefs();

  /// The interface language, 'en' or 'bn' (shared with the web).
  String lang = appLang;

  /// Short notices for the screen (budget alerts, offline saves); the shell shows them.
  final notices = StreamController<String>.broadcast();

  /// True while the app shows the copy saved on this phone (no connection at the
  /// last load), from [offlineSince].
  bool offline = false;
  DateTime? offlineSince;
  Timer? _retry;
  final Set<String> _offlineFails = {};

  /// Entries and moods made offline, still waiting to be sent.
  int get unsent => Outbox.instance.ops.length;
  Set<String> get unsentIds => Outbox.instance.unsentIds;

  final Set<String> _prefsTouched = {};

  /// The board last opened per kind (this device): the boards screen shows it,
  /// and the + scanner adds to it.
  final selectedBoards = <BoardKind, String>{};

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
      if (isOffline(e)) _offlineFails.add(name);
      return fallback;
    }
  }

  /// The signed-in account (null in tests and when signed out).
  static String? get _uid {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// (Re)load every collection — each one independently, so one missing table
  /// degrades gracefully instead of breaking the whole app.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    vaultMode = prefs.getBool('vaultMode') ?? false;
    currency = setCurrency(prefs.getString('currency') ?? currency).code;
    reminders = ReminderPrefs.fromJson(_decode(prefs.getString('reminders')));
    for (final k in BoardKind.values) {
      final id = prefs.getString('board:${k.name}');
      if (id != null) selectedBoards.putIfAbsent(k, () => id);
    }
    if (dashboardHidden == null) {
      dashboardHidden = _parseHidden(_decode(prefs.getString(_dashboardHiddenKey))) ?? [];
      notifyListeners();
      unawaited(_loadRemotePrefs(prefs));
    }

    final uid = _uid;
    if (uid != null) await Outbox.instance.load(uid);
    _offlineFails.clear();
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
      _safe(Repo.listBoards, <Board>[], 'boards'),
      _safe(Repo.listBoardColumns, <BoardColumn>[], 'boardColumns'),
      _safe(Repo.listTickets, <Ticket>[], 'tickets'),
      _loadWallets(),
      _safe(Repo.listTransfers, <Transfer>[], 'transfers'),
      _safe(Repo.listDebts, <Debt>[], 'debts'),
      _safe(Repo.listDebtPayments, <DebtPayment>[], 'debtPayments'),
    ]);

    // No connection: open on the copy saved on this phone, plus what's waiting to be sent.
    if (_offlineFails.contains('transactions') || _offlineFails.contains('categories')) {
      final copy = uid == null ? null : await OfflineCopy.read(uid);
      offline = true;
      offlineSince = copy?.savedAt;
      if (copy != null) _restore(copy.tables, copy.walletsReady);
      _applyOutbox();
      loading = false;
      notifyListeners();
      _startRetry();
      return;
    }
    offline = false;
    offlineSince = null;

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
    boards = results[9] as List<Board>;
    boardColumns = results[10] as List<BoardColumn>;
    tickets = results[11] as List<Ticket>;
    final w = results[12] as (bool, List<Wallet>);
    walletsReady = w.$1;
    wallets = w.$2;
    transfers = results[13] as List<Transfer>;
    debts = results[14] as List<Debt>;
    debtPayments = results[15] as List<DebtPayment>;
    _applyOutbox();
    loading = false;
    notifyListeners();
    if (uid != null) unawaited(OfflineCopy.save(uid, Map.of(Repo.lastRows), walletsReady: walletsReady));
    if (unsent > 0) unawaited(syncOutbox());
    if (unsent == 0) _stopRetry();
  }

  /// The lists from the saved copy's rows (the same fromRow the server's go through).
  void _restore(Map<String, List<Map<String, dynamic>>> t, bool ready) {
    List<T> rows<T>(String table, T Function(Map<String, dynamic>) from) {
      final out = <T>[];
      for (final r in t[table] ?? const <Map<String, dynamic>>[]) {
        try {
          out.add(from(r));
        } catch (_) {}
      }
      return out;
    }

    categories = rows('categories', Category.fromRow);
    transactions = rows('transactions', Txn.fromRow);
    moods = rows('mood_logs', MoodLog.fromRow);
    budgets = rows('budgets', Budget.fromRow);
    goals = rows('goals', Goal.fromRow);
    bills = rows('bills', Bill.fromRow);
    journal = rows('journal_entries', JournalEntry.fromRow);
    activities = rows('activities', Activity.fromRow);
    activityLogs = rows('activity_logs', ActivityLog.fromRow);
    boards = rows('boards', Board.fromRow);
    boardColumns = rows('board_columns', BoardColumn.fromRow);
    tickets = rows('tickets', Ticket.fromRow);
    wallets = rows('wallets', Wallet.fromRow);
    transfers = rows('transfers', Transfer.fromRow);
    debts = rows('debts', Debt.fromRow);
    debtPayments = rows('debt_payments', DebtPayment.fromRow);
    walletsReady = ready && wallets.isNotEmpty;
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// An entry as the phone knows it before the server has it.
  Txn _localTxn(String id, Map<String, dynamic> row, {Txn? was}) =>
      Txn.fromRow({'wallet_id': was?.walletId, ...row, 'id': id, 'created_at': was?.createdAt ?? _nowIso()});

  /// Put the outbox's changes over the lists (they aren't on the server yet).
  void _applyOutbox() {
    final ops = Outbox.instance.ops;
    if (ops.isEmpty) return;
    var txns = [...transactions];
    var logs = [...moods];
    for (final o in ops) {
      switch (o.op) {
        case 'addTxn':
          if (!txns.any((t) => t.id == o.id)) txns.add(_localTxn(o.id, o.row));
        case 'editTxn':
          txns = [for (final t in txns) t.id == o.id ? _localTxn(o.id, o.row, was: t) : t];
        case 'deleteTxn':
          txns.removeWhere((t) => t.id == o.id);
        case 'addMood':
          if (!logs.any((m) => m.id == o.id)) logs.add(MoodLog.fromRow({...o.row, 'id': o.id, 'created_at': _nowIso()}));
      }
    }
    transactions = txns..sort(newestFirst);
    moods = logs..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  /// A write that couldn't reach the server was kept on the phone instead.
  void _savedOffline() {
    final first = !offline;
    offline = true;
    if (first || unsent == 1) notices.add(tr("Saved on this phone — it'll sync when you're back online."));
    _startRetry();
  }

  /// Send what's waiting; reload once something went through.
  Future<void> syncOutbox() async {
    final sent = await Outbox.instance.flush(
      onRefused: (m) => notices.add(tr("Couldn't sync an entry made offline: {error}", {'error': m})),
    );
    notifyListeners();
    if (sent > 0) {
      notices.add(trn(sent, 'Synced {n} entry made offline.', 'Synced {n} entries made offline.'));
      await load();
    }
  }

  // While offline (or with unsent changes), try again every minute.
  void _startRetry() {
    _retry ??= Timer.periodic(const Duration(minutes: 1), (_) async {
      if (unsent > 0) {
        await syncOutbox();
      } else if (offline) {
        try {
          await Repo.listBudgets();
          await load();
        } catch (_) {}
      } else {
        _stopRetry();
      }
    });
  }

  void _stopRetry() {
    _retry?.cancel();
    _retry = null;
  }

  /// Sign out. The phone's copy of the account's data goes too; entries still
  /// waiting to be sent stay queued for this account's next sign-in.
  Future<void> signOut() async {
    final uid = _uid;
    if (uid != null) await OfflineCopy.clear(uid);
    await Supabase.instance.client.auth.signOut();
  }

  /// Wallets need the newer database update; until it's run they're simply off.
  Future<(bool, List<Wallet>)> _loadWallets() async {
    try {
      final list = await Repo.listWallets();
      return (true, list.isNotEmpty ? list : await Repo.seedDefaultWallets());
    } catch (e) {
      debugPrint('[catalyst] wallets unavailable — run db/supabase.sql? $e');
      return (false, <Wallet>[]);
    }
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
    boards = [];
    boardColumns = [];
    tickets = [];
    wallets = [];
    transfers = [];
    debts = [];
    debtPayments = [];
    walletsReady = false;
    offline = false;
    offlineSince = null;
    _stopRetry();
    selectedBoards.clear();
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
      if (!_prefsTouched.contains('currency') && meta['currency'] is String) {
        currency = setCurrency(meta['currency']).code;
        prefs.setString('currency', currency);
      }
      if (!_prefsTouched.contains('reminders') && meta['reminders'] != null) {
        reminders = ReminderPrefs.fromJson(meta['reminders']);
        prefs.setString('reminders', jsonEncode(reminders.toJson()));
      }
      if (!_prefsTouched.contains('lang') && (meta['lang'] == 'en' || meta['lang'] == 'bn')) {
        await setAppLang(meta['lang']);
        lang = appLang;
        prefs.setString('lang', lang);
      }
      if (!_dashboardTouched) {
        final remote = _parseHidden(meta[_dashboardHiddenKey]) ?? [];
        dashboardHidden = remote;
        prefs.setString(_dashboardHiddenKey, jsonEncode(remote));
      }
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

  void setCurrencyCode(String code) {
    _prefsTouched.add('currency');
    currency = setCurrency(code).code;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString('currency', currency));
    Repo.savePrefs({'currency': currency}).catchError((Object e) => debugPrint('[catalyst] could not save the currency: $e'));
  }

  Future<void> setLang(String code) async {
    _prefsTouched.add('lang');
    await setAppLang(code);
    lang = appLang;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('lang', lang);
    Repo.savePrefs({'lang': lang}).catchError((Object e) => debugPrint('[catalyst] could not save the language: $e'));
  }

  void setReminders(ReminderPrefs r) {
    _prefsTouched.add('reminders');
    reminders = r;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString('reminders', jsonEncode(r.toJson())));
    Repo.savePrefs({'reminders': r.toJson()}).catchError((Object e) => debugPrint('[catalyst] could not save reminders: $e'));
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

  // ---- money / mood (made offline, these wait in the outbox — see data/offline.dart)

  /// [offlineOk] false: fail without a connection instead of queueing (a bill
  /// payment also has to move the bill on, which needs the server).
  Future<Txn> addMoney(NewTxn t, {bool offlineOk = true}) async {
    final id = uuidV4();
    Txn c;
    try {
      c = await Repo.addTransaction(t, id: id);
    } catch (e) {
      if (!offlineOk || !isOffline(e)) rethrow;
      c = _localTxn(id, t.toRow());
      await Outbox.instance.add(OutboxOp('addTxn', id, t.toRow()));
      _savedOffline();
    }
    final before = transactions;
    transactions = [c, ...transactions]..sort(newestFirst);
    notifyListeners();
    if (c.kind == Kind.expense) checkBudgets(before);
    return c;
  }

  /// Budget alerts: when an expense takes a budget past 80% or 100% this month —
  /// each level once per budget per month (this device).
  Future<void> checkBudgets(List<Txn> before) async {
    if (!reminders.budgets || budgets.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'budget-alerts:${toDateKey(DateTime.now()).substring(0, 7)}';
    final seen = prefs.getStringList(key) ?? [];
    for (final b in budgets) {
      final was = budgetUse(b, before).ratio;
      final now = budgetUse(b, transactions);
      final level = now.ratio >= 1 ? 100 : now.ratio >= 0.8 ? 80 : 0;
      final id = '${b.id}:$level';
      if (level == 0 || was >= level / 100 || seen.contains(id)) continue;
      seen.add(id);
      final args = {'name': tr(b.categoryName), 'spent': formatCurrency(now.spent), 'limit': formatCurrency(b.amount)};
      notices.add(level == 100
          ? tr('{name} budget is used up: {spent} of {limit} this month.', args)
          : tr('{name} budget is {percent}% used: {spent} of {limit}.', {...args, 'percent': (now.ratio * 100).round()}));
    }
    await prefs.setStringList(key, seen);
  }

  /// Saves new values for a transaction. Every total (ledger, dashboard, calendar,
  /// budgets, savings) is computed from [transactions], so they all follow.
  Future<void> editMoney(String id, NewTxn t) async {
    final was = transactions.where((x) => x.id == id).firstOrNull;
    Txn c;
    if (Outbox.instance.hasUnsent(id)) {
      // Not on the server yet: change the queued entry itself.
      await Outbox.instance.edit(id, t.toRow());
      c = _localTxn(id, t.toRow(), was: was);
    } else {
      try {
        c = await Repo.updateTransaction(id, t);
      } catch (e) {
        if (!isOffline(e)) rethrow;
        await Outbox.instance.edit(id, t.toRow());
        c = _localTxn(id, t.toRow(), was: was);
        _savedOffline();
      }
    }
    final before = transactions;
    transactions = [for (final x in transactions) x.id == id ? c : x]..sort(newestFirst);
    notifyListeners();
    if (c.kind == Kind.expense) checkBudgets(before);
  }

  Future<void> removeMoney(String id) async {
    if (Outbox.instance.hasUnsent(id)) {
      await Outbox.instance.delete(id);
    } else {
      try {
        await Repo.deleteTransaction(id);
      } catch (e) {
        if (!isOffline(e)) rethrow;
        await Outbox.instance.delete(id);
        _savedOffline();
      }
    }
    transactions = transactions.where((t) => t.id != id).toList();
    notifyListeners();
  }

  Future<void> saveMood({required int mood, required String note, required List<String> tags, required String loggedOn, required String loggedAt}) async {
    final id = uuidV4();
    MoodLog s;
    try {
      s = await Repo.addMood(mood: mood, note: note, tags: tags, loggedOn: loggedOn, loggedAt: loggedAt, id: id);
    } catch (e) {
      if (!isOffline(e)) rethrow;
      final row = {'mood': mood, 'note': note, 'tags': tags, 'logged_on': loggedOn, 'logged_at': loggedAt};
      s = MoodLog.fromRow({...row, 'id': id, 'created_at': _nowIso()});
      await Outbox.instance.add(OutboxOp('addMood', id, row));
      _savedOffline();
    }
    moods = [s, ...moods]..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    notifyListeners();
  }

  List<MoodLog> moodsForDate(String key) =>
      moods.where((m) => m.loggedOn == key).toList()..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

  // ---- categories
  Future<Category> createCategory({required String name, required Kind kind, required String color, required int sort}) async {
    final x = await Repo.addCategory(name: name, kind: kind, color: color, sort: sort);
    categories = orderCategories([...categories, x]);
    notifyListeners();
    return x;
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
  Future<void> createBill(String name, double amount, String dueOn, String recurrence, {String? categoryId, String? walletId}) async {
    final x = await db.addBill(
      name: name,
      amount: amount,
      dueOn: dueOn,
      recurrence: recurrence,
      categoryId: walletsReady ? categoryId : null,
      walletId: walletsReady ? walletId : null,
    );
    bills = [...bills, x]..sort((a, b) => a.dueOn.compareTo(b.dueOn));
    notifyListeners();
  }

  Future<void> toggleBillPaid(Bill b) async {
    await db.setBillPaid(b.id, !b.isPaid);
    bills = [for (final x in bills) x.id == b.id ? x.copyWith(isPaid: !b.isPaid) : x];
    notifyListeners();
  }

  Future<void> removeBill(String id) async {
    await db.deleteBill(id);
    bills = bills.where((b) => b.id != id).toList();
    notifyListeners();
  }

  // ---- bills: paying logs the expense; a repeating bill moves to its next due date
  Future<BillPayment> payBill(String id) async {
    final bill = bills.where((b) => b.id == id).firstOrNull;
    if (bill == null) throw Exception(tr('That bill no longer exists.'));
    final cat = billCategory(bill, categories);
    final today = toDateKey(DateTime.now());
    final txn = await addMoney(
      NewTxn(
        kind: Kind.expense,
        amount: bill.amount,
        categoryId: cat?.id,
        categoryName: cat?.name ?? 'Other',
        note: bill.name,
        occurredOn: today,
        occurredAt: combineDateTime(today, nowTime()),
        walletId: walletsReady ? bill.walletId ?? defaultWallet(wallets)?.id : null,
      ),
      offlineOk: false,
    );
    final next = nextDue(bill.dueOn, bill.recurrence);
    final patch = <String, dynamic>{
      'due_on': ?next,
      'is_paid': next == null,
      if (walletsReady) 'last_paid_txn': txn.id,
    };
    await db.updateBill(id, patch);
    bills = [
      for (final b in bills)
        b.id == id ? b.copyWith(dueOn: next, isPaid: next == null, lastPaidTxn: walletsReady ? txn.id : null) : b,
    ]..sort((a, b) => a.dueOn.compareTo(b.dueOn));
    notifyListeners();
    return (billId: id, txnId: txn.id, dueOn: bill.dueOn, isPaid: bill.isPaid, lastPaidTxn: bill.lastPaidTxn);
  }

  /// Takes a payment back: removes its expense and puts the bill as it was.
  Future<void> undoBillPayment(BillPayment p) async {
    await db.updateBill(p.billId, {'due_on': p.dueOn, 'is_paid': p.isPaid, if (walletsReady) 'last_paid_txn': p.lastPaidTxn});
    bills = [
      for (final b in bills)
        b.id == p.billId ? b.copyWith(dueOn: p.dueOn, isPaid: p.isPaid, lastPaidTxn: p.lastPaidTxn, clearLastPaid: p.lastPaidTxn == null) : b,
    ]..sort((a, b) => a.dueOn.compareTo(b.dueOn));
    notifyListeners();
    await removeMoney(p.txnId);
  }

  /// A paid one-off bill back to unpaid, optionally taking its expense off the ledger.
  Future<void> unpayBill(String id, {bool removeExpense = true}) async {
    final bill = bills.where((b) => b.id == id).firstOrNull;
    if (bill == null) return;
    await db.updateBill(id, {'is_paid': false, if (walletsReady && bill.lastPaidTxn != null) 'last_paid_txn': null});
    bills = [for (final b in bills) b.id == id ? b.copyWith(isPaid: false, clearLastPaid: true) : b];
    notifyListeners();
    if (removeExpense && bill.lastPaidTxn != null) await removeMoney(bill.lastPaidTxn!);
  }

  /// Saves a bill's editable fields.
  Future<void> editBill(Bill b) async {
    await db.updateBill(b.id, {
      'name': b.name,
      'amount': b.amount,
      'due_on': b.dueOn,
      'recurrence': b.recurrence,
      if (walletsReady) 'category_id': b.categoryId,
      if (walletsReady) 'wallet_id': b.walletId,
    });
    bills = [for (final x in bills) x.id == b.id ? b : x]..sort((a, c) => a.dueOn.compareTo(c.dueOn));
    notifyListeners();
  }

  // ---- wallets + transfers
  Future<Wallet> createWallet({required String name, required WalletKind kind, required String color, required double openingBalance}) async {
    final w = await db.addWallet(
      name: name,
      kind: kind,
      color: color,
      openingBalance: openingBalance,
      sort: wallets.fold<int>(-1, (m, x) => x.sort > m ? x.sort : m) + 1,
    );
    wallets = [...wallets, w]..sort((a, b) => a.sort.compareTo(b.sort));
    notifyListeners();
    return w;
  }

  Future<void> editWallet(String id, {String? name, WalletKind? kind, String? color, double? openingBalance, bool? archived}) async {
    await db.updateWallet(id, {
      'name': ?name,
      'kind': ?kind?.name,
      'color': ?color,
      'opening_balance': ?openingBalance,
      'archived': ?archived,
    });
    wallets = [
      for (final w in wallets)
        w.id == id ? w.copyWith(name: name, kind: kind, color: color, openingBalance: openingBalance, archived: archived) : w,
    ];
    notifyListeners();
  }

  /// Its entries move to the default wallet; its transfers go with it.
  Future<void> removeWallet(String id) async {
    await db.deleteWallet(id);
    wallets = wallets.where((w) => w.id != id).toList();
    transfers = transfers.where((t) => t.fromWallet != id && t.toWallet != id).toList();
    transactions = [for (final t in transactions) t.walletId == id ? t.withWallet(null) : t];
    notifyListeners();
  }

  /// A transfer between two wallets; a fee (a bKash cash-out, say) is logged as an expense.
  Future<void> createTransfer({
    required String fromWallet,
    required String toWallet,
    required double amount,
    required String note,
    required String occurredOn,
    required String occurredAt,
    double fee = 0,
  }) async {
    final t = await db.addTransfer(
      fromWallet: fromWallet,
      toWallet: toWallet,
      amount: amount,
      note: note,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
    );
    transfers = [t, ...transfers]..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    notifyListeners();
    if (fee > 0) {
      final from = wallets.where((w) => w.id == fromWallet).firstOrNull;
      final cat = categories.where((c) => c.kind == Kind.expense && RegExp(r'^(fees?|charges?)$', caseSensitive: false).hasMatch(c.name)).firstOrNull ??
          categories.where((c) => c.kind == Kind.expense && c.name.toLowerCase() == 'other').firstOrNull;
      await addMoney(NewTxn(
        kind: Kind.expense,
        amount: (fee * 100).roundToDouble() / 100,
        categoryId: cat?.id,
        categoryName: cat?.name ?? 'Other',
        note: '${from?.name ?? 'Transfer'} fee',
        occurredOn: occurredOn,
        occurredAt: occurredAt,
        walletId: fromWallet,
      ));
    }
  }

  Future<void> removeTransfer(String id) async {
    await db.deleteTransfer(id);
    transfers = transfers.where((t) => t.id != id).toList();
    notifyListeners();
  }

  // ---- dhar / baki
  Future<Debt> createDebt({
    required String person,
    required DebtDirection direction,
    required double amount,
    required String note,
    required String? walletId,
    required String occurredOn,
    required String? dueOn,
  }) async {
    final d = await db.addDebt(
      person: person,
      direction: direction,
      amount: amount,
      note: note,
      walletId: walletId,
      occurredOn: occurredOn,
      dueOn: dueOn,
    );
    debts = [d, ...debts];
    notifyListeners();
    return d;
  }

  /// Settled or written off (closed), or reopened.
  Future<void> setDebtClosed(String id, bool closed) async {
    await db.updateDebt(id, {'closed': closed});
    debts = [for (final d in debts) d.id == id ? d.copyWith(closed: closed) : d];
    notifyListeners();
  }

  /// Its payments go with it.
  Future<void> removeDebt(String id) async {
    await db.deleteDebt(id);
    debts = debts.where((d) => d.id != id).toList();
    debtPayments = debtPayments.where((p) => p.debtId != id).toList();
    notifyListeners();
  }

  /// A part (or full) payment; a debt that's paid off closes itself.
  Future<void> recordDebtPayment({required String debtId, required double amount, required String? walletId, required String paidOn}) async {
    final p = await db.addDebtPayment(debtId: debtId, amount: amount, walletId: walletId, paidOn: paidOn);
    debtPayments = [...debtPayments, p];
    notifyListeners();
    final debt = debts.where((d) => d.id == debtId).firstOrNull;
    if (debt != null && !debt.closed && debtRemaining(debt, debtPayments) <= 0) await setDebtClosed(debtId, true);
  }

  /// Taking a payment back reopens a debt it had closed.
  Future<void> removeDebtPayment(String id) async {
    final pay = debtPayments.where((p) => p.id == id).firstOrNull;
    await db.deleteDebtPayment(id);
    debtPayments = debtPayments.where((p) => p.id != id).toList();
    notifyListeners();
    final debt = pay == null ? null : debts.where((d) => d.id == pay.debtId).firstOrNull;
    if (debt != null && debt.closed && debtRemaining(debt, debtPayments) > 0) await setDebtClosed(debt.id, false);
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

  // ---- boards (to-do + to-buy): a new board starts with its kind's default columns
  List<BoardColumn> columnsOf(String boardId) =>
      boardColumns.where((c) => c.boardId == boardId).toList()..sort((a, b) => a.sort.compareTo(b.sort));

  List<Ticket> ticketsIn(String columnId) => tickets.where((t) => t.columnId == columnId).toList()..sort(byTicketOrder);

  /// The board on screen for [kind]: the one last opened, else the first.
  Board? boardOf(BoardKind kind) {
    final mine = boards.where((b) => b.kind == kind);
    return mine.where((b) => b.id == selectedBoards[kind]).firstOrNull ?? mine.firstOrNull;
  }

  void selectBoard(BoardKind kind, String id) {
    selectedBoards[kind] = id;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString('board:${kind.name}', id));
  }

  Future<Board> createBoard(String name, BoardKind kind) async {
    final board = await Repo.addBoard(name: name, kind: kind, sort: boards.length);
    boards = [...boards, board];
    notifyListeners();
    try {
      // Named in the app's language (they're the board's own columns from then on).
      final cols = await Repo.addBoardColumns(board.id, [for (final (i, n) in defaultBoardColumns[kind]!.indexed) (tr(n), i)]);
      boardColumns = [...boardColumns, ...cols];
      notifyListeners();
    } catch (e) {
      // The board still works — its columns can be added by hand.
      debugPrint('[catalyst] could not add the new board\'s columns: $e');
    }
    return board;
  }

  Future<void> renameBoard(String id, String name) async {
    await Repo.renameBoard(id, name);
    boards = [for (final b in boards) b.id == id ? b.copyWith(name: name) : b];
    notifyListeners();
  }

  Future<void> removeBoard(String id) async {
    await Repo.deleteBoard(id);
    boards = boards.where((b) => b.id != id).toList();
    boardColumns = boardColumns.where((c) => c.boardId != id).toList();
    tickets = tickets.where((t) => t.boardId != id).toList();
    notifyListeners();
  }

  Future<void> createColumn(String boardId, String name) async {
    final last = columnsOf(boardId).fold<int>(-1, (m, c) => c.sort > m ? c.sort : m);
    final cols = await Repo.addBoardColumns(boardId, [(name, last + 1)]);
    boardColumns = [...boardColumns, ...cols];
    notifyListeners();
  }

  Future<void> renameColumn(String id, String name) async {
    await Repo.updateBoardColumn(id, name: name);
    boardColumns = [for (final c in boardColumns) c.id == id ? c.copyWith(name: name) : c];
    notifyListeners();
  }

  Future<void> moveColumn(String id, int dir) async {
    final col = boardColumns.where((c) => c.id == id).firstOrNull;
    if (col == null) return;
    final cols = columnsOf(col.boardId);
    final i = cols.indexWhere((c) => c.id == id);
    if (i + dir < 0 || i + dir >= cols.length) return;
    await placeColumn(id, i + dir);
  }

  /// Puts column [id] at [index] among its board's columns (renumbering them all).
  Future<void> placeColumn(String id, int index) async {
    final col = boardColumns.where((c) => c.id == id).firstOrNull;
    if (col == null) return;
    final cols = columnsOf(col.boardId);
    final from = cols.indexWhere((c) => c.id == id);
    final to = index.clamp(0, cols.length - 1);
    if (from == to) return;
    final order = [...cols]
      ..removeAt(from)
      ..insert(to, col);
    // Renumber the whole board so equal or gapped sorts can't block the move.
    final changes = {for (final (k, c) in order.indexed) if (c.sort != k) c.id: k};
    // Optimistic: the column stays where it was dropped while the writes go out.
    final before = boardColumns;
    boardColumns = [for (final c in boardColumns) changes.containsKey(c.id) ? c.copyWith(sort: changes[c.id]) : c];
    notifyListeners();
    try {
      await Future.wait([for (final e in changes.entries) Repo.updateBoardColumn(e.key, sort: e.value)]);
    } catch (_) {
      // Put the board back the way the database has it, then let the caller say so.
      try {
        boardColumns = await Repo.listBoardColumns();
      } catch (_) {
        boardColumns = before;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeColumn(String id) async {
    await Repo.deleteBoardColumn(id);
    boardColumns = boardColumns.where((c) => c.id != id).toList();
    tickets = tickets.where((t) => t.columnId != id).toList();
    notifyListeners();
  }

  Future<Ticket> createTicket(String columnId, String title) async {
    final col = boardColumns.where((c) => c.id == columnId).firstOrNull;
    if (col == null) throw Exception(tr('That column no longer exists.'));
    final inBoard = tickets.where((t) => t.boardId == col.boardId);
    final lastSort = inBoard.where((t) => t.columnId == columnId).fold<double>(0, (m, t) => t.sort > m ? t.sort : m);
    final t = await Repo.addTicket({
      'board_id': col.boardId,
      'column_id': columnId,
      'number': inBoard.fold<int>(0, (m, x) => x.number > m ? x.number : m) + 1,
      'title': title,
      'sort': lastSort + sortStep, // new tickets join the bottom of the column
    });
    tickets = [...tickets, t];
    notifyListeners();
    return t;
  }

  /// Saves a ticket's editable fields (title, notes, priority, due date, price).
  Future<void> saveTicket(Ticket t) async {
    await Repo.updateTicket(t.id, {
      'title': t.title,
      'description': t.description,
      'priority': t.priority.name,
      'due_on': t.dueOn,
      'amount': t.amount,
    });
    tickets = [
      for (final x in tickets)
        x.id == t.id
            ? x.edited(title: t.title, description: t.description, priority: t.priority, dueOn: t.dueOn, amount: t.amount)
            : x,
    ];
    notifyListeners();
  }

  /// Puts a ticket in [columnId] where it sits in [order] (that column's ids, top to bottom).
  Future<void> placeTicket(String id, String columnId, List<String> order) async {
    final i = order.indexOf(id);
    if (i < 0) return;
    final sortOf = {for (final t in tickets) t.id: t.sort};
    final between = sortBetween(i > 0 ? sortOf[order[i - 1]] : null, i < order.length - 1 ? sortOf[order[i + 1]] : null);
    // Usually one row changes; when neighbours are too close, renumber the column.
    final moves = between == null ? {for (final (k, tid) in order.indexed) tid: (k + 1) * sortStep} : {id: between};
    // Optimistic: the card stays where it was dropped while the write goes out.
    tickets = [
      for (final t in tickets)
        moves.containsKey(t.id) ? t.moved(t.id == id ? columnId : t.columnId, moves[t.id]!) : t,
    ];
    notifyListeners();
    try {
      await Future.wait([
        for (final e in moves.entries)
          Repo.updateTicket(e.key, {'sort': e.value, if (e.key == id) 'column_id': columnId}),
      ]);
    } catch (e) {
      debugPrint('[catalyst] could not move the ticket: $e');
      // Put the board back the way the database has it.
      tickets = await _safe(Repo.listTickets, tickets, 'tickets');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeTicket(String id) async {
    await Repo.deleteTicket(id);
    tickets = tickets.where((t) => t.id != id).toList();
    notifyListeners();
  }

  /// Adds a batch (a scanned list) to [boardId] in one insert — see [newTicketRows].
  Future<List<Ticket>> createTickets(String boardId, List<NewTicket> drafts) async {
    if (drafts.isEmpty) return [];
    final made = await Repo.addTickets(newTicketRows(boardId, drafts, tickets));
    tickets = [...tickets, ...made];
    notifyListeners();
    return made;
  }

  Future<void> removeTickets(List<String> ids) async {
    if (ids.isEmpty) return;
    await Repo.deleteTickets(ids);
    final gone = ids.toSet();
    tickets = tickets.where((t) => !gone.contains(t.id)).toList();
    notifyListeners();
  }
}

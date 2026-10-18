// Domain types — mirror src/types/index.ts of the Catalyst web app. Both apps
// read and write the same Supabase tables, so field names and rules match.
import 'package:flutter/painting.dart';

import 'util/i18n.dart';
import 'util/recurring.dart';

enum Kind { expense, income, saving }

Kind kindFrom(String? s) => switch (s) {
      'income' => Kind.income,
      'saving' => Kind.saving,
      _ => Kind.expense,
    };

/// Special expense category: amount spent here is subtracted from total savings.
const breakSaving = 'Break saving';

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// "#RRGGBB" -> Color.
Color hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.tryParse('FF${h.padRight(6, '0').substring(0, 6)}', radix: 16) ?? 0xFF7A746A);
}

class Category {
  const Category({required this.id, required this.name, required this.kind, required this.color, required this.sort});

  final String id;
  final String name;
  final Kind kind;
  final String color;
  final int sort;

  factory Category.fromRow(Map<String, dynamic> r) => Category(
        id: r['id'] as String,
        name: r['name'] as String,
        kind: kindFrom(r['kind'] as String?),
        color: (r['color'] as String?) ?? '#7A746A',
        sort: (r['sort'] as num?)?.toInt() ?? 0,
      );

  Category copyWith({String? name, String? color}) =>
      Category(id: id, name: name ?? this.name, kind: kind, color: color ?? this.color, sort: sort);
}

class Txn {
  const Txn({
    required this.id,
    required this.kind,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    required this.place,
    required this.note,
    required this.occurredOn,
    required this.occurredAt,
    required this.createdAt,
    this.walletId,
    this.recurringId,
  });

  final String id;
  final Kind kind;
  final double amount; // positive; kind carries sign meaning
  final String? categoryId;
  final String categoryName;
  final String place;
  final String note;
  final String occurredOn; // yyyy-mm-dd (date bucket)
  final String occurredAt; // ISO timestamp (intraday)
  final String createdAt;
  final String? walletId; // null = the default wallet
  final String? recurringId; // logged automatically by this recurring rule

  factory Txn.fromRow(Map<String, dynamic> r) => Txn(
        id: r['id'] as String,
        kind: kindFrom(r['kind'] as String?),
        amount: _num(r['amount']),
        categoryId: r['category_id'] as String?,
        categoryName: (r['category_name'] as String?) ?? 'Other',
        place: (r['place'] as String?) ?? '',
        note: (r['note'] as String?) ?? '',
        occurredOn: r['occurred_on'] as String,
        occurredAt: (r['occurred_at'] ?? r['created_at']) as String,
        createdAt: (r['created_at'] as String?) ?? '',
        walletId: r['wallet_id'] as String?,
        recurringId: r['recurring_id'] as String?,
      );

  /// The same entry in another wallet (null = the default one).
  Txn withWallet(String? wallet) => Txn(
      id: id, kind: kind, amount: amount, categoryId: categoryId, categoryName: categoryName, place: place,
      note: note, occurredOn: occurredOn, occurredAt: occurredAt, createdAt: createdAt, walletId: wallet, recurringId: recurringId);

  /// The same entry, no longer linked to the recurring rule that logged it.
  Txn unlinked() => Txn(
      id: id, kind: kind, amount: amount, categoryId: categoryId, categoryName: categoryName, place: place,
      note: note, occurredOn: occurredOn, occurredAt: occurredAt, createdAt: createdAt, walletId: walletId);
}

/// The ledger's order (same as the database list): newest day first, then newest
/// added. A full order, so re-sorting never shuffles a day's entries.
int newestFirst(Txn a, Txn b) {
  final d = b.occurredOn.compareTo(a.occurredOn);
  return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
}

class NewTxn {
  const NewTxn({
    required this.kind,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    this.place = '',
    this.note = '',
    required this.occurredOn,
    required this.occurredAt,
    this.walletId,
  });

  final Kind kind;
  final double amount;
  final String? categoryId;
  final String categoryName;
  final String place;
  final String note;
  final String occurredOn;
  final String occurredAt;
  final String? walletId;

  // wallet_id only goes out when there is one, so entries still save on a database
  // that hasn't had the wallets update yet.
  Map<String, dynamic> toRow() => {
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'category_name': categoryName,
        'place': place,
        'note': note,
        'occurred_on': occurredOn,
        'occurred_at': occurredAt,
        'wallet_id': ?walletId,
      };
}

class MoodLog {
  const MoodLog({
    required this.id,
    required this.mood,
    required this.note,
    required this.tags,
    required this.loggedOn,
    required this.loggedAt,
    required this.createdAt,
  });

  final String id;
  final int mood; // 1..5
  final String note;
  final List<String> tags;
  final String loggedOn; // yyyy-mm-dd
  final String loggedAt; // ISO timestamp
  final String createdAt;

  factory MoodLog.fromRow(Map<String, dynamic> r) => MoodLog(
        id: r['id'] as String,
        mood: (r['mood'] as num).toInt(),
        note: (r['note'] as String?) ?? '',
        tags: ((r['tags'] as List?) ?? const []).map((e) => '$e').toList(),
        loggedOn: r['logged_on'] as String,
        loggedAt: (r['logged_at'] ?? r['created_at']) as String,
        createdAt: (r['created_at'] as String?) ?? '',
      );
}

class Budget {
  const Budget({required this.id, required this.categoryId, required this.categoryName, required this.amount, required this.period});

  final String id;
  final String? categoryId;
  final String categoryName;
  final double amount;
  final String period;

  factory Budget.fromRow(Map<String, dynamic> r) => Budget(
        id: r['id'] as String,
        categoryId: r['category_id'] as String?,
        categoryName: (r['category_name'] as String?) ?? 'Overall',
        amount: _num(r['amount']),
        period: (r['period'] as String?) ?? 'monthly',
      );

  Budget copyWith({double? amount}) =>
      Budget(id: id, categoryId: categoryId, categoryName: categoryName, amount: amount ?? this.amount, period: period);
}

class Goal {
  const Goal({required this.id, required this.title, required this.targetAmount, required this.savedAmount, required this.dueOn});

  final String id;
  final String title;
  final double targetAmount;
  final double savedAmount;
  final String? dueOn;

  factory Goal.fromRow(Map<String, dynamic> r) => Goal(
        id: r['id'] as String,
        title: r['title'] as String,
        targetAmount: _num(r['target_amount']),
        savedAmount: _num(r['saved_amount']),
        dueOn: r['due_on'] as String?,
      );

  Goal copyWith({double? savedAmount}) =>
      Goal(id: id, title: title, targetAmount: targetAmount, savedAmount: savedAmount ?? this.savedAmount, dueOn: dueOn);
}

class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.amount,
    required this.dueOn,
    required this.recurrence,
    required this.isPaid,
    this.categoryId,
    this.walletId,
    this.lastPaidTxn,
  });

  final String id;
  final String name;
  final double amount;
  final String dueOn;
  final String recurrence; // monthly | weekly | yearly | once
  final bool isPaid;
  final String? categoryId; // what paying it is logged under (null = matched by name)
  final String? walletId; // paid from (null = the default wallet)
  final String? lastPaidTxn; // the expense its last payment logged

  factory Bill.fromRow(Map<String, dynamic> r) => Bill(
        id: r['id'] as String,
        name: r['name'] as String,
        amount: _num(r['amount']),
        dueOn: r['due_on'] as String,
        recurrence: (r['recurrence'] as String?) ?? 'monthly',
        isPaid: (r['is_paid'] as bool?) ?? false,
        categoryId: r['category_id'] as String?,
        walletId: r['wallet_id'] as String?,
        lastPaidTxn: r['last_paid_txn'] as String?,
      );

  /// A copy with some fields changed; pass `clearX: true` to set a link to null.
  Bill copyWith({
    String? name,
    double? amount,
    String? dueOn,
    String? recurrence,
    bool? isPaid,
    String? categoryId,
    String? walletId,
    String? lastPaidTxn,
    bool clearCategory = false,
    bool clearWallet = false,
    bool clearLastPaid = false,
  }) =>
      Bill(
        id: id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        dueOn: dueOn ?? this.dueOn,
        recurrence: recurrence ?? this.recurrence,
        isPaid: isPaid ?? this.isPaid,
        categoryId: clearCategory ? null : categoryId ?? this.categoryId,
        walletId: clearWallet ? null : walletId ?? this.walletId,
        lastPaidTxn: clearLastPaid ? null : lastPaidTxn ?? this.lastPaidTxn,
      );
}

/// An income or expense that logs itself — a salary on the 1st, rent, a
/// subscription. Each due date becomes a transaction (util/recurring.dart has the
/// dates; the web and its hourly job use the same rules).
class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.name,
    required this.kind,
    required this.amount,
    this.categoryId,
    this.walletId,
    required this.schedule,
    required this.nextOn,
    this.paused = false,
    this.tz = 'Asia/Dhaka',
    this.createdAt = '',
  });

  final String id;
  final String name;
  final Kind kind; // income or expense
  final double amount;
  final String? categoryId; // null = matched by name, else Other
  final String? walletId; // null = the default wallet
  final Schedule schedule;
  final String nextOn; // the next date not logged yet
  final bool paused;
  final String tz; // the timezone its time is in (where it was saved)
  final String createdAt;

  bool get ended => hasEnded(schedule, nextOn);

  factory RecurringRule.fromRow(Map<String, dynamic> r) => RecurringRule(
        id: r['id'] as String,
        name: r['name'] as String,
        kind: kindFrom(r['kind'] as String?),
        amount: _num(r['amount']),
        categoryId: r['category_id'] as String?,
        walletId: r['wallet_id'] as String?,
        schedule: Schedule(
          frequency: frequencyFrom(r['frequency'] as String?),
          every: (r['every'] as num?)?.toInt() ?? 1,
          day1: (r['day1'] as num?)?.toInt() ?? 1,
          day2: (r['day2'] as num?)?.toInt(),
          time: (r['at_time'] as String?) ?? '09:00',
          startOn: r['start_on'] as String,
          endOn: r['end_on'] as String?,
        ),
        nextOn: r['next_on'] as String,
        paused: (r['paused'] as bool?) ?? false,
        tz: (r['tz'] as String?) ?? 'Asia/Dhaka',
        createdAt: (r['created_at'] as String?) ?? '',
      );

  /// The columns the user sets (not nextOn, paused or tz).
  static Map<String, dynamic> fields({
    required String name,
    required Kind kind,
    required double amount,
    required String? categoryId,
    required String? walletId,
    required Schedule schedule,
  }) =>
      {
        'name': name,
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'wallet_id': walletId,
        'frequency': frequencyName(schedule.frequency),
        'every': schedule.every,
        'day1': schedule.day1,
        'day2': schedule.frequency == Frequency.twiceMonthly ? schedule.day2 : null,
        'at_time': schedule.time,
        'start_on': schedule.startOn,
        'end_on': schedule.endOn,
      };

  RecurringRule copyWith({
    String? name,
    Kind? kind,
    double? amount,
    String? categoryId,
    String? walletId,
    Schedule? schedule,
    String? nextOn,
    bool? paused,
    String? tz,
    bool clearCategory = false,
    bool clearWallet = false,
  }) =>
      RecurringRule(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        categoryId: clearCategory ? null : categoryId ?? this.categoryId,
        walletId: clearWallet ? null : walletId ?? this.walletId,
        schedule: schedule ?? this.schedule,
        nextOn: nextOn ?? this.nextOn,
        paused: paused ?? this.paused,
        tz: tz ?? this.tz,
        createdAt: createdAt,
      );
}

enum ChallengeKind { noSpend, spendUnder, skipCategory, save, logDaily }

const challengeKindNames = {
  ChallengeKind.noSpend: 'no_spend',
  ChallengeKind.spendUnder: 'spend_under',
  ChallengeKind.skipCategory: 'skip_category',
  ChallengeKind.save: 'save',
  ChallengeKind.logDaily: 'log_daily',
};

/// A few days' challenge — no-spend days, spending under an amount, skipping a
/// category, saving an amount, logging every day. Progress comes from the entries
/// (util/habits.dart).
class Challenge {
  const Challenge({
    required this.id,
    required this.kind,
    required this.target,
    this.categoryId,
    this.categoryName = '',
    required this.startOn,
    required this.days,
    this.createdAt = '',
  });

  final String id;
  final ChallengeKind kind;
  final double target; // no-spend days, or an amount to stay under / save
  final String? categoryId; // skip a category
  final String categoryName;
  final String startOn;
  final int days;
  final String createdAt;

  factory Challenge.fromRow(Map<String, dynamic> r) => Challenge(
        id: r['id'] as String,
        kind: challengeKindNames.entries.where((e) => e.value == r['kind']).firstOrNull?.key ?? ChallengeKind.noSpend,
        target: _num(r['target']),
        categoryId: r['category_id'] as String?,
        categoryName: (r['category_name'] as String?) ?? '',
        startOn: r['start_on'] as String,
        days: (r['days'] as num?)?.toInt() ?? 7,
        createdAt: (r['created_at'] as String?) ?? '',
      );

  Map<String, dynamic> toRow() => {
        'kind': challengeKindNames[kind],
        'target': target,
        'category_id': categoryId,
        'category_name': categoryName,
        'start_on': startOn,
        'days': days,
      };
}

class JournalEntry {
  const JournalEntry({required this.id, required this.entryOn, required this.mood, required this.title, required this.body, required this.createdAt});

  final String id;
  final String entryOn;
  final int? mood;
  final String title;
  final String body;
  final String createdAt;

  factory JournalEntry.fromRow(Map<String, dynamic> r) => JournalEntry(
        id: r['id'] as String,
        entryOn: r['entry_on'] as String,
        mood: (r['mood'] as num?)?.toInt(),
        title: (r['title'] as String?) ?? '',
        body: (r['body'] as String?) ?? '',
        createdAt: (r['created_at'] as String?) ?? '',
      );
}

class Activity {
  const Activity({required this.id, required this.name, required this.color, required this.sort});

  final String id;
  final String name;
  final String color;
  final int sort;

  factory Activity.fromRow(Map<String, dynamic> r) => Activity(
        id: r['id'] as String,
        name: r['name'] as String,
        color: (r['color'] as String?) ?? '#3D80BC',
        sort: (r['sort'] as num?)?.toInt() ?? 0,
      );
}

class ActivityLog {
  const ActivityLog({required this.id, required this.activityId, required this.loggedOn, required this.value});

  final String id;
  final String activityId;
  final String loggedOn;
  final String value;

  factory ActivityLog.fromRow(Map<String, dynamic> r) => ActivityLog(
        id: r['id'] as String,
        activityId: r['activity_id'] as String,
        loggedOn: r['logged_on'] as String,
        value: (r['value'] as String?) ?? 'done',
      );
}

// ---- wallets: where money sits (cash, bKash, Nagad, a bank account…)

enum WalletKind { cash, mobile, bank, card, other }

WalletKind walletKindFrom(String? s) => WalletKind.values.firstWhere((k) => k.name == s, orElse: () => WalletKind.other);

const walletKindLabels = {
  WalletKind.cash: 'Cash',
  WalletKind.mobile: 'Mobile money',
  WalletKind.bank: 'Bank',
  WalletKind.card: 'Card',
  WalletKind.other: 'Other',
};

class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.kind,
    required this.color,
    required this.openingBalance,
    required this.sort,
    required this.archived,
  });

  final String id;
  final String name;
  final WalletKind kind;
  final String color;
  final double openingBalance;
  final int sort;
  final bool archived;

  factory Wallet.fromRow(Map<String, dynamic> r) => Wallet(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        kind: walletKindFrom(r['kind'] as String?),
        color: (r['color'] as String?) ?? '#7A746A',
        openingBalance: _num(r['opening_balance']),
        sort: (r['sort'] as num?)?.toInt() ?? 0,
        archived: (r['archived'] as bool?) ?? false,
      );

  Wallet copyWith({String? name, WalletKind? kind, String? color, double? openingBalance, int? sort, bool? archived}) => Wallet(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        color: color ?? this.color,
        openingBalance: openingBalance ?? this.openingBalance,
        sort: sort ?? this.sort,
        archived: archived ?? this.archived,
      );
}

/// Wallets a new account starts with (renamable, more can be added, any can be archived).
const defaultWallets = [
  ('Cash', WalletKind.cash, '#2E8159'),
  ('bKash', WalletKind.mobile, '#E2136E'),
  ('Nagad', WalletKind.mobile, '#F26522'),
  ('Bank', WalletKind.bank, '#3D80BC'),
];

/// Money moved between two wallets — never spending or income.
class Transfer {
  const Transfer({
    required this.id,
    required this.fromWallet,
    required this.toWallet,
    required this.amount,
    required this.note,
    required this.occurredOn,
    required this.occurredAt,
    required this.createdAt,
  });

  final String id;
  final String fromWallet;
  final String toWallet;
  final double amount;
  final String note;
  final String occurredOn;
  final String occurredAt;
  final String createdAt;

  factory Transfer.fromRow(Map<String, dynamic> r) => Transfer(
        id: r['id'] as String,
        fromWallet: r['from_wallet'] as String,
        toWallet: r['to_wallet'] as String,
        amount: _num(r['amount']),
        note: (r['note'] as String?) ?? '',
        occurredOn: r['occurred_on'] as String,
        occurredAt: (r['occurred_at'] as String?) ?? '',
        createdAt: (r['created_at'] as String?) ?? '',
      );
}

// ---- dhar / baki: money lent (they owe you) or borrowed (you owe them)

enum DebtDirection { lent, borrowed }

class Debt {
  const Debt({
    required this.id,
    required this.person,
    required this.direction,
    required this.amount,
    required this.note,
    required this.walletId,
    required this.occurredOn,
    required this.dueOn,
    required this.closed,
    required this.createdAt,
  });

  final String id;
  final String person;
  final DebtDirection direction;
  final double amount;
  final String note;
  final String? walletId; // the money left / came into this wallet
  final String occurredOn;
  final String? dueOn;
  final bool closed; // settled or written off
  final String createdAt;

  bool get lent => direction == DebtDirection.lent;

  factory Debt.fromRow(Map<String, dynamic> r) => Debt(
        id: r['id'] as String,
        person: (r['person'] as String?) ?? '',
        direction: r['direction'] == 'borrowed' ? DebtDirection.borrowed : DebtDirection.lent,
        amount: _num(r['amount']),
        note: (r['note'] as String?) ?? '',
        walletId: r['wallet_id'] as String?,
        occurredOn: r['occurred_on'] as String,
        dueOn: r['due_on'] as String?,
        closed: (r['closed'] as bool?) ?? false,
        createdAt: (r['created_at'] as String?) ?? '',
      );

  Debt copyWith({bool? closed}) => Debt(
      id: id, person: person, direction: direction, amount: amount, note: note, walletId: walletId,
      occurredOn: occurredOn, dueOn: dueOn, closed: closed ?? this.closed, createdAt: createdAt);
}

class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.debtId,
    required this.amount,
    required this.walletId,
    required this.paidOn,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String debtId;
  final double amount;
  final String? walletId;
  final String paidOn;
  final String note;
  final String createdAt;

  factory DebtPayment.fromRow(Map<String, dynamic> r) => DebtPayment(
        id: r['id'] as String,
        debtId: r['debt_id'] as String,
        amount: _num(r['amount']),
        walletId: r['wallet_id'] as String?,
        paidOn: r['paid_on'] as String,
        note: (r['note'] as String?) ?? '',
        createdAt: (r['created_at'] as String?) ?? '',
      );
}

// ---- boards: Jira-style to-do (tasks) and to-buy (shopping) boards share one UI.

enum BoardKind { todo, shopping }

BoardKind boardKindFrom(String? s) => s == 'shopping' ? BoardKind.shopping : BoardKind.todo;

class Board {
  const Board({required this.id, required this.name, required this.kind, required this.sort});

  final String id;
  final String name;
  final BoardKind kind;
  final int sort;

  factory Board.fromRow(Map<String, dynamic> r) => Board(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        kind: boardKindFrom(r['kind'] as String?),
        sort: (r['sort'] as num?)?.toInt() ?? 0,
      );

  Board copyWith({String? name}) => Board(id: id, name: name ?? this.name, kind: kind, sort: sort);
}

/// A board's status column ("To do", "In progress", "Done"…), ordered by sort.
class BoardColumn {
  const BoardColumn({required this.id, required this.boardId, required this.name, required this.sort});

  final String id;
  final String boardId;
  final String name;
  final int sort;

  factory BoardColumn.fromRow(Map<String, dynamic> r) => BoardColumn(
        id: r['id'] as String,
        boardId: r['board_id'] as String,
        name: (r['name'] as String?) ?? '',
        sort: (r['sort'] as num?)?.toInt() ?? 0,
      );

  BoardColumn copyWith({String? name, int? sort}) =>
      BoardColumn(id: id, boardId: boardId, name: name ?? this.name, sort: sort ?? this.sort);
}

enum TicketPriority { high, medium, low }

TicketPriority priorityFrom(String? s) => switch (s) {
      'high' => TicketPriority.high,
      'low' => TicketPriority.low,
      _ => TicketPriority.medium,
    };

class Ticket {
  const Ticket({
    required this.id,
    required this.boardId,
    required this.columnId,
    required this.number,
    required this.title,
    required this.description,
    required this.priority,
    required this.dueOn,
    required this.amount,
    required this.sort,
  });

  final String id;
  final String boardId;
  final String columnId;
  final int number; // per-board, shown as #12
  final String title;
  final String description;
  final TicketPriority priority;
  final String? dueOn; // yyyy-mm-dd
  final double? amount; // price, for to-buy items
  final double sort; // order inside the column (float: a move rewrites one row)

  factory Ticket.fromRow(Map<String, dynamic> r) => Ticket(
        id: r['id'] as String,
        boardId: r['board_id'] as String,
        columnId: r['column_id'] as String,
        number: (r['number'] as num?)?.toInt() ?? 0,
        title: (r['title'] as String?) ?? '',
        description: (r['description'] as String?) ?? '',
        priority: priorityFrom(r['priority'] as String?),
        dueOn: r['due_on'] as String?,
        amount: r['amount'] == null ? null : _num(r['amount']),
        sort: (r['sort'] as num?)?.toDouble() ?? 0,
      );

  Ticket moved(String columnId, double sort) => Ticket(
      id: id, boardId: boardId, columnId: columnId, number: number, title: title,
      description: description, priority: priority, dueOn: dueOn, amount: amount, sort: sort);

  /// The editable fields, replaced wholesale (null clears the due date / price).
  Ticket edited({required String title, required String description, required TicketPriority priority, required String? dueOn, required double? amount}) =>
      Ticket(id: id, boardId: boardId, columnId: columnId, number: number, title: title,
          description: description, priority: priority, dueOn: dueOn, amount: amount, sort: sort);
}

/// A ticket to add — its id, number and sort come with the insert.
typedef NewTicket = ({String columnId, String title, String description, TicketPriority priority, String? dueOn, double? amount});

/// Rows that add [drafts] to [boardId] in one insert: numbered after the board's
/// highest number, each joining the bottom of its column in the order given.
List<Map<String, dynamic>> newTicketRows(String boardId, List<NewTicket> drafts, List<Ticket> existing) {
  final inBoard = existing.where((t) => t.boardId == boardId);
  var number = inBoard.fold<int>(0, (m, t) => t.number > m ? t.number : m);
  final bottom = <String, double>{}; // column id -> its last sort
  for (final t in inBoard) {
    if (t.sort > (bottom[t.columnId] ?? 0)) bottom[t.columnId] = t.sort;
  }
  final rows = <Map<String, dynamic>>[];
  for (final d in drafts) {
    final sort = (bottom[d.columnId] ?? 0) + sortStep;
    bottom[d.columnId] = sort;
    rows.add({
      'board_id': boardId,
      'column_id': d.columnId,
      'number': ++number,
      'title': d.title,
      'description': d.description,
      'priority': d.priority.name,
      'due_on': d.dueOn,
      'amount': d.amount,
      'sort': sort,
    });
  }
  return rows;
}

/// Columns a new board starts with (renamable, and more can be added).
const defaultBoardColumns = {
  BoardKind.todo: ['To do', 'In progress', 'Done'],
  BoardKind.shopping: ['To buy', 'In cart', 'Bought'],
};

const sortStep = 1024.0;

/// A sort value between two neighbours (either may be missing); null when they
/// are too close to split — renumber the column instead. Same rule as the web.
double? sortBetween(double? prev, double? next) {
  if (prev == null && next == null) return sortStep;
  if (prev == null) return next! - sortStep;
  if (next == null) return prev + sortStep;
  final mid = (prev + next) / 2;
  return next - prev > 1e-6 && mid > prev && mid < next ? mid : null;
}

/// Column order: sort, then ticket number for rows that share a sort.
int byTicketOrder(Ticket a, Ticket b) {
  final c = a.sort.compareTo(b.sort);
  return c != 0 ? c : a.number.compareTo(b.number);
}

/// 5 moods (1 = lowest .. 5 = highest), earthy brick -> forest green.
class MoodPreset {
  const MoodPreset(this.value, this.name, this.hex);

  final int value;
  final String name; // English, as the web shows it
  final String hex;

  /// In the app's language.
  String get label => tr('$name|mood');
  Color get color => hexColor(hex);
}

const moodPresets = [
  MoodPreset(1, 'Awful', '#A8322A'),
  MoodPreset(2, 'Low', '#C06A33'),
  MoodPreset(3, 'Okay', '#B59A3C'),
  MoodPreset(4, 'Good', '#6E8C46'),
  MoodPreset(5, 'Great', '#2E8159'),
];

MoodPreset moodPreset(num value) {
  var best = moodPresets.first;
  for (final m in moodPresets) {
    if ((m.value - value).abs() < (best.value - value).abs()) best = m;
  }
  return best;
}

/// Preset context tags for the mood entry (what the day was about).
const moodTags = [
  'Family time', 'Date', 'Friends', 'Travel', 'Shopping', 'Work',
  'Study', 'Exercise', 'Food', 'Rest', 'Health', 'Alone',
];

/// Default categories seeded for new users (editable in Settings).
const defaultExpenseCategories = [
  ('Food', '#C06A33'), ('Groceries', '#2E8159'), ('Transport', '#3D80BC'), ('Rent', '#7A4E86'),
  ('Utilities', '#B59A3C'), ('Internet', '#3D80BC'), ('Health', '#CB453B'), ('Education', '#4C5B82'),
  ('Shopping', '#8E5B6E'), ('Entertainment', '#A6694A'), ('Travel', '#2F6F6B'), ('Subscriptions', '#7A4E86'),
  ('Gifts', '#8E5B6E'), ('Fitness', '#6E8C46'), ('Personal Care', '#7A4E86'), ('Pets', '#B59A3C'),
  (breakSaving, '#3D80BC'), ('Other', '#7A746A'),
];

const defaultIncomeCategories = [
  ('Salary', '#2E8159'), ('Freelance', '#3D80BC'), ('Gift', '#7A4E86'), ('Other', '#7A746A'),
];

/// The dashboard's sections, in display order (same ids the web stores).
const dashboardSections = [
  ('kpis', 'Monthly summary', 'Spent · Earned · Saved · Avg mood'),
  ('trend', 'Mood × money trend', 'Net flow vs mood over time'),
  ('recap', 'Monthly recap', 'AI look back at the month, with what to change'),
  ('wallets', 'Wallets', "What's in cash, bKash, Nagad, the bank"),
  ('netWorth', 'Net worth', 'Wallets and dhar, month by month'),
  ('habits', 'Streaks & challenges', 'Your streak and the challenges going'),
  ('insights', 'AI insights', 'Mood · money · savings, with suggestions'),
  ('spent', 'Spent by category', 'Where the money went'),
  ('earned', 'Earned by category', 'Where the money came from'),
  ('mood', 'Mood distribution', 'How the days felt'),
  ('savings', 'Savings', 'Added vs broken'),
  ('moodTags', 'Mood was about', 'Tag frequency'),
  ('categories', 'Category frequency', 'Most-used categories'),
];

// Domain types — mirror src/types/index.ts of the Catalyst web app. Both apps
// read and write the same Supabase tables, so field names and rules match.
import 'package:flutter/painting.dart';

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
      );
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
  });

  final Kind kind;
  final double amount;
  final String? categoryId;
  final String categoryName;
  final String place;
  final String note;
  final String occurredOn;
  final String occurredAt;

  Map<String, dynamic> toRow() => {
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'category_name': categoryName,
        'place': place,
        'note': note,
        'occurred_on': occurredOn,
        'occurred_at': occurredAt,
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
  const Bill({required this.id, required this.name, required this.amount, required this.dueOn, required this.recurrence, required this.isPaid});

  final String id;
  final String name;
  final double amount;
  final String dueOn;
  final String recurrence; // monthly | weekly | yearly | once
  final bool isPaid;

  factory Bill.fromRow(Map<String, dynamic> r) => Bill(
        id: r['id'] as String,
        name: r['name'] as String,
        amount: _num(r['amount']),
        dueOn: r['due_on'] as String,
        recurrence: (r['recurrence'] as String?) ?? 'monthly',
        isPaid: (r['is_paid'] as bool?) ?? false,
      );

  Bill copyWith({bool? isPaid}) =>
      Bill(id: id, name: name, amount: amount, dueOn: dueOn, recurrence: recurrence, isPaid: isPaid ?? this.isPaid);
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
  const MoodPreset(this.value, this.label, this.hex);

  final int value;
  final String label;
  final String hex;
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
  ('insights', 'AI insights', 'Mood · money · savings, with suggestions'),
  ('spent', 'Spent by category', 'Where the money went'),
  ('earned', 'Earned by category', 'Where the money came from'),
  ('mood', 'Mood distribution', 'How the days felt'),
  ('savings', 'Savings', 'Added vs broken'),
  ('moodTags', 'Mood was about', 'Tag frequency'),
  ('categories', 'Category frequency', 'Most-used categories'),
];

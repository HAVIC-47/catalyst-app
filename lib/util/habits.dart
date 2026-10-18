// Streaks, challenges and mood-spend alerts, worked out from the entries
// themselves — a challenge stores only its settings. The web's src/lib/habits.ts
// in Dart (its reminders job uses that one too).
import '../models.dart';
import 'recurring.dart';

double _cents(double n) => (n * 100).roundToDouble() / 100;
bool _same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();
String _min(String a, String b) => a.compareTo(b) < 0 ? a : b;

/// Money spent by hand: an expense that isn't automatic (recurring) or savings broken.
bool isSpend(Txn t) => t.kind == Kind.expense && t.recurringId == null && t.categoryName != breakSaving;

// ---------------------------------------------------------------- streaks
/// Days with something logged by hand: a money entry (not an automatic one) or a mood.
Set<String> loggedDays(List<Txn> transactions, List<MoodLog> moods) => {
      for (final t in transactions)
        if (t.recurringId == null) t.occurredOn,
      for (final m in moods) m.loggedOn,
    };

/// Days in a row up to today (or up to yesterday, while today is still open), the
/// longest run ever, whether today already counts, and the current run's first day.
typedef Streak = ({int current, int best, bool todayDone, String? since});

Streak streakOf(Set<String> days, String today) {
  final todayDone = days.contains(today);
  var current = 0;
  String? since;
  for (var d = todayDone ? today : addDaysKey(today, -1); days.contains(d); d = addDaysKey(d, -1)) {
    current++;
    since = d;
  }
  var best = 0, run = 0;
  var prev = '';
  for (final d in days.where((k) => k.compareTo(today) <= 0).toList()..sort()) {
    run = prev.isNotEmpty && daysBetween(prev, d) == 1 ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return (current: current, best: best > current ? best : current, todayDone: todayDone, since: since);
}

/// Streak lengths worth a notification.
const streakMilestones = [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365];

/// The biggest milestone a streak of [n] days has reached (0 for none yet).
int streakMilestone(int n) {
  if (n >= 400) return n ~/ 100 * 100;
  return streakMilestones.where((m) => m <= n).lastOrNull ?? 0;
}

// ---------------------------------------------------------------- challenges
enum ChallengeStatus { upcoming, active, won, lost }

/// How a challenge stands today: its last day, the days left (including today),
/// what's counted so far against its goal, and a 0 … 1 ratio for a progress bar.
typedef ChallengeProgress = ({ChallengeStatus status, String endOn, int daysLeft, double value, double goal, double ratio});

/// Automatic entries (rent, subscriptions) never count as spending.
ChallengeProgress challengeProgress(Challenge c, List<Txn> transactions, List<MoodLog> moods, String today) {
  final days = c.days < 1 ? 1 : c.days;
  final endOn = addDaysKey(c.startOn, days - 1);
  final last = _min(today, endOn); // the window so far
  final complete = _min(addDaysKey(today, -1), endOn); // its days that are over
  final completeDays = complete.compareTo(c.startOn) < 0 ? 0 : daysBetween(c.startOn, complete) + 1;
  final over = today.compareTo(endOn) > 0;
  final daysLeft = over ? 0 : (today.compareTo(c.startOn) < 0 ? days : daysBetween(today, endOn) + 1);
  bool inWindow(String k, [String? to]) => k.compareTo(c.startOn) >= 0 && k.compareTo(to ?? last) <= 0;
  final spends = transactions.where((t) => isSpend(t) && inWindow(t.occurredOn)).toList();

  double value = 0, goal = 0, ratio = 0;
  var won = false, lost = false;
  switch (c.kind) {
    case ChallengeKind.noSpend:
      final g = c.target.round();
      goal = (g < 1 ? 1 : (g > days ? days : g)).toDouble();
      final spendDays = {for (final t in spends) if (t.occurredOn.compareTo(complete) <= 0) t.occurredOn};
      value = (completeDays - spendDays.length).toDouble();
      won = value >= goal;
      lost = !won && completeDays - value > days - goal;
      ratio = value / goal;
    case ChallengeKind.spendUnder:
      goal = c.target;
      value = _cents(spends.fold<double>(0, (s, t) => s + t.amount));
      lost = value > goal;
      won = !lost && over;
      ratio = goal > 0 ? value / goal : 1;
    case ChallengeKind.skipCategory:
      value = spends.where((t) => (c.categoryId != null && t.categoryId == c.categoryId) || _same(t.categoryName, c.categoryName)).length.toDouble();
      lost = value > 0;
      won = !lost && over;
      ratio = (days - daysLeft) / days;
    case ChallengeKind.save:
      goal = c.target;
      value = _cents(transactions.where((t) => t.kind == Kind.saving && inWindow(t.occurredOn)).fold<double>(0, (s, t) => s + t.amount));
      won = goal > 0 && value >= goal;
      lost = !won && over;
      ratio = goal > 0 ? value / goal : 0;
    case ChallengeKind.logDaily:
      goal = days.toDouble();
      final logged = loggedDays(transactions, moods);
      for (var d = c.startOn; d.compareTo(last) <= 0; d = addDaysKey(d, 1)) {
        if (logged.contains(d)) value++;
      }
      var missed = false;
      for (var d = c.startOn; d.compareTo(complete) <= 0; d = addDaysKey(d, 1)) {
        if (!logged.contains(d)) missed = true;
      }
      lost = missed;
      won = !lost && value >= days;
      ratio = value / days;
  }
  final status = today.compareTo(c.startOn) < 0
      ? ChallengeStatus.upcoming
      : won
          ? ChallengeStatus.won
          : lost
              ? ChallengeStatus.lost
              : ChallengeStatus.active;
  return (
    status: status,
    endOn: endOn,
    daysLeft: daysLeft,
    value: value,
    goal: goal,
    ratio: ratio.isFinite ? ratio.clamp(0.0, 1.0).toDouble() : 0.0,
  );
}

/// What a challenge asks, in words — [t] translates, [money] formats an amount.
String challengeTitle(Challenge c, String Function(String key, [Map<String, Object?> args]) t, String Function(double) money) {
  final days = c.days;
  return switch (c.kind) {
    ChallengeKind.noSpend => t('{n} no-spend days in {days} days', {'n': c.target.round(), 'days': days}),
    ChallengeKind.spendUnder => t('Spend under {amount} in {days} days', {'amount': money(c.target), 'days': days}),
    ChallengeKind.skipCategory => t('No {category} for {days} days', {'category': t(c.categoryName), 'days': days}),
    ChallengeKind.save => t('Save {amount} in {days} days', {'amount': money(c.target), 'days': days}),
    ChallengeKind.logDaily => t('Log something every day for {days} days', {'days': days}),
  };
}

// ---------------------------------------------------------------- mood × money
/// Spent by hand today, a usual day's spending (the 30 days before), their ratio
/// (one decimal) and today's average mood.
typedef MoodSpend = ({double spent, double usual, double ratio, double mood});

/// A low day (average mood 2.5 or under) with at least 1.5× the usual day's
/// spending — once there's a week of history to know what usual is.
MoodSpend? moodSpendAlert(List<Txn> transactions, List<MoodLog> moods, String today) {
  final todays = moods.where((m) => m.loggedOn == today).toList();
  if (todays.isEmpty) return null;
  final mood = todays.fold<int>(0, (s, m) => s + m.mood) / todays.length;
  if (mood > 2.5) return null;
  final spent = _cents(transactions.where((t) => isSpend(t) && t.occurredOn == today).fold<double>(0, (s, t) => s + t.amount));
  if (spent <= 0) return null;
  final first = transactions.fold<String>(today, (m, t) => t.occurredOn.compareTo(m) < 0 ? t.occurredOn : m);
  final monthAgo = addDaysKey(today, -30);
  final from = monthAgo.compareTo(first) > 0 ? monthAgo : first;
  final n = daysBetween(from, today);
  if (n < 7) return null;
  final before = transactions
      .where((t) => isSpend(t) && t.occurredOn.compareTo(from) >= 0 && t.occurredOn.compareTo(today) < 0)
      .fold<double>(0, (s, t) => s + t.amount);
  final usual = before / n;
  if (usual <= 0 || spent < usual * 1.5) return null;
  return (spent: spent, usual: _cents(usual), ratio: (spent / usual * 10).round() / 10, mood: (mood * 10).round() / 10);
}

/// Over the last [span] days: a low day's average spending next to a good day's
/// (null until there are at least 3 of each).
({double low, double good, int lowDays, int goodDays})? moodSpendPattern(List<Txn> transactions, List<MoodLog> moods, String today,
    {int span = 90}) {
  final from = addDaysKey(today, -(span - 1));
  final byDay = <String, List<int>>{};
  for (final m in moods) {
    if (m.loggedOn.compareTo(from) >= 0 && m.loggedOn.compareTo(today) <= 0) (byDay[m.loggedOn] ??= []).add(m.mood);
  }
  final spentOn = <String, double>{};
  for (final t in transactions) {
    if (isSpend(t) && t.occurredOn.compareTo(from) >= 0 && t.occurredOn.compareTo(today) <= 0) {
      spentOn[t.occurredOn] = (spentOn[t.occurredOn] ?? 0) + t.amount;
    }
  }
  double low = 0, good = 0;
  var lowDays = 0, goodDays = 0;
  for (final e in byDay.entries) {
    final avg = e.value.fold<int>(0, (s, x) => s + x) / e.value.length;
    if (avg <= 2.5) {
      lowDays++;
      low += spentOn[e.key] ?? 0;
    } else if (avg >= 3.5) {
      goodDays++;
      good += spentOn[e.key] ?? 0;
    }
  }
  if (lowDays < 3 || goodDays < 3) return null;
  return (low: _cents(low / lowDays), good: _cents(good / goodDays), lowDays: lowDays, goodDays: goodDays);
}

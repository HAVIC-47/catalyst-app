// Recurring income and expenses — when each one falls due. The web's
// src/lib/recurring.ts in Dart (the web and its hourly reminders job use that
// one), so every side works out the same dates.
//
// Dates are "yyyy-mm-dd" keys, counted in UTC so no clock change can shift a day.
// A rule remembers the next date it hasn't logged yet (nextOn); everything from
// there up to today is due.

/// How often a rule repeats.
enum Frequency { weekly, monthly, twiceMonthly }

Frequency frequencyFrom(String? s) => switch (s) {
      'weekly' => Frequency.weekly,
      'twice_monthly' => Frequency.twiceMonthly,
      _ => Frequency.monthly,
    };

String frequencyName(Frequency f) => switch (f) {
      Frequency.weekly => 'weekly',
      Frequency.monthly => 'monthly',
      Frequency.twiceMonthly => 'twice_monthly',
    };

/// What decides a rule's dates.
class Schedule {
  const Schedule({
    required this.frequency,
    this.every = 1,
    required this.day1,
    this.day2,
    required this.time,
    required this.startOn,
    this.endOn,
  });

  final Frequency frequency;
  final int every; // weeks or months between (1 = every week / month; twice a month ignores it)
  final int day1; // weekly: weekday 1 (Monday) … 7 (Sunday); otherwise a day of the month, 1 … 31
  final int? day2; // twice a month: the other day
  final String time; // "HH:mm", the rule's local time
  final String startOn; // nothing is logged before this date …
  final String? endOn; // … or after this one

  /// The same dates and time (a change to anything else keeps nextOn).
  bool sameAs(Schedule o) =>
      frequency == o.frequency &&
      every == o.every &&
      day1 == o.day1 &&
      (frequency != Frequency.twiceMonthly || day2 == o.day2) &&
      time == o.time &&
      startOn == o.startOn &&
      endOn == o.endOn;
}

final _key = RegExp(r'^\d{4}-\d{2}-\d{2}$');
DateTime _utc(String k) => DateTime.utc(int.parse(k.substring(0, 4)), int.parse(k.substring(5, 7)), int.parse(k.substring(8, 10)));
String _keyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _later(String a, String b) => a.compareTo(b) > 0 ? a : b;
int _clamp(int n, int lo, int hi) => n < lo ? lo : (n > hi ? hi : n);

String addDaysKey(String k, int n) => _keyOf(_utc(k).add(Duration(days: n)));
int daysBetween(String a, String b) => _utc(b).difference(_utc(a)).inDays;

/// 1 = Monday … 7 = Sunday.
int isoWeekday(String k) => _utc(k).weekday;

/// A day of the month; days past the month's end fall on its last day (31 → 30 April).
String _monthDay(int y, int m, int day) {
  final last = DateTime.utc(y, m + 1, 0).day;
  return _keyOf(DateTime.utc(y, m, day > last ? last : day));
}

/// The first date on or after [from] the schedule falls on — null once it has ended.
String? occurrenceOnOrAfter(Schedule s, String from) {
  if (!_key.hasMatch(s.startOn) || !_key.hasMatch(from)) return null;
  final lo = _later(from, s.startOn);
  final every = _clamp(s.every, 1, 12);
  var found = '';
  if (s.frequency == Frequency.weekly) {
    // The first matching weekday on or after the start, then every [every] weeks.
    final anchor = addDaysKey(s.startOn, ((_clamp(s.day1, 1, 7) - isoWeekday(s.startOn)) % 7 + 7) % 7);
    final step = 7 * every;
    found = lo.compareTo(anchor) <= 0 ? anchor : addDaysKey(anchor, (daysBetween(anchor, lo) / step).ceil() * step);
  } else {
    // Months counted from the start's month (every [every] months, or every month twice).
    final twice = s.frequency == Frequency.twiceMonthly;
    final step = twice ? 1 : every;
    final startIndex = int.parse(s.startOn.substring(0, 4)) * 12 + int.parse(s.startOn.substring(5, 7)) - 1;
    final loIndex = int.parse(lo.substring(0, 4)) * 12 + int.parse(lo.substring(5, 7)) - 1;
    final days = [for (final d in (twice && s.day2 != null ? [s.day1, s.day2!] : [s.day1])) _clamp(d, 1, 31)];
    final gap = ((loIndex - startIndex) / step).floor();
    final first = gap < 0 ? 0 : gap;
    for (var j = first; found.isEmpty && j < first + 3; j++) {
      final index = startIndex + j * step;
      final y = index ~/ 12, m = index % 12 + 1;
      final keys = [for (final d in days) _monthDay(y, m, d)]..sort();
      found = keys.where((k) => k.compareTo(lo) >= 0).firstOrNull ?? '';
    }
  }
  if (found.isEmpty) return null;
  return s.endOn != null && found.compareTo(s.endOn!) > 0 ? null : found;
}

/// The first date after [date].
String? occurrenceAfter(Schedule s, String date) => occurrenceOnOrAfter(s, addDaysKey(date, 1));

/// Dates due now, oldest first: from [nextOn] up to [today] — today once its time
/// ([now], "HH:mm") has come.
List<String> dueDates(Schedule s, {required String nextOn, required bool paused, required String today, required String now, int limit = 60}) {
  if (paused) return const [];
  final out = <String>[];
  for (var d = occurrenceOnOrAfter(s, nextOn);
      d != null && out.length < limit && (d.compareTo(today) < 0 || (d == today && s.time.compareTo(now) <= 0));
      d = occurrenceAfter(s, d)) {
    out.add(d);
  }
  return out;
}

/// What nextOn becomes once [last] is logged: the date after it, or — when the rule
/// has ended — the day after its end (a nextOn past endOn means finished).
String nextAfterLogged(Schedule s, String last) =>
    occurrenceAfter(s, last) ?? addDaysKey(_later(last, s.endOn ?? last), 1);

/// nextOn for a new or changed schedule: its first date from [from] on (the start
/// date for a new rule — earlier dates are logged too — or today after a change).
String firstNextOn(Schedule s, String from) => occurrenceOnOrAfter(s, from) ?? addDaysKey(_later(from, s.endOn ?? from), 1);

/// No more dates to log (its end date has passed).
bool hasEnded(Schedule s, String nextOn) => occurrenceOnOrAfter(s, nextOn) == null;

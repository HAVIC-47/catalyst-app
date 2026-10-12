import 'package:intl/intl.dart';

/// Bangladeshi Taka, with en-IN grouping (1,00,000 style) — same as the web.
const taka = '৳';

final _grouped0 = NumberFormat('#,##,##0', 'en_IN');
final _grouped2 = NumberFormat('#,##,##0.##', 'en_IN');

String formatCurrency(double value, {bool sign = false}) {
  final s = value > 0 ? (sign ? '+' : '') : (value < 0 ? '−' : '');
  final abs = value.abs();
  final f = abs % 1 == 0 ? _grouped0.format(abs) : _grouped2.format(abs);
  return '$s$taka$f';
}

/// Grouped number without the currency sign (e.g. "1,25,000").
String groupNumber(double value) => value % 1 == 0 ? _grouped0.format(value) : _grouped2.format(value);

/// Compact en-IN notation: 950, 43.1K, 1.4L, 2.3Cr.
String compactCurrency(double value) {
  final abs = value.abs();
  String body;
  if (abs >= 1e7) {
    body = '${_trim(abs / 1e7)}Cr';
  } else if (abs >= 1e5) {
    body = '${_trim(abs / 1e5)}L';
  } else if (abs >= 1e3) {
    body = '${_trim(abs / 1e3)}K';
  } else {
    body = _trim(abs);
  }
  return '${value < 0 ? '−' : ''}$taka$body';
}

String _trim(double v) {
  final r = (v * 10).round() / 10;
  return r % 1 == 0 ? r.toInt().toString() : r.toStringAsFixed(1);
}

/// yyyy-mm-dd in local time.
String toDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime fromDateKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Combine a yyyy-mm-dd date with an HH:mm time into an ISO timestamp (UTC).
String combineDateTime(String dateKey, String hhmm) {
  final d = fromDateKey(dateKey);
  final t = hhmm.split(':');
  final local = DateTime(d.year, d.month, d.day, int.tryParse(t[0]) ?? 12, int.tryParse(t.length > 1 ? t[1] : '0') ?? 0);
  return local.toUtc().toIso8601String();
}

String nowTime() {
  final d = DateTime.now();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String fmt(DateTime d, String pattern) => DateFormat(pattern, 'en_US').format(d);

DateTime startOfWeek(DateTime d) => DateTime(d.year, d.month, d.day - d.weekday % 7); // Sunday start
DateTime endOfWeek(DateTime d) => startOfWeek(d).add(const Duration(days: 6));
DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
bool sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

List<DateTime> daysBetween(DateTime start, DateTime end) {
  final out = <DateTime>[];
  for (var d = DateTime(start.year, start.month, start.day); !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    out.add(d);
  }
  return out;
}

/// Parse an ISO timestamp to local time (falls back to now).
DateTime parseTs(String iso) => (DateTime.tryParse(iso) ?? DateTime.now()).toLocal();

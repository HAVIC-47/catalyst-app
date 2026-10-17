import 'package:intl/intl.dart';

import 'currency.dart';
import 'i18n.dart';

/// The Bangladeshi taka sign — the default currency (see currency.dart for the chosen one).
const taka = '৳';

final _indian0 = NumberFormat('#,##,##0', 'en_IN');
final _indian2 = NumberFormat('#,##,##0.##', 'en_IN');
final _western0 = NumberFormat('#,##0', 'en_US');
final _western2 = NumberFormat('#,##0.##', 'en_US');

/// The account currency's sign, for amount fields and labels (৳ unless changed in Settings).
String currencySymbol() => currentCurrency.symbol.trim();

/// An amount in the account's currency: ৳1,25,000 by default (lakh grouping), $125,000 for dollars.
String formatCurrency(double value, {bool sign = false}) {
  final s = value > 0 ? (sign ? '+' : '') : (value < 0 ? '−' : '');
  return digits('$s${currentCurrency.symbol}${groupNumber(value.abs())}');
}

/// Grouped number without the currency sign (e.g. "1,25,000", or "125,000") — plain
/// digits, so it can prefill a field.
String groupNumber(double value) {
  final c = currentCurrency;
  final whole = value % 1 == 0 || c.decimals == 0;
  final f = c.indian ? (whole ? _indian0 : _indian2) : (whole ? _western0 : _western2);
  return f.format(whole && c.decimals == 0 ? value.roundToDouble() : value);
}

/// Short form: 950, 43.1K, 1.4L, 2.3Cr (lakh/crore currencies) or 1.4M, 2.3B.
String compactCurrency(double value) {
  final abs = value.abs();
  final indian = currentCurrency.indian;
  String body;
  if (indian && abs >= 1e7) {
    body = '${_trim(abs / 1e7)}Cr';
  } else if (indian && abs >= 1e5) {
    body = '${_trim(abs / 1e5)}L';
  } else if (!indian && abs >= 1e9) {
    body = '${_trim(abs / 1e9)}B';
  } else if (!indian && abs >= 1e6) {
    body = '${_trim(abs / 1e6)}M';
  } else if (abs >= 1e3) {
    body = '${_trim(abs / 1e3)}K';
  } else {
    body = _trim(abs);
  }
  return digits('${value < 0 ? '−' : ''}${currentCurrency.symbol}$body');
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

/// A date in the app's language (Bengali month names and digits in Bangla).
String fmt(DateTime d, String pattern) => DateFormat(pattern, isBangla ? 'bn' : 'en_US').format(d);

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

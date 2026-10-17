// Shared time-window helpers for dashboard charts (port of web src/lib/range.ts).
import 'format.dart';
import 'i18n.dart';

enum Range { day, week, month, year }

String rangeName(Range r) => switch (r) {
      Range.day => tr('Day'),
      Range.week => tr('Week'),
      Range.month => tr('Month'),
      Range.year => tr('Year'),
    };

class Window {
  const Window(this.startKey, this.endKey, this.label);
  final String startKey;
  final String endKey;
  final String label;
}

Window rangeWindow(Range range, int offset) {
  final now = DateTime.now();
  switch (range) {
    case Range.day:
      final d = DateTime(now.year, now.month, now.day + offset);
      final k = toDateKey(d);
      return Window(k, k, fmt(d, 'EEE, MMM d'));
    case Range.week:
      final a = DateTime(now.year, now.month, now.day + offset * 7);
      final s = startOfWeek(a), e = endOfWeek(a);
      return Window(toDateKey(s), toDateKey(e), '${fmt(s, 'MMM d')} – ${fmt(e, 'MMM d')}');
    case Range.month:
      final a = DateTime(now.year, now.month + offset, 1);
      return Window(toDateKey(startOfMonth(a)), toDateKey(endOfMonth(a)), fmt(a, 'MMMM yyyy'));
    case Range.year:
      final y = now.year + offset;
      return Window('$y-01-01', '$y-12-31', digits('$y'));
  }
}

bool inRange(String dateKey, String startKey, String endKey) =>
    dateKey.compareTo(startKey) >= 0 && dateKey.compareTo(endKey) <= 0;

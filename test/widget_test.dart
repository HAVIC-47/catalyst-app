import 'package:catalyst/models.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/math.dart';
import 'package:catalyst/util/range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('format', () {
    test('formatCurrency uses en-IN grouping and taka', () {
      expect(formatCurrency(125000), '৳1,25,000');
      expect(formatCurrency(-950), '−৳950');
      expect(formatCurrency(1300.5, sign: true), '+৳1,300.5');
    });

    test('compactCurrency matches the web (K / L / Cr)', () {
      expect(compactCurrency(950), '৳950');
      expect(compactCurrency(13000), '৳13K');
      expect(compactCurrency(43100), '৳43.1K');
      expect(compactCurrency(140000), '৳1.4L');
      expect(compactCurrency(-23000000), '−৳2.3Cr');
    });

    test('date keys round-trip and weeks start on Sunday', () {
      final d = DateTime(2026, 10, 13); // Tuesday
      expect(toDateKey(d), '2026-10-13');
      expect(fromDateKey('2026-10-13'), d);
      expect(toDateKey(startOfWeek(d)), '2026-10-11');
      expect(toDateKey(endOfWeek(d)), '2026-10-17');
      expect(toDateKey(endOfMonth(DateTime(2026, 2, 5))), '2026-02-28');
    });
  });

  test('rangeWindow covers the current month', () {
    final w = rangeWindow(Range.month, 0);
    final now = DateTime.now();
    expect(w.startKey, toDateKey(DateTime(now.year, now.month, 1)));
    expect(inRange(toDateKey(now), w.startKey, w.endKey), isTrue);
  });

  test('pearson + label', () {
    expect(pearson([1, 2, 3], [2, 4, 6]), closeTo(1, 1e-9));
    expect(pearson([1, 1], [2, 3]), 0);
    expect(correlationLabel(0.05), 'No clear link');
    expect(correlationLabel(0.47), startsWith('Moderate link'));
  });

  test('moodPreset snaps to nearest level', () {
    expect(moodPreset(4.4).label, 'Good');
    expect(moodPreset(0).label, 'Awful');
  });
}

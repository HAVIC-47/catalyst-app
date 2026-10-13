import 'package:flutter/services.dart';

/// Longest text each field accepts. db/security.sql (web repo) enforces the same
/// limits with CHECK constraints; the fields stop here so a long value never
/// turns into a database error.
class Limits {
  static const name = 100; // categories, activities, bills, boards, board columns
  static const title = 200; // goals, journal entries, tickets
  static const place = 200;
  static const note = 1000; // transaction + mood notes
  static const description = 5000; // ticket description
  static const body = 20000; // journal entry text
}

/// Caps a field at [max] characters without Flutter's "0/max" counter.
List<TextInputFormatter> maxChars(int max) => [LengthLimitingTextInputFormatter(max)];

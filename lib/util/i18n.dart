// Bangla UI. The English text is the key: tr('Wallets') is 'ওয়ালেট' when the app
// is in Bangla and bn.dart has it, else the English itself — so a missing
// translation shows English, never a blank. {name} slots are filled from args.
// The language is an account preference shared with the web (user metadata
// "lang"); dates and figures follow it (Bengali digits in Bangla).
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'bn.dart';

String _lang = 'en';

/// 'en' or 'bn'.
String get appLang => _lang;
bool get isBangla => _lang == 'bn';

/// Called at startup and by AppState when the preference loads or changes. A change
/// rebuilds every widget, since their text comes from tr().
Future<void> setAppLang(Object? lang) async {
  final next = lang == 'bn' ? 'bn' : 'en';
  if (next == _lang) return;
  if (next == 'bn') await initializeDateFormatting('bn');
  _lang = next;
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(mark);
}

/// The UI text for [en] in the current language. Numbers in [args] are written in
/// the language's digits. A word with two meanings carries its sense after a bar
/// ('Low|mood', 'Low|priority'): English shows the part before it.
String tr(String en, [Map<String, Object?> args = const {}]) {
  final bar = en.indexOf('|');
  final plain = bar < 0 ? en : en.substring(0, bar);
  var s = isBangla ? (bn[en] ?? plain) : plain;
  args.forEach((k, v) => s = s.replaceAll('{$k}', v is num ? digits('$v') : '$v'));
  return s;
}

/// Singular or plural: trn(n, '{n} payment', '{n} payments').
String trn(int n, String one, String many) => tr(n == 1 ? one : many, {'n': n});

const _bnDigits = '০১২৩৪৫৬৭৮৯';

/// Bengali digits in Bangla — for showing a number, never for a field's text.
String digits(String s) => isBangla ? s.replaceAllMapped(RegExp(r'\d'), (m) => _bnDigits[int.parse(m[0]!)]) : s;

/// Typed Bengali digits back to 0-9, so an amount parses whichever keyboard typed it.
String asciiDigits(String s) => s.replaceAllMapped(RegExp('[০-৯]'), (m) => '${_bnDigits.indexOf(m[0]!)}');

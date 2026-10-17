// Bangla UI: every tr('…') in lib/ has a translation, translations keep their
// {slots}, and the helpers (digits, fallbacks, words with two senses) behave.
import 'dart:io';

import 'package:catalyst/screens/wallets_screen.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/util/bn.dart';
import 'package:catalyst/util/currency.dart';
import 'package:catalyst/util/format.dart';
import 'package:catalyst/util/i18n.dart';
import 'package:catalyst/widgets/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';

/// A Dart string literal's text (the escapes the app's strings use).
String _unescape(String body) => body.replaceAllMapped(RegExp(r'\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|.)'), (m) {
      final e = m[1]!;
      if (e == 'n') return '\n';
      if (e == 't') return '\t';
      if (e.startsWith('u{')) return String.fromCharCode(int.parse(e.substring(2, e.length - 1), radix: 16));
      if (e.startsWith('u') && e.length == 5) return String.fromCharCode(int.parse(e.substring(1), radix: 16));
      return e;
    });

const _lit = r'''(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")''';

/// The literal keys passed to tr() and trn() in [source] (adjacent literals joined).
Iterable<String> _keys(String source) sync* {
  final group = '((?:$_lit\\s*)+)';
  String join(String g) => RegExp(_lit).allMatches(g).map((m) => _unescape(m[0]!.substring(1, m[0]!.length - 1))).join();
  for (final m in RegExp(r'\btr\(\s*' + group + r'\s*[,)]').allMatches(source)) {
    final k = join(m[1]!);
    if (!k.contains(r'$')) yield k;
  }
  for (final m in RegExp(r'\btrn\([^,()]+,\s*' + group + r'\s*,\s*' + group).allMatches(source)) {
    for (final g in [m[1]!, m[2]!]) {
      final k = join(g);
      if (!k.contains(r'$')) yield k;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setCurrency('BDT');
    await setAppLang('en');
  });
  tearDown(() => setAppLang('en'));

  test('every tr() text in lib/ has Bangla', () {
    final missing = <String>{};
    var count = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.replaceAll('\\', '/').endsWith('util/bn.dart')) continue;
      for (final k in _keys(f.readAsStringSync())) {
        count++;
        if (!bn.containsKey(k)) missing.add('${f.path}: $k');
      }
    }
    expect(count, greaterThan(500));
    expect(missing, isEmpty);
  });

  test('translations keep every {slot}', () {
    final slot = RegExp(r'\{(\w+)\}');
    final broken = [
      for (final e in bn.entries)
        if (slot.allMatches(e.key).map((m) => m[1]).any((s) => !e.value.contains('{$s}'))) e.key,
    ];
    expect(broken, isEmpty);
  });

  test('English shows the key; Bangla the translation, with Bengali digits', () async {
    expect(tr('Wallets'), 'Wallets');
    expect(tr('Low|mood'), 'Low'); // the sense after the bar never shows in English
    expect(tr('Not in the dictionary {n}', {'n': 3}), 'Not in the dictionary 3');
    await setAppLang('bn');
    expect(tr('Wallets'), 'ওয়ালেট');
    expect(tr('Low|mood'), isNot(tr('Low|priority')));
    expect(tr('{n} payment', {'n': 12}), '১২টি পেমেন্ট');
    expect(tr('Not in the dictionary {n}', {'n': 3}), 'Not in the dictionary ৩');
    expect(trn(1, '{n} payment', '{n} payments'), '১টি পেমেন্ট');
  });

  test('figures and dates follow the language; typed Bengali digits still parse', () async {
    expect(formatCurrency(125000.5), '৳1,25,000.5');
    await setAppLang('bn');
    expect(formatCurrency(125000.5), '৳১,২৫,০০০.৫');
    expect(compactCurrency(250000), '৳২.৫L');
    expect(fmt(DateTime(2026, 10, 17), 'd MMMM'), contains('অক্টোবর'));
    expect(groupNumber(1500), '1,500'); // a field's text stays plain digits
    expect(parseAmount('১,২৫০.৫০'), 1250.5);
    expect(parseSigned('−৫০'), -50);
    setCurrency('USD');
    expect(formatCurrency(1234.5), r'$১,২৩৪.৫');
  });

  testWidgets('the Wallets page in Bangla', (tester) async {
    await setAppLang('bn');
    final app = FakeApp()
      ..loading = false
      ..walletsReady = true
      ..wallets = const [
        Wallet(id: 'cash', name: 'Cash', kind: WalletKind.cash, color: '#2E8159', openingBalance: 1500, sort: 0, archived: false),
        Wallet(id: 'bk', name: 'bKash', kind: WalletKind.mobile, color: '#E2136E', openingBalance: 250, sort: 1, archived: false),
      ];
    await tester.pumpWidget(host(app, const WalletsScreen()));
    await tester.pump();
    expect(find.text('টাকা কোথায় আছে।'), findsOneWidget);
    expect(find.text('সব ওয়ালেট মিলে ৳১,৭৫০'), findsOneWidget);
    expect(find.text('৳১,৫০০'), findsOneWidget);
    expect(find.text('ক্যাশ · ডিফল্ট'), findsOneWidget);
    expect(find.text('মোবাইল ব্যাংকিং'), findsOneWidget);
  });
}

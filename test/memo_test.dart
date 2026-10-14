import 'package:catalyst/data/scan.dart';
import 'package:catalyst/models.dart';
import 'package:catalyst/screens/memo_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_app.dart';

FakeApp _app() => seeded()
  ..categories = const [
    Category(id: 'food', name: 'Food', kind: Kind.expense, color: '#C06A33', sort: 0),
    Category(id: 'other', name: 'Other', kind: Kind.expense, color: '#7A746A', sort: 1),
    Category(id: 'break', name: breakSaving, kind: Kind.expense, color: '#3D80BC', sort: 2),
    Category(id: 'salary', name: 'Salary', kind: Kind.income, color: '#2E8159', sort: 0),
  ];

Widget _opener() => Builder(builder: (c) => Center(child: TextButton(onPressed: () => openMemoScanner(c), child: const Text('open'))));

Map<String, dynamic> _entry(String type, String name, double amount, String category, {String date = ''}) =>
    {'type': type, 'name': name, 'amount': amount, 'category': category, 'newCategory': false, 'date': date};

void main() {
  final pick = Scan.pick, send = Scan.send;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    Scan.pick = pick;
    Scan.send = send;
  });

  testWidgets('a screenshot of notes -> expenses and income, with the missing categories created', (tester) async {
    final app = _app();
    final sent = <(String, Map<String, dynamic>)>[];
    Scan.pick = (_) async => png;
    Scan.send = (path, body) async {
      sent.add((path, body));
      return {
        'notes': {
          'date': '2026-10-12',
          'entries': [
            _entry('expense', 'Lunch', 250, 'Food'),
            _entry('expense', 'Gym fee', 1500, 'Gym', date: '2026-10-11'),
            _entry('income', 'Tuition', 5000, 'Tuition'),
            _entry('income', 'October salary', 65000, 'salary'),
          ],
        },
      };
    };

    await tester.pumpWidget(host(app, _opener()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Scan a memo'), findsOneWidget);
    expect(find.textContaining('or choose a screenshot of your notes'), findsOneWidget);
    await tester.tap(find.text('Choose photo or screenshot'));
    await tester.pumpAndSettle();

    final (path, body) = sent.single;
    expect(path, '/api/scan-memo');
    expect(body['notes'], isTrue);
    expect(body['categories'], ['Food', 'Other']); // Break saving isn't offered
    expect(body['incomeCategories'], ['Salary']);

    expect(find.text('Found 4 entries in your note. Check them — untick anything you don\'t want — then add.'), findsOneWidget);
    expect(find.text('New categories from your note will be created: Gym (expense), Tuition (income).'), findsOneWidget);
    expect(find.text('New: Gym'), findsOneWidget);
    expect(find.text('New: Tuition'), findsOneWidget);

    await tester.tap(find.text('Add 4 entries'));
    await tester.pumpAndSettle();
    expect(find.text('Added 4 entries'), findsOneWidget);
    expect(find.text('Spent ৳1,750 · Earned ৳70,000'), findsOneWidget);
    expect(find.text('New categories created: Gym (expense), Tuition (income). Rename or recolor them in Settings.'), findsOneWidget);

    final gym = app.categories.singleWhere((c) => c.name == 'Gym');
    final tuition = app.categories.singleWhere((c) => c.name == 'Tuition');
    expect((gym.kind, tuition.kind), (Kind.expense, Kind.income));
    final byNote = {for (final t in app.transactions) t.note: t};
    expect(byNote.keys.toSet(), {'Lunch', 'Gym fee', 'Tuition', 'October salary'});
    expect((byNote['Lunch']!.kind, byNote['Lunch']!.categoryId, byNote['Lunch']!.occurredOn), (Kind.expense, 'food', '2026-10-12'));
    expect((byNote['Gym fee']!.categoryId, byNote['Gym fee']!.occurredOn, byNote['Gym fee']!.amount), (gym.id, '2026-10-11', 1500));
    expect((byNote['Tuition']!.kind, byNote['Tuition']!.categoryId), (Kind.income, tuition.id));
    // "salary" in the note is filed under the user's own "Salary".
    expect((byNote['October salary']!.kind, byNote['October salary']!.categoryName), (Kind.income, 'Salary'));
  });

  testWidgets('unticked lines are left out, and their new categories are not created', (tester) async {
    final app = _app();
    Scan.pick = (_) async => png;
    Scan.send = (path, body) async => {
          'notes': {
            'date': '',
            'entries': [_entry('expense', 'Lunch', 250, 'Food'), _entry('expense', 'Gym fee', 1500, 'Gym')],
          },
        };
    await tester.pumpWidget(host(app, _opener()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo or screenshot'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).at(1)); // untick "Gym fee"
    await tester.pumpAndSettle();
    expect(find.textContaining('will be created'), findsNothing);
    await tester.tap(find.text('Add 1 entry'));
    await tester.pumpAndSettle();

    expect(find.text('Added 1 entry'), findsOneWidget);
    expect(find.textContaining('categories created'), findsNothing);
    expect(app.categories.where((c) => c.name == 'Gym'), isEmpty);
    expect(app.transactions.single.note, 'Lunch');
  });

  testWidgets('a receipt still reviews as a memo (one expense per item)', (tester) async {
    final app = _app();
    Scan.pick = (_) async => png;
    Scan.send = (path, body) async => {
          'memo': {
            'merchant': 'Agora',
            'date': '',
            'time': '',
            'currency': 'BDT',
            'items': [
              {'name': 'Rice', 'amount': 950, 'category': 'Food'},
              {'name': 'Soap', 'amount': 80, 'category': 'Other'},
            ],
            'extras': [],
            'discount': 0,
            'total': 1030,
          },
        };
    await tester.pumpWidget(host(app, _opener()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo or screenshot'));
    await tester.pumpAndSettle();
    expect(find.text('Add 2 expenses'), findsOneWidget);
    await tester.tap(find.text('Add 2 expenses'));
    await tester.pumpAndSettle();
    expect(find.text('Added 2 expenses'), findsOneWidget);
    expect(app.transactions.map((t) => (t.note, t.place, t.amount)).toSet(), {('Rice', 'Agora', 950), ('Soap', 'Agora', 80)});
  });
}

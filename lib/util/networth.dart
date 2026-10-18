// Net worth: what's in the wallets, plus dhar owed to you, minus dhar you owe —
// on any day, worked out from the entries, so the history needs nothing stored.
// The web's src/lib/networth.ts in Dart.
import '../models.dart';
import 'recurring.dart';

double _cents(double n) => (n * 100).roundToDouble() / 100;

/// Net worth at the end of [date]: every wallet's balance (transfers between them
/// change nothing), dhar owed to you and dhar you owe.
typedef NetWorth = ({String date, double cash, double owedToYou, double youOwe, double total});

/// A closed debt with something left (written off) stops counting after its last payment.
NetWorth netWorthOn(String date, List<Wallet> wallets, List<Txn> transactions, List<Debt> debts, List<DebtPayment> payments) {
  var cash = wallets.fold<double>(0, (s, w) => s + w.openingBalance);
  for (final t in transactions) {
    if (t.occurredOn.compareTo(date) > 0) continue;
    if (t.kind == Kind.income) cash += t.amount;
    if (t.kind == Kind.expense) cash -= t.amount;
  }
  double owedToYou = 0, youOwe = 0;
  final byDebt = <String, List<DebtPayment>>{};
  for (final p in payments) {
    (byDebt[p.debtId] ??= []).add(p);
  }
  for (final d in debts) {
    if (d.occurredOn.compareTo(date) > 0) continue;
    cash += d.lent ? -d.amount : d.amount;
    final pays = byDebt[d.id] ?? const <DebtPayment>[];
    double paid = 0;
    for (final p in pays) {
      if (p.paidOn.compareTo(date) > 0) continue;
      paid += p.amount;
      cash += d.lent ? p.amount : -p.amount;
    }
    final lastActivity = pays.fold<String>(d.occurredOn, (m, p) => p.paidOn.compareTo(m) > 0 ? p.paidOn : m);
    final left = d.closed && date.compareTo(lastActivity) >= 0 ? 0.0 : (d.amount - paid > 0 ? d.amount - paid : 0.0);
    if (d.lent) {
      owedToYou += left;
    } else {
      youOwe += left;
    }
  }
  cash = _cents(cash);
  owedToYou = _cents(owedToYou);
  youOwe = _cents(youOwe);
  return (date: date, cash: cash, owedToYou: owedToYou, youOwe: youOwe, total: _cents(cash + owedToYou - youOwe));
}

/// Net worth at the end of each month — up to [months] of them, from the first
/// month with an entry — with today as the last point.
List<NetWorth> netWorthSeries(String today, int months, List<Wallet> wallets, List<Txn> transactions, List<Debt> debts, List<DebtPayment> payments) {
  var first = today;
  for (final k in [for (final t in transactions) t.occurredOn, for (final d in debts) d.occurredOn]) {
    if (k.compareTo(first) < 0) first = k;
  }
  final ty = int.parse(today.substring(0, 4)), tm = int.parse(today.substring(5, 7));
  final fy = int.parse(first.substring(0, 4)), fm = int.parse(first.substring(5, 7));
  final gap = (ty - fy) * 12 + (tm - fm) + 1;
  final span = gap < months ? gap : months;
  final out = <NetWorth>[];
  for (var i = span - 1; i >= 1; i--) {
    // the last day of the month i months back = the day before the 1st of the month after it
    final index = ty * 12 + (tm - 1) - i + 1;
    final firstOfNext = '${index ~/ 12}-${(index % 12 + 1).toString().padLeft(2, '0')}-01';
    out.add(netWorthOn(addDaysKey(firstOfNext, -1), wallets, transactions, debts, payments));
  }
  out.add(netWorthOn(today, wallets, transactions, debts, payments));
  return out;
}

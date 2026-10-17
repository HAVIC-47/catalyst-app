// Money rules shared by the screens — the web's src/lib/money.ts: wallet balances,
// what's left on a debt, when a bill is due next and what paying it is logged as,
// and how much of a budget is used.
import '../models.dart';
import 'format.dart';

double _cents(double n) => (n * 100).roundToDouble() / 100;

/// Entries and debts without a wallet belong to this one: the first that isn't archived.
Wallet? defaultWallet(List<Wallet> wallets) {
  final live = wallets.where((w) => !w.archived).toList()..sort((a, b) => a.sort.compareTo(b.sort));
  return live.firstOrNull ?? wallets.firstOrNull;
}

/// The wallet an entry counts in: its own, else the default one (older entries
/// and entries whose wallet was deleted). Null when there are no wallets.
Wallet? Function(Txn) walletNamer(List<Wallet> wallets) {
  final byId = {for (final w in wallets) w.id: w};
  final fallback = defaultWallet(wallets);
  return (t) => byId[t.walletId] ?? fallback;
}

/// Each wallet's balance: opening balance + income − expenses, ± transfers, ± dhar
/// (lending takes money out, getting it back puts it in; borrowing the reverse).
/// Savings entries stay in the savings pool — move money with a transfer instead.
Map<String, double> walletBalances(
  List<Wallet> wallets,
  List<Txn> transactions,
  List<Transfer> transfers,
  List<Debt> debts,
  List<DebtPayment> payments,
) {
  final fallback = defaultWallet(wallets)?.id;
  final out = {for (final w in wallets) w.id: w.openingBalance};
  void add(String? id, double amount) {
    final key = id != null && out.containsKey(id) ? id : fallback;
    if (key != null) out[key] = (out[key] ?? 0) + amount;
  }

  for (final t in transactions) {
    if (t.kind == Kind.income) add(t.walletId, t.amount);
    if (t.kind == Kind.expense) add(t.walletId, -t.amount);
  }
  for (final t in transfers) {
    add(t.fromWallet, -t.amount);
    add(t.toWallet, t.amount);
  }
  final byId = {for (final d in debts) d.id: d};
  for (final d in debts) {
    add(d.walletId, d.lent ? -d.amount : d.amount);
  }
  for (final p in payments) {
    final d = byId[p.debtId];
    if (d != null) add(p.walletId, d.lent ? p.amount : -p.amount);
  }
  return {for (final e in out.entries) e.key: _cents(e.value)};
}

/// What's still owed on a debt (never below zero).
double debtRemaining(Debt debt, List<DebtPayment> payments) {
  final paid = payments.where((p) => p.debtId == debt.id).fold<double>(0, (s, p) => s + p.amount);
  final left = _cents(debt.amount - paid);
  return left > 0 ? left : 0;
}

/// Open = not closed and something is still owed.
bool debtIsOpen(Debt debt, List<DebtPayment> payments) => !debt.closed && debtRemaining(debt, payments) > 0;

/// The next due date after paying the one on [dueOn] (null: a one-off bill doesn't repeat).
String? nextDue(String dueOn, String recurrence) {
  final d = fromDateKey(dueOn);
  switch (recurrence) {
    case 'weekly':
      return toDateKey(d.add(const Duration(days: 7)));
    case 'monthly':
      // Same day next month, pulled back to the month's last day (Jan 31 -> Feb 28).
      final last = DateTime(d.year, d.month + 2, 0).day;
      return toDateKey(DateTime(d.year, d.month + 1, d.day > last ? last : d.day));
    case 'yearly':
      final last = DateTime(d.year + 1, d.month + 1, 0).day;
      return toDateKey(DateTime(d.year + 1, d.month, d.day > last ? last : d.day));
    default:
      return null;
  }
}

bool _same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

/// The expense category a bill's payment is logged under: its own, one named like
/// it, Utilities, or Other.
Category? billCategory(Bill bill, List<Category> categories) {
  final expense = categories.where((c) => c.kind == Kind.expense).toList();
  return expense.where((c) => c.id == bill.categoryId).firstOrNull ??
      expense.where((c) => _same(c.name, bill.name)).firstOrNull ??
      expense.where((c) => _same(c.name, 'Utilities')).firstOrNull ??
      expense.where((c) => _same(c.name, 'Other')).firstOrNull ??
      expense.firstOrNull;
}

/// How much of a monthly budget this month's expenses have used.
({double spent, double ratio}) budgetUse(Budget budget, List<Txn> transactions, [DateTime? now]) {
  final month = toDateKey(now ?? DateTime.now()).substring(0, 7);
  final spent = transactions
      .where((t) => t.kind == Kind.expense && t.occurredOn.startsWith(month))
      .where((t) => budget.categoryId == null || t.categoryId == budget.categoryId || _same(t.categoryName, budget.categoryName))
      .fold<double>(0, (s, t) => s + t.amount);
  return (spent: _cents(spent), ratio: budget.amount > 0 ? spent / budget.amount : 0);
}

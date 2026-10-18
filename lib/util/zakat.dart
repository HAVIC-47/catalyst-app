// Zakat: 2.5% of what you own (cash, gold, silver, savings, money owed to you,
// investments) less what you owe now — when that's at least the nisab, the value
// of 87.48 g of gold or 612.36 g of silver (7.5 or 52.5 bhori). An estimate; the
// screen says to ask a scholar. The web's src/lib/zakat.ts in Dart; the inputs
// live in the account's preferences ("zakat"), so both show the same figures.

const nisabGoldGrams = 87.48;
const nisabSilverGrams = 612.36;
const bhoriGrams = 11.664;
const zakatRate = 0.025;

class ZakatInputs {
  const ZakatInputs({
    this.basis = 'silver',
    this.unit = 'bhori',
    this.goldPrice = 0,
    this.silverPrice = 0,
    this.gold = 0,
    this.silver = 0,
    this.cash = 0,
    this.investments = 0,
    this.other = 0,
    this.debts = 0,
    this.useWallets = true,
    this.useDhar = true,
  });

  final String basis; // 'silver' or 'gold': which metal sets the nisab
  final String unit; // 'bhori' or 'g': gold and silver weights and prices are in it
  final double goldPrice; // per unit
  final double silverPrice;
  final double gold; // weight owned
  final double silver;
  final double cash; // cash and accounts not tracked in a wallet
  final double investments; // shares, business stock, other savings
  final double other;
  final double debts; // owed now and not in Dhar
  final bool useWallets; // count the wallets' balances
  final bool useDhar; // count Dhar (owed to you, and you owe)

  /// Stored inputs, with defaults for anything missing or malformed.
  factory ZakatInputs.fromJson(Object? raw) {
    final r = raw is Map ? raw : const {};
    double n(String k) {
      final v = r[k];
      return v is num && v.isFinite && v >= 0 ? v.toDouble() : 0;
    }

    bool b(String k) => r[k] is bool ? r[k] as bool : true;
    return ZakatInputs(
      basis: r['basis'] == 'gold' ? 'gold' : 'silver',
      unit: r['unit'] == 'g' ? 'g' : 'bhori',
      goldPrice: n('goldPrice'),
      silverPrice: n('silverPrice'),
      gold: n('gold'),
      silver: n('silver'),
      cash: n('cash'),
      investments: n('investments'),
      other: n('other'),
      debts: n('debts'),
      useWallets: b('useWallets'),
      useDhar: b('useDhar'),
    );
  }

  Map<String, dynamic> toJson() => {
        'basis': basis,
        'unit': unit,
        'goldPrice': goldPrice,
        'silverPrice': silverPrice,
        'gold': gold,
        'silver': silver,
        'cash': cash,
        'investments': investments,
        'other': other,
        'debts': debts,
        'useWallets': useWallets,
        'useDhar': useDhar,
      };

  ZakatInputs copyWith({
    String? basis,
    String? unit,
    double? goldPrice,
    double? silverPrice,
    double? gold,
    double? silver,
    double? cash,
    double? investments,
    double? other,
    double? debts,
    bool? useWallets,
    bool? useDhar,
  }) =>
      ZakatInputs(
        basis: basis ?? this.basis,
        unit: unit ?? this.unit,
        goldPrice: goldPrice ?? this.goldPrice,
        silverPrice: silverPrice ?? this.silverPrice,
        gold: gold ?? this.gold,
        silver: silver ?? this.silver,
        cash: cash ?? this.cash,
        investments: investments ?? this.investments,
        other: other ?? this.other,
        debts: debts ?? this.debts,
        useWallets: useWallets ?? this.useWallets,
        useDhar: useDhar ?? this.useDhar,
      );
}

/// The nisab's weight in a unit.
double nisabWeight(String basis, String unit) {
  final grams = basis == 'gold' ? nisabGoldGrams : nisabSilverGrams;
  return unit == 'g' ? grams : grams / bhoriGrams;
}

double _cents(double n) => (n * 100).roundToDouble() / 100;

/// What zakat is counted on ([net], never below zero), the nisab (0 until the
/// nisab metal's price is filled in), whether it's reached, and what's due.
typedef ZakatResult = ({double goldValue, double silverValue, double assets, double liabilities, double net, double nisab, bool above, double due});

ZakatResult zakatOf(ZakatInputs i, {required double wallets, required double owedToYou, required double youOwe}) {
  final goldValue = _cents(i.gold * i.goldPrice);
  final silverValue = _cents(i.silver * i.silverPrice);
  final assets = _cents((i.useWallets ? wallets : 0) + i.cash + (i.useDhar ? owedToYou : 0) + goldValue + silverValue + i.investments + i.other);
  final liabilities = _cents((i.useDhar ? youOwe : 0) + i.debts);
  final diff = _cents(assets - liabilities);
  final net = diff > 0 ? diff : 0.0;
  final nisab = _cents(nisabWeight(i.basis, i.unit) * (i.basis == 'gold' ? i.goldPrice : i.silverPrice));
  final above = nisab > 0 && net >= nisab;
  return (
    goldValue: goldValue,
    silverValue: silverValue,
    assets: assets,
    liabilities: liabilities,
    net: net,
    nisab: nisab,
    above: above,
    due: above ? _cents(net * zakatRate) : 0.0,
  );
}

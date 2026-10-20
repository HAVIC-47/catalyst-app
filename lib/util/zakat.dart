// Zakat: 2.5% of what you own (cash, gold, silver, savings, money owed to you,
// investments) less what you owe now — when that's at least the nisab, the value
// of 87.48 g of gold or 612.36 g of silver (7.5 or 52.5 bhori). An estimate; the
// screen says to ask a scholar. The web's src/lib/zakat.ts in Dart; the inputs
// live in the account's preferences ("zakat"), so both show the same figures.

const nisabGoldGrams = 87.48;
const nisabSilverGrams = 612.36;
const bhoriGrams = 11.664;
const zakatRate = 0.025;

/// Gold purities the calculator offers (karat / 24 = the share that's gold).
const karats = [24, 22, 21, 18];

class ZakatInputs {
  const ZakatInputs({
    this.basis = 'silver',
    this.unit = 'bhori',
    this.autoPrices = true,
    this.goldPrice = 0,
    this.silverPrice = 0,
    this.gold = 0,
    this.karat = 22,
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
  final bool autoPrices; // today's international prices (else goldPrice / silverPrice)
  final double goldPrice; // per unit, 24K — used when autoPrices is off
  final double silverPrice;
  final double gold; // weight owned
  final int karat; // the gold's purity: 24, 22, 21 or 18
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
    final k = r['karat'];
    return ZakatInputs(
      basis: r['basis'] == 'gold' ? 'gold' : 'silver',
      unit: r['unit'] == 'g' ? 'g' : 'bhori',
      autoPrices: b('autoPrices'),
      goldPrice: n('goldPrice'),
      silverPrice: n('silverPrice'),
      gold: n('gold'),
      karat: k is num && karats.contains(k) ? k.toInt() : 22,
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
        'autoPrices': autoPrices,
        'goldPrice': goldPrice,
        'silverPrice': silverPrice,
        'gold': gold,
        'karat': karat,
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
    bool? autoPrices,
    double? goldPrice,
    double? silverPrice,
    double? gold,
    int? karat,
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
        autoPrices: autoPrices ?? this.autoPrices,
        goldPrice: goldPrice ?? this.goldPrice,
        silverPrice: silverPrice ?? this.silverPrice,
        gold: gold ?? this.gold,
        karat: karat ?? this.karat,
        silver: silver ?? this.silver,
        cash: cash ?? this.cash,
        investments: investments ?? this.investments,
        other: other ?? this.other,
        debts: debts ?? this.debts,
        useWallets: useWallets ?? this.useWallets,
        useDhar: useDhar ?? this.useDhar,
      );
}

/// Grams in one of a unit.
double unitGrams(String unit) => unit == 'g' ? 1 : bhoriGrams;

/// Today's international prices per gram (24K gold, pure silver), from the web's /api/metal-prices.
typedef LivePrices = ({double gold, double silver});

/// The prices the sums use, per unit: today's when auto and loaded, else the typed ones.
({double gold, double silver}) pricesOf(ZakatInputs i, LivePrices? live) {
  if (i.autoPrices && live != null) {
    final g = unitGrams(i.unit);
    return (gold: _cents(live.gold * g), silver: _cents(live.silver * g));
  }
  return (gold: i.goldPrice, silver: i.silverPrice);
}

/// The nisab's weight in a unit.
double nisabWeight(String basis, String unit) {
  final grams = basis == 'gold' ? nisabGoldGrams : nisabSilverGrams;
  return unit == 'g' ? grams : grams / bhoriGrams;
}

double _cents(double n) => (n * 100).roundToDouble() / 100;

/// What zakat is counted on ([net], never below zero), the nisab (0 until the
/// nisab metal's price is known), whether it's reached, and what's due.
typedef ZakatResult = ({double goldValue, double silverValue, double assets, double liabilities, double net, double nisab, bool above, double due});

ZakatResult zakatOf(ZakatInputs i, {required double wallets, required double owedToYou, required double youOwe, LivePrices? live}) {
  final price = pricesOf(i, live);
  // Only the gold in the jewellery counts: a 22K piece is 22/24 gold.
  final goldValue = _cents(i.gold * price.gold * (i.karat / 24));
  final silverValue = _cents(i.silver * price.silver);
  final assets = _cents((i.useWallets ? wallets : 0) + i.cash + (i.useDhar ? owedToYou : 0) + goldValue + silverValue + i.investments + i.other);
  final liabilities = _cents((i.useDhar ? youOwe : 0) + i.debts);
  final diff = _cents(assets - liabilities);
  final net = diff > 0 ? diff : 0.0;
  final nisab = _cents(nisabWeight(i.basis, i.unit) * (i.basis == 'gold' ? price.gold : price.silver));
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

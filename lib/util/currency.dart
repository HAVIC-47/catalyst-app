// The account's currency — the web's src/lib/currency.ts. Amounts are plain
// numbers; this only decides how they're written (sign, digit grouping). Taka
// unless changed in Settings, stored in the account's preferences so the web and
// the app agree. formatCurrency() and friends read the current one.

class CurrencyInfo {
  const CurrencyInfo(this.code, this.symbol, this.name, {this.indian = false, this.decimals = 2});

  final String code;
  final String symbol; // as it sits before the number
  final String name;
  final bool indian; // 1,00,000 grouping and K / L / Cr short forms
  final int decimals;
}

const currencies = [
  CurrencyInfo('BDT', '৳', 'Bangladeshi taka', indian: true),
  CurrencyInfo('USD', r'$', 'US dollar'),
  CurrencyInfo('CAD', r'C$', 'Canadian dollar'),
  CurrencyInfo('EUR', '€', 'Euro'),
  CurrencyInfo('GBP', '£', 'British pound'),
  CurrencyInfo('AUD', r'A$', 'Australian dollar'),
  CurrencyInfo('INR', '₹', 'Indian rupee', indian: true),
  CurrencyInfo('PKR', 'Rs ', 'Pakistani rupee', indian: true),
  CurrencyInfo('SAR', 'SAR ', 'Saudi riyal'),
  CurrencyInfo('AED', 'AED ', 'UAE dirham'),
  CurrencyInfo('MYR', 'RM', 'Malaysian ringgit'),
  CurrencyInfo('SGD', r'S$', 'Singapore dollar'),
  CurrencyInfo('JPY', '¥', 'Japanese yen', decimals: 0),
];

CurrencyInfo currencyOf(Object? code) => currencies.firstWhere((c) => c.code == code, orElse: () => currencies.first);

CurrencyInfo _current = currencies.first;

/// The account's currency right now.
CurrencyInfo get currentCurrency => _current;

/// Called by AppState when the preference loads or changes.
CurrencyInfo setCurrency(Object? code) => _current = currencyOf(code);

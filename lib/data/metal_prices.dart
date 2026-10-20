// Today's international gold and silver prices for the zakat calculator, from
// the web's /api/metal-prices: per gram in the account's currency (24K gold).
// Public — no login needed. Kept for half an hour, so coming back to the screen
// doesn't fetch again.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../util/zakat.dart';

typedef MetalPrices = ({LivePrices prices, DateTime? updatedAt});

/// Where the zakat screen gets them (tests swap in an answer that needs no network).
Future<MetalPrices?> Function(String currency) metalPrices = fetchMetalPrices;

final _cache = <String, (DateTime, MetalPrices)>{};

/// Null when they can't be had (offline, or the price services are down).
Future<MetalPrices?> fetchMetalPrices(String currency) async {
  final hit = _cache[currency];
  if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 30)) return hit.$2;
  try {
    final res = await http
        .get(Uri.parse('$apiBaseUrl/api/metal-prices?currency=${Uri.encodeQueryComponent(currency)}'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final d = jsonDecode(res.body);
    if (d is! Map) return null;
    final gold = d['gold'] is num ? (d['gold'] as num).toDouble() : 0.0;
    final silver = d['silver'] is num ? (d['silver'] as num).toDouble() : 0.0;
    if (!(gold > 0 && silver > 0)) return null;
    final MetalPrices out = (prices: (gold: gold, silver: silver), updatedAt: DateTime.tryParse('${d['updatedAt']}')?.toLocal());
    _cache[currency] = (DateTime.now(), out);
    return out;
  } catch (_) {
    return null;
  }
}

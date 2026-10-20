// Category icons: a curated set of Lucide icons (the web has the same set in
// src/lib/category-icons.ts). A category's chosen icon is stored by name in
// categories.icon; without one, the icon is picked from the category's name.
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Every icon a category can have, in the order the picker shows them.
const categoryIcons = <String, IconData>{
  'utensils': LucideIcons.utensils,
  'coffee': LucideIcons.coffee,
  'pizza': LucideIcons.pizza,
  'shopping-basket': LucideIcons.shoppingBasket,
  'shopping-bag': LucideIcons.shoppingBag,
  'shirt': LucideIcons.shirt,
  'bus': LucideIcons.bus,
  'car': LucideIcons.car,
  'fuel': LucideIcons.fuel,
  'bike': LucideIcons.bike,
  'train-front': LucideIcons.trainFront,
  'plane': LucideIcons.plane,
  'house': LucideIcons.house,
  'zap': LucideIcons.zap,
  'droplet': LucideIcons.droplet,
  'flame': LucideIcons.flame,
  'wifi': LucideIcons.wifi,
  'smartphone': LucideIcons.smartphone,
  'tv': LucideIcons.tv,
  'heart-pulse': LucideIcons.heartPulse,
  'pill': LucideIcons.pill,
  'stethoscope': LucideIcons.stethoscope,
  'graduation-cap': LucideIcons.graduationCap,
  'book-open': LucideIcons.bookOpen,
  'baby': LucideIcons.baby,
  'users': LucideIcons.users,
  'paw-print': LucideIcons.pawPrint,
  'dumbbell': LucideIcons.dumbbell,
  'sparkles': LucideIcons.sparkles,
  'scissors': LucideIcons.scissors,
  'gamepad-2': LucideIcons.gamepad2,
  'music': LucideIcons.music,
  'clapperboard': LucideIcons.clapperboard,
  'repeat': LucideIcons.repeat,
  'gift': LucideIcons.gift,
  'hand-heart': LucideIcons.handHeart,
  'receipt': LucideIcons.receipt,
  'shield': LucideIcons.shield,
  'wrench': LucideIcons.wrench,
  'landmark': LucideIcons.landmark,
  'piggy-bank': LucideIcons.piggyBank,
  'hand-coins': LucideIcons.handCoins,
  'briefcase': LucideIcons.briefcase,
  'laptop': LucideIcons.laptop,
  'store': LucideIcons.store,
  'trending-up': LucideIcons.trendingUp,
  'banknote': LucideIcons.banknote,
  'coins': LucideIcons.coins,
  'wallet': LucideIcons.wallet,
  'tag': LucideIcons.tag,
  'circle-ellipsis': LucideIcons.circleEllipsis,
};

RegExp _re(String source) => RegExp(source, caseSensitive: false);

// Name → icon, first match wins (English and Bangla words). Short English words
// are whole words, so "Transport" isn't sport and "Personal Care" isn't a car.
final _auto = <(RegExp, String)>[
  (_re(r'break saving|saving|সঞ্চয়'), 'piggy-bank'),
  (_re(r'salary|wage|payroll|বেতন'), 'briefcase'),
  (_re(r'freelanc|client|project|ফ্রিল্যান্স'), 'laptop'),
  (_re(r'business|\bshop\b|\bstore\b|\bsales?\b|ব্যবসা|দোকান'), 'store'),
  (_re(r'invest|stock|\bshares?\b|dividend|profit|বিনিয়োগ|শেয়ার'), 'trending-up'),
  (_re(r'interest|\bbank\b|ব্যাংক'), 'landmark'),
  (_re(r'\bloans?\b|\bdebts?\b|\bemi\b|\bdhar\b|ধার|ঋণ'), 'hand-coins'),
  (_re(r'refund|cashback|bonus|reward'), 'coins'),
  (_re(r'charity|donat|zakat|sadaq|যাকাত|জাকাত|দান'), 'hand-heart'),
  (_re(r'gift|উপহার'), 'gift'),
  (_re(r'coffee|\btea\b|\bcafe\b|কফি'), 'coffee'),
  (_re(r'pizza|burger|fast ?food'), 'pizza'),
  (_re(r'grocer|bazar|bazaar|market|super ?shop|বাজার|মুদি'), 'shopping-basket'),
  (_re(r'food|meal|lunch|dinner|breakfast|restaurant|snack|\beat|খাবার|খাওয়া'), 'utensils'),
  (_re(r'\bfuel\b|petrol|diesel|octane|\bcng\b|জ্বালানি'), 'fuel'),
  (_re(r'personal care|\bcare\b|salon|\bhair|barber|beauty|cosmetic|যত্ন|সৌন্দর্য'), 'sparkles'),
  (_re(r'\bcars?\b|\buber\b|\btaxi\b|\bride|গাড়ি'), 'car'),
  (_re(r'\bbikes?\b|cycle|motorcycle|সাইকেল|বাইক'), 'bike'),
  (_re(r'\btrains?\b|\bmetro\b|\brail'), 'train-front'),
  (_re(r'flight|travel|\btrips?\b|\btour|hotel|holiday|vacation|ভ্রমণ'), 'plane'),
  (_re(r'transport|\bbus\b|rickshaw|commute|pathao|যাতায়াত|রিকশা'), 'bus'),
  (_re(r'\bbaby|\bkids?\b|child|সন্তান|বাচ্চা'), 'baby'),
  (_re(r'family|parent|পরিবার'), 'users'),
  (_re(r'\brent\b|\bhouse|\bhome\b|\bflat\b|ভাড়া|বাসা|বাড়ি'), 'house'),
  (_re(r'electric|utilit|\bpower\b|বিদ্যুৎ|ইউটিলিটি'), 'zap'),
  (_re(r'\bwater\b|পানি'), 'droplet'),
  (_re(r'\bgas\b|গ্যাস'), 'flame'),
  (_re(r'internet|wi-?fi|broadband|ইন্টারনেট'), 'wifi'),
  (_re(r'phone|mobile|recharge|top ?up|ফোন|মোবাইল|রিচার্জ'), 'smartphone'),
  (_re(r'\btv\b|\bcable\b|\bdish\b|netflix|stream'), 'tv'),
  (_re(r'medic|pharma|\bpills?\b|\bdrugs?\b|ঔষধ|ওষুধ'), 'pill'),
  (_re(r'doctor|clinic|hospital|ডাক্তার|হাসপাতাল'), 'stethoscope'),
  (_re(r'health|স্বাস্থ্য'), 'heart-pulse'),
  (_re(r'school|tuition|course|educat|universit|college|\bexams?\b|শিক্ষা|পড়া|স্কুল'), 'graduation-cap'),
  (_re(r'\bbooks?\b|বই'), 'book-open'),
  (_re(r'\bpets?\b|\bcats?\b|\bdogs?\b|পোষা'), 'paw-print'),
  (_re(r'\bgym\b|fitness|\bsports?\b|\byoga\b|ফিটনেস|ব্যায়াম'), 'dumbbell'),
  (_re(r'cloth|fashion|\bdress|\bshoes?\b|পোশাক|কাপড়'), 'shirt'),
  (_re(r'shopping|কেনাকাটা'), 'shopping-bag'),
  (_re(r'\bgames?\b|gaming'), 'gamepad-2'),
  (_re(r'music|concert|spotify'), 'music'),
  (_re(r'movie|cinema|entertain|বিনোদন|সিনেমা'), 'clapperboard'),
  (_re(r'subscri|সাবস্ক্রিপশন'), 'repeat'),
  (_re(r'\btax|\bfees?\b|charge|\bvat\b|\bbills?\b|বিল'), 'receipt'),
  (_re(r'insur|বিমা'), 'shield'),
  (_re(r'repair|mainten|\bservice|\bfix|মেরামত'), 'wrench'),
  (_re(r'\bcash\b|salami|money|টাকা|সালামি'), 'banknote'),
  (_re(r'wallet|ওয়ালেট'), 'wallet'),
  (_re(r'other|misc|অন্যান্য'), 'circle-ellipsis'),
];

/// The icon name a category shows: its own (when it's one of ours), else one picked from its name.
String categoryIconName(String name, [String? icon]) {
  if (icon != null && categoryIcons.containsKey(icon)) return icon;
  for (final (re, id) in _auto) {
    if (re.hasMatch(name)) return id;
  }
  return 'tag';
}

IconData categoryIcon(String name, [String? icon]) => categoryIcons[categoryIconName(name, icon)]!;

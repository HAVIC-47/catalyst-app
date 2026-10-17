// What the app does (Settings → About the app) and what each release brought (the
// pop-up after an update, and the top of About). Built when shown, so the text
// follows the language. These are the Android app's features — the web lists its own.
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config.dart';
import '../util/i18n.dart';

class Feature {
  const Feature(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

class FeatureGroup {
  const FeatureGroup(this.title, this.accent, this.features);

  final String title; // "Money"
  final String accent; // "& entries" (italic)
  final List<Feature> features;
}

class Release {
  const Release(this.version, this.notes);

  final String version; // "1.4.0"
  final List<Feature> notes;
}

/// What each release brought, newest first — add one for every version shipped.
List<Release> releases() => [
      Release('1.4.2', [
        if (googleSignIn)
          Feature(LucideIcons.keyRound, tr('Continue with Google'), tr('Sign in with your Google account — no password to remember.')),
        Feature(
          LucideIcons.settings,
          tr('Settings, sorted'),
          tr('Settings is a short list now — language and currency, reminders, dashboard, categories, bKash & Nagad, '
              'account — each on its own page.'),
        ),
        Feature(
          LucideIcons.appWindow,
          tr('Four new widgets'),
          tr('This month, Wallets, Bills due and a Mood check-in. Press and hold your home screen, tap Widgets, then '
              'Catalyst.'),
        ),
      ]),
      Release('1.4.1', [
        Feature(
          LucideIcons.share2,
          tr('Share a bKash or Nagad message'),
          tr('Press and hold the message in your Messages app, tap Share, then Catalyst — or copy it and paste it in '
              'Settings. The entry is ready for you to check.'),
        ),
        Feature(
          LucideIcons.shieldCheck,
          tr('No SMS permission'),
          tr("The app doesn't ask to read your messages any more, so Android no longer blocks installing it."),
        ),
      ]),
      Release('1.4.0', [
        Feature(LucideIcons.wallet, tr('Wallets'), tr("Cash, bKash, Nagad and Bank: what's in each, and transfers between them.")),
        Feature(LucideIcons.handCoins, tr('Dhar / baki'), tr('Money you lent or borrowed, per person — part payments, settle, write off.')),
        Feature(
          LucideIcons.receipt,
          tr('Bills that log themselves'),
          tr('Tick a bill when you pay it: the expense is added and the bill moves to its next date. Undo takes both back.'),
        ),
        Feature(LucideIcons.bellRing, tr('Reminders'), tr('An evening check-in, bills and dhar due tomorrow, and budget alerts at 80% and 100%.')),
        Feature(LucideIcons.wifiOff, tr('Works offline'), tr("Everything stays on the phone; entries and moods made offline sync when you're back online.")),
        Feature(LucideIcons.appWindow, tr('Home-screen widget'), tr("Today's spending at a glance, and a + for a quick entry.")),
        Feature(LucideIcons.messageSquareText, tr('bKash / Nagad messages'), tr('Optional: entries suggested from payment messages, read on the phone only.')),
        Feature(LucideIcons.calendarCheck, tr('AI monthly recap'), tr('The month in one read on the dashboard, with what to do differently next time.')),
        Feature(LucideIcons.coins, tr('Currency'), tr('Taka by default — or dollar, Canadian dollar, euro, rupee and more.')),
        Feature(LucideIcons.languages, 'বাংলা', tr('The whole app in Bangla, with Bengali dates and digits.')),
        Feature(
          LucideIcons.keyRound,
          tr('Account'),
          googleSignIn ? tr('Forgot password, Google sign-in and Delete account.') : tr('Forgot password and Delete account.'),
        ),
        Feature(LucideIcons.download, tr('Updates'), tr("The app tells you when a new version is out — Update downloads it — and shows what's new.")),
        Feature(LucideIcons.sparkles, tr('A new look'), tr('A new logo, and Settings → About the app lists everything Catalyst does.')),
      ]),
    ];

/// Everything the app does, by theme.
List<FeatureGroup> appFeatures() {
  final site = Uri.tryParse(apiBaseUrl)?.host ?? apiBaseUrl;
  return [
    FeatureGroup(tr('Money'), tr('& entries'), [
      Feature(LucideIcons.plus, tr('Quick entry'), tr('Expense, income, savings or a mood in a few taps — each with a time, place and note.')),
      Feature(
        LucideIcons.receipt,
        tr('Ledger'),
        tr('Every entry by day, with search (even "october" or "monday") and filters. Tap the pen to change or delete one — '
            'every total follows.'),
      ),
      Feature(
        LucideIcons.scanLine,
        tr('Memo scanner'),
        tr('Photograph a memo or receipt, or pick a screenshot of your notes: its lines become entries for you to check. '
            'Reads Bengali and English, printed or handwritten.'),
      ),
      Feature(
        LucideIcons.wallet,
        tr('Wallets'),
        tr("Cash, bKash, Nagad and Bank to start. See what's in each; transfers move money between them without counting as spending."),
      ),
      Feature(
        LucideIcons.bell,
        tr('Bills'),
        tr('Due dates, repeats and overdue warnings. Tick a bill when you pay it: the expense is logged and the bill moves to its next date.'),
      ),
      Feature(LucideIcons.piggyBank, tr('Budgets'), tr('Monthly limits per category that fill up as you spend, with alerts at 80% and 100%.')),
      Feature(LucideIcons.target, tr('Goals'), tr('Savings targets with progress bars and quick additions.')),
      Feature(LucideIcons.handCoins, tr('Dhar / baki'), tr('Money you lent or borrowed, per person: part payments, settle in full or write off.')),
      Feature(LucideIcons.vault, tr('Vault Mode'), tr('Count every income and expense against your savings pool.')),
    ]),
    FeatureGroup(tr('Mood'), tr('& days'), [
      Feature(LucideIcons.smile, tr('Mood check-in'), tr('Five moods, with what the day was about — work, family, travel…')),
      Feature(
        LucideIcons.calendarDays,
        tr('Calendar'),
        tr('Week, month and year views. Every day is tinted by its mood and its money; tap one to log.'),
      ),
      Feature(LucideIcons.notebookPen, tr('Journal'), tr('A daily log with a mood, plus habits to tick off each day.')),
      Feature(
        LucideIcons.layoutGrid,
        tr('Dashboard'),
        tr('The month at a glance: spent, earned, saved, average mood, the mood × money trend and charts by category.'),
      ),
    ]),
    FeatureGroup(tr('Lists'), tr('& plans'), [
      Feature(
        LucideIcons.listTodo,
        tr('To-do and To buy'),
        tr('Boards with columns and numbered tickets — priority, due dates, notes and prices. Press and hold to drag.'),
      ),
      Feature(
        LucideIcons.scanText,
        tr('Lists from a screenshot'),
        tr('On a board, + adds a whole list from a screenshot or photo — ticked items land as done, with Undo.'),
      ),
    ]),
    FeatureGroup(tr('AI'), tr('& insights'), [
      Feature(
        LucideIcons.sparkles,
        tr('AI summaries'),
        tr('A weekly, monthly or yearly read of your money, mood, journal, goals, bills and boards — with suggestions.'),
      ),
      Feature(LucideIcons.calendarCheck, tr('AI monthly recap'), tr('The month in one read on the dashboard, with what to do differently next time.')),
    ]),
    FeatureGroup(tr('On your'), tr('phone'), [
      Feature(
        LucideIcons.bellRing,
        tr('Reminders'),
        tr('An evening "how was today?", bills and dhar due tomorrow, and budget alerts — scheduled on the phone, so they work offline.'),
      ),
      Feature(
        LucideIcons.wifiOff,
        tr('Works offline'),
        tr("A copy of your data stays on the phone. Entries and moods made offline — for any date — sync when you're back online."),
      ),
      Feature(
        LucideIcons.appWindow,
        tr('Home-screen widgets'),
        tr('Spent today with a quick +, this month, your wallets, bills due, and a mood check-in you tap to log.'),
      ),
      Feature(
        LucideIcons.messageSquareText,
        tr('bKash / Nagad messages'),
        tr('Share a payment message to Catalyst (or paste it in Settings) and the app suggests the entry. It\'s read on '
            'the phone only, and nothing is saved until you add it.'),
      ),
      Feature(LucideIcons.download, tr('Updates'), tr("The app tells you when a new version is out — Update downloads it — and shows what's new.")),
    ]),
    FeatureGroup(tr('Your'), tr('way'), [
      Feature(LucideIcons.languages, 'বাংলা', tr('The whole app in Bangla, with Bengali dates and digits.')),
      Feature(LucideIcons.coins, tr('Currency'), tr('Taka by default; switch to dollar, Canadian dollar, euro, rupee and more. Nothing is converted.')),
      Feature(LucideIcons.sunMoon, tr('Dark and light'), tr('Dark by default — switch any time from More.')),
      Feature(
        LucideIcons.slidersHorizontal,
        tr('Your dashboard'),
        tr('Choose in Settings which sections the dashboard shows — the web follows the same choice.'),
      ),
    ]),
    FeatureGroup(tr('Account'), tr('& sync'), [
      Feature(
        LucideIcons.refreshCw,
        tr('One account, two apps'),
        tr('The same login and the same data as the web app at {site} — anything added on one shows up on the other.', {'site': site}),
      ),
      Feature(
        LucideIcons.keyRound,
        tr('Sign-in'),
        googleSignIn
            ? tr('Email and password or Google — and Forgot password if you lose it.')
            : tr('Email and password — and Forgot password if you lose it.'),
      ),
      Feature(LucideIcons.shieldCheck, tr('Private'), tr('Your entries are locked to your account — no one else can read them.')),
      Feature(LucideIcons.userX, tr('Delete account'), tr('Removes the account and everything in it, from Settings.')),
    ]),
  ];
}

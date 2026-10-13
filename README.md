<div align="center">

# Catalyst — Android app

**Money meets _mood_.** Track every taka against how the day actually felt.

[![Download APK](https://img.shields.io/badge/Download-Catalyst%20APK-B2462C?style=for-the-badge&logo=android&logoColor=white)](https://github.com/HAVIC-47/catalyst-app/releases/latest/download/Catalyst.apk)
&nbsp;
[![Latest release](https://img.shields.io/github/v/release/HAVIC-47/catalyst-app?style=for-the-badge&color=181512&label=version)](https://github.com/HAVIC-47/catalyst-app/releases/latest)

**Direct download (latest version):** https://github.com/HAVIC-47/catalyst-app/releases/latest/download/Catalyst.apk

Android 7.0+ · Flutter · same account and data as the [Catalyst web app](https://catalyst-hishab.vercel.app)

</div>

<p align="center">
  <img src="docs/screenshots/calendar.png" width="200" alt="Calendar — month view with mood faces and spend / income tints" />
  <img src="docs/screenshots/dashboard.png" width="200" alt="Dashboard — monthly summary and mood × money trend" />
  <img src="docs/screenshots/year.png" width="200" alt="Calendar — year heatmap" />
</p>
<p align="center">
  <img src="docs/screenshots/todo.png" width="200" alt="To-do board — columns of numbered tickets" />
  <img src="docs/screenshots/to-buy.png" width="200" alt="To buy list — items with prices and column totals" />
  <img src="docs/screenshots/memo-scan.png" width="200" alt="Memo scanner — items read from a receipt, ready to add" />
</p>
<p align="center">
  <img src="docs/screenshots/ai-summary.png" width="200" alt="AI money summary with suggestions on the ledger" />
  <img src="docs/screenshots/mood-entry.png" width="200" alt="Logging a mood with context tags" />
  <img src="docs/screenshots/calendar-light.png" width="200" alt="Calendar in light mode" />
</p>

## Install

1. On your phone, open the **[direct download link](https://github.com/HAVIC-47/catalyst-app/releases/latest/download/Catalyst.apk)**
   (or download it on a computer and send it over USB, Drive, Telegram…).
2. Open the downloaded `Catalyst.apk`. Android asks once to allow installs from your browser or
   file manager — allow it, then tap **Install**.
3. Log in with your Catalyst account, or create one.

The download is a universal APK (~56 MB) that runs on any Android phone. A smaller build for
modern 64-bit phones, [`Catalyst-arm64.apk`](https://github.com/HAVIC-47/catalyst-app/releases/latest/download/Catalyst-arm64.apk) (~21 MB), is attached to every
[release](https://github.com/HAVIC-47/catalyst-app/releases).

**Updating:** install the newer APK over the old one — your data lives in the cloud, nothing is lost.

**New in 1.2.0:** **To-do** and **To buy** boards — Jira-style columns you drag tickets across (press and
hold a ticket); **AI summaries and suggestions** for your money, savings, goals, bills, journal and mood, by
week, month or year; and a new bottom bar — Calendar · Dashboard · **+** · Ledger · More, where **+** opens
the memo scanner and Journal now lives in More. Install it over the older version — you stay logged in.
[Release notes](https://github.com/HAVIC-47/catalyst-app/releases/latest)

## One account, two apps

The app talks to the **same Supabase backend** as the [web app](https://github.com/HAVIC-47/catalyst)
([live](https://catalyst-hishab.vercel.app)). Log in with the same email and you see the same
transactions, moods, budgets, goals, bills, journal and boards. Anything added on one shows up on the other —
pull down to refresh, or just reopen the app.

## Features

- **Calendar** — week, month and year views. Every day is tinted by its mood and by heavier spend or
  income, with a mood face and the day's amounts. The month view always fits one screen; the year view
  is a 12-month heatmap. Tap any day to log money or mood.
- **Dashboard** — this month's spent / earned / saved / average mood, a mood × money trend (net cash
  flow bars against the mood line, with correlation), and charts for spending and income by category,
  mood distribution, savings, mood tags and category frequency. Choose which sections to show in
  Settings — the choice is shared with the web app.
- **Ledger** — every transaction grouped by day, with search (note, category, place, amount, even
  "october" or "monday") and filters by type, period or date range, category and amount.
- **Memo scanner** — tap **+** in the middle of the bottom bar, take or choose a photo of a memo/receipt,
  check what it found (shop, date, every item with its category), and each item — plus VAT or service charge —
  is added as its own expense, with any discount shared out. Reads Bengali and English, printed or handwritten.
- **To-do and To buy** — Jira-style boards in More: status columns (To do → In progress → Done; To buy →
  In cart → Bought), numbered tickets with priority, due date, notes and — on to-buy lists — a price. Press and
  hold a ticket to drag it within or across columns (the board scrolls when you reach an edge); tap it to edit.
- **AI summaries and suggestions** — a weekly, monthly or yearly read of your ledger, savings, goals, bills,
  journal and mood, with suggestions to manage money, save more or feel better — on each of those screens and
  the dashboard. Written by Gemini on the web app's server and saved, so the web and the app show the same one.
- **Quick entry** — expense and income in one go, five moods with context tags (work, family, travel…),
  and savings; each with a time, place and note.
- **Budgets** — monthly limits per category that fill up as you spend and turn red when you go over.
- **Goals** — savings targets with progress bars and quick additions.
- **Bills** — due dates, recurrence, overdue / due-soon warnings, one-tap paid.
- **Journal** — a daily log with a mood, plus custom habits to tick off each day.
- **Vault Mode** — count all income and spending against your savings pool.
- **Dark and light themes** — dark by default, the same design as the web.

## Build from source

Requirements: [Flutter](https://docs.flutter.dev/get-started/install) 3.47+, JDK 17 and the Android SDK.

```powershell
git clone https://github.com/HAVIC-47/catalyst-app.git
cd catalyst-app
copy env.example.json env.json     # then fill in your Supabase URL + anon key
.\build_apk.bat                    # -> dist\Catalyst.apk
```

`build_apk.ps1` options: `-Small` builds the 64-bit-only APK, `-Install` installs it on a phone
connected over USB (with USB debugging on). Release builds are obfuscated; keep `build\symbols` if
you want to read crash stack traces later.

To run on a connected phone or emulator while developing:

```powershell
flutter run --dart-define-from-file=env.json
```

### Configuration

`env.json` (git-ignored) holds the Supabase project the app connects to — the same values as the web
app's `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`:

```json
{ "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co", "SUPABASE_ANON_KEY": "your-anon-key" }
```

The memo scanner sends photos to the web app's `/api/scan-memo`, and the AI summaries call its
`/api/ai-insights` (set `API_BASE_URL` to point them elsewhere; it defaults to the live site), with the user's
login token. The Gemini key lives only on that server — it is never in this repo or the APK.

The anon key is public by design; every table is protected by row-level security, so each account
only ever sees its own rows. The database schema and its hardening live in the web repo
(`db/supabase.sql`, `db/security.sql`).

### Signing

Release builds are signed with the keystore named in `android/key.properties`. Both files are
git-ignored — without them the build falls back to the debug key, which installs fine but can't
update an app that was signed with the release key.

## Project structure

```
lib/
  main.dart            app entry, auth gate, themes
  config.dart          Supabase settings (from env.json at build time)
  models.dart          domain types — mirror the web's src/types
  data/repo.dart       Supabase queries — mirror the web's src/lib/db
  data/app_state.dart  central store — mirrors the web's useAppData
  data/secure_session_storage.dart  login session in Keystore-encrypted storage
  data/insights.dart   AI summaries client (the web's /api/ai-insights)
  screens/memo_sheet.dart  memo scanner: photo -> review -> one expense per item
  screens/boards_screen.dart  To-do / To buy boards with drag and drop
  widgets/ai_insights.dart  the AI summary card
  util/limits.dart     text length limits (same as the database checks)
  theme/               design tokens (same values as the web's globals.css)
  widgets/             cards, buttons, segmented controls, charts, mood faces
  screens/             one screen per web page, plus the entry sheet and app shell
build_apk.ps1          release build script (build_apk.bat to double-click)
```

## Tech

Flutter 3.47 · Dart 3.13 · [supabase_flutter](https://pub.dev/packages/supabase_flutter) ·
provider · [Lucide](https://lucide.dev) icons · charts drawn with `CustomPainter` ·
fonts: Newsreader, Hanken Grotesk and IBM Plex Mono (SIL Open Font License, bundled in `assets/fonts`).

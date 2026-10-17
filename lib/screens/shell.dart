// App shell — the web's layout on a phone: "TODAY" top bar, the page, and the
// bottom nav (Calendar · Dashboard · + · Ledger · More). The center + scans a
// memo or a screenshot of notes — or, on To-do and To buy, a screenshot of a
// list. The More sheet holds the other sections (Journal, To-do, To buy, …),
// New entry, Vault Mode, theme and sign out.
//
// It also runs the phone-side helpers: reminders and the home-screen widget
// follow the data, notices (budget alerts, offline saves) show as snack bars,
// and slim banners say when the app is offline and when a new version is out.
// A bKash / Nagad message shared to the app opens for review, and the first
// launch after an update pops up what's new.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/app_state.dart';
import '../models.dart';
import '../services/notifications.dart';
import '../services/sms.dart';
import '../services/updates.dart';
import '../services/whats_new.dart';
import '../services/widget_sync.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../widgets/ui.dart';
import '../widgets/wallet_picker.dart';
import 'about_screen.dart';
import 'bills_screen.dart';
import 'boards_screen.dart';
import 'budgets_screen.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import 'dhar_screen.dart';
import 'entry_sheet.dart';
import 'goals_screen.dart';
import 'journal_screen.dart';
import 'ledger_screen.dart';
import 'list_scan_sheet.dart';
import 'memo_sheet.dart';
import 'settings_screen.dart';
import 'sms_review_sheet.dart';
import 'wallets_screen.dart';

enum Section { calendar, dashboard, ledger, journal, todo, shopping, budgets, goals, bills, wallets, dhar, settings }

const _calendarTab = (Section.calendar, 'Calendar', LucideIcons.calendarDays);
const _dashboardTab = (Section.dashboard, 'Dashboard', LucideIcons.layoutGrid);
const _ledgerTab = (Section.ledger, 'Ledger', LucideIcons.receipt);
const _tabs = [_calendarTab, _dashboardTab, _ledgerTab];

/// Sections that aren't in the bottom bar.
const _moreSections = [
  (Section.journal, 'Journal', LucideIcons.notebookPen),
  (Section.todo, 'To-do', LucideIcons.listTodo),
  (Section.shopping, 'To buy', LucideIcons.shoppingCart),
  (Section.budgets, 'Budgets', LucideIcons.piggyBank),
  (Section.goals, 'Goals', LucideIcons.target),
  (Section.bills, 'Bills', LucideIcons.bell),
  (Section.wallets, 'Wallets', LucideIcons.wallet),
  (Section.dhar, 'Dhar', LucideIcons.handCoins),
  (Section.settings, 'Settings', LucideIcons.settings),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  Section _section = Section.calendar;
  late final AppState _app = context.read<AppState>();
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _follow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app.ensureLoaded();
    _app.addListener(_onData);
    _subs
      ..add(_app.notices.stream.listen(_notice))
      ..add(Notifications.taps.stream.listen(_open))
      ..add(HomeWidget.actions.stream.listen(_widgetAction))
      ..add(SmsShare.shared.stream.listen(_shared));
    loadLastWallet();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_onData);
    for (final s in _subs) {
      s.cancel();
    }
    _follow?.cancel();
    super.dispose();
  }

  // Back in the foreground: pick up anything changed on the web meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _app.load();
      _checkUpdate();
    }
  }

  Future<void> _start() async {
    // Opened from a reminder, from the widget's +, or by sharing a message to the app.
    final target = Notifications.launchTarget;
    Notifications.launchTarget = null;
    if (target != null) _open(target);
    final action = await HomeWidget.launchAction();
    if (action != null) _widgetAction(action);
    final shared = await SmsShare.launchText();
    if (shared != null) _shared(shared);
    _checkUpdate();
    if (target == null && action == null && shared == null) await _whatsNew();
    await _askForNotifications();
  }

  /// Once after an update: what it brought (and, if asked, every feature).
  Future<void> _whatsNew() async {
    final due = await WhatsNew.due();
    if (due.isEmpty || !mounted) return;
    if (await showWhatsNew(context, due) && mounted) await openAbout(context);
  }

  /// Reminders and the widget follow the data (a moment after it settles).
  void _onData() {
    _follow?.cancel();
    _follow = Timer(const Duration(milliseconds: 600), () {
      if (_app.loading) return;
      Notifications.sync(_app);
      HomeWidget.sync(_app);
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Where a notification leads.
  void _open(String target) {
    if (!mounted) return;
    switch (target) {
      case NoticeTarget.mood:
        openEntry(context, tab: EntryTab.mood);
      case NoticeTarget.bills:
        go(Section.bills);
      case NoticeTarget.dhar:
        go(Section.dhar);
      case NoticeTarget.update:
        final u = Updates.available.value;
        if (u != null) Updates.download(u);
    }
  }

  /// A home-screen widget tap: the +, a widget opening its page, or a mood face.
  void _widgetAction(String action) {
    if (!mounted) return;
    final colon = action.indexOf(':');
    final kind = colon < 0 ? action : action.substring(0, colon);
    final arg = colon < 0 ? '' : action.substring(colon + 1);
    switch (kind) {
      case 'add':
        openEntry(context);
      case 'open':
        final section = const {'dashboard': Section.dashboard, 'wallets': Section.wallets, 'bills': Section.bills}[arg];
        if (section != null) go(section);
      case 'mood':
        final mood = int.tryParse(arg);
        if (mood != null) openEntry(context, tab: EntryTab.mood, mood: mood);
    }
  }

  void _checkUpdate() => Updates.check(
        onNew: (u) => Notifications.showNow(
          5000,
          tr('Catalyst {version} is out', {'version': u.version}),
          tr('Tap to download the update.'),
          NoticeTarget.update,
        ),
      );

  /// A bKash / Nagad message shared to the app: what it would add, for review.
  void _shared(String text) {
    if (mounted) reviewSharedText(context, text);
  }

  /// Ask once for notification permission (Android 13+) when a reminder is on.
  Future<void> _askForNotifications() async {
    final r = _app.reminders;
    if (!Notifications.supported || !(r.checkin || r.bills || r.dhar || r.budgets)) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notifications:asked') ?? false) return;
    await prefs.setBool('notifications:asked', true);
    await Notifications.request();
  }

  void go(Section s) => setState(() => _section = s);

  /// The + adds from a photo: a list onto the board on screen, else a memo or notes.
  BoardKind? get _board => switch (_section) {
        Section.todo => BoardKind.todo,
        Section.shopping => BoardKind.shopping,
        _ => null,
      };

  void _scan(BuildContext context) {
    final kind = _board;
    kind == null ? openMemoScanner(context) : openListScanner(context, kind);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pages = {
      Section.calendar: const CalendarScreen(),
      Section.dashboard: DashboardScreen(
        onCustomize: () => openSettingsPage(context, SettingsPage.dashboard),
        onWallets: () => go(Section.wallets),
      ),
      Section.ledger: const LedgerScreen(),
      Section.journal: const JournalScreen(),
      Section.todo: const BoardsScreen(kind: BoardKind.todo),
      Section.shopping: const BoardsScreen(kind: BoardKind.shopping),
      Section.budgets: const BudgetsScreen(),
      Section.goals: const GoalsScreen(),
      Section.bills: const BillsScreen(),
      Section.wallets: const WalletsScreen(),
      Section.dhar: const DharScreen(),
      Section.settings: const SettingsScreen(),
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: p.paper,
        systemNavigationBarIconBrightness: p.dark ? Brightness.light : Brightness.dark,
      ),
      child: PopScope(
        canPop: _section == Section.calendar,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) go(Section.calendar);
        },
        child: Scaffold(
          backgroundColor: p.paper,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _TopBar(),
                const _OfflineBanner(),
                const _UpdateBanner(),
                Expanded(child: KeyedSubtree(key: ValueKey(_section), child: pages[_section]!)),
              ],
            ),
          ),
          bottomNavigationBar: _BottomNav(
            current: _section,
            onSelect: go,
            scanLabel: _board == null ? tr('Scan a memo or notes') : tr('Add from a screenshot of your list'),
            onScan: () => _scan(context),
            onMore: () => _openMore(context),
          ),
        ),
      ),
    );
  }

  void _openMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (c) => _MoreSheet(
        current: _section,
        onSelect: (s) {
          Navigator.pop(c);
          go(s);
        },
        // Open from the shell's context — the sheet's is gone once it closes.
        onNewEntry: () {
          Navigator.pop(c);
          openEntry(context);
        },
      ),
    );
  }
}

/// A slim notice under the top bar, with one action and an optional close.
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action, this.onAction, this.onClose, this.tint});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onClose;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = tint ?? p.accent;
    return Container(
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), border: Border(bottom: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
      child: Row(children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 12.5, color: p.muted(0.75)))),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action!.toUpperCase(), style: monoStyle(p, 11, weight: FontWeight.w600, color: c, letterSpacing: 1.2)),
          ),
        if (onClose != null)
          IconButton(
            tooltip: tr('Dismiss'),
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: Icon(LucideIcons.x, size: 15, color: p.muted(0.45)),
          ),
      ]),
    );
  }
}

/// No connection, or entries made offline still waiting to be sent.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    if (!app.offline && app.unsent == 0) return const SizedBox.shrink();
    final since = app.offlineSince;
    final text = app.offline
        ? [
            since == null
                ? tr('Offline — nothing saved on this phone yet.')
                : tr('Offline — showing what was saved {when}.', {'when': fmt(since, 'MMM d, h:mm a')}),
            if (app.unsent > 0) trn(app.unsent, '{n} change waits to sync.', '{n} changes wait to sync.'),
          ].join(' ')
        : trn(app.unsent, '{n} change made offline is waiting to sync.', '{n} changes made offline are waiting to sync.');
    return _Banner(icon: LucideIcons.cloudOff, text: text, tint: p.muted(0.7), action: tr('Retry'), onAction: app.load);
  }
}

/// A newer release on GitHub: Update opens its APK in the browser (it downloads).
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: Updates.available,
      builder: (context, u, _) {
        if (u == null) return const SizedBox.shrink();
        return _Banner(
          icon: LucideIcons.download,
          text: tr('Catalyst {version} is out — you have {current}.', {'version': u.version, 'current': Updates.current}),
          action: tr('Update'),
          onAction: () async {
            if (!await Updates.download(u) && context.mounted) {
              showError(context, tr('Couldn\'t open the download — get it from {url}', {'url': latestApkUrl}));
            }
          },
          onClose: () => Updates.dismiss(u),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: p.paper, border: Border(bottom: BorderSide(color: p.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Label(tr('Today')),
          const SizedBox(width: 8),
          Text(fmt(DateTime.now(), 'EEE, MMM d, yyyy'), style: monoStyle(p, 14, color: p.muted(0.7))),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.onSelect, required this.scanLabel, required this.onScan, required this.onMore});

  final Section current;
  final ValueChanged<Section> onSelect;
  final String scanLabel;
  final VoidCallback onScan;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final moreActive = !_tabs.any((t) => t.$1 == current);
    Widget item(String label, IconData icon, bool active, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            selected: active,
            label: label,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (active)
                        Positioned(
                          top: 4,
                          child: Container(width: 28, height: 2, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(2))),
                        ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 19, color: active ? p.accent : p.muted(0.45)),
                          const SizedBox(height: 3),
                          Text(label, style: bodyStyle(p, 10.5, weight: FontWeight.w500, color: active ? p.accent : p.muted(0.45))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: p.paper, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              for (final t in [_calendarTab, _dashboardTab]) item(tr(t.$2), t.$3, current == t.$1, () => onSelect(t.$1)),
              // Add from a photo (a memo or notes, or a list on the boards) — the
              // center action. Same fixed height as the tabs, so the bar never grows.
              Expanded(
                child: SizedBox(
                  height: 60,
                  child: Center(
                    child: Tooltip(
                      message: scanLabel,
                      child: Semantics(
                        button: true,
                        label: scanLabel,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: p.accentA(p.dark ? 0.45 : 0.5), blurRadius: p.dark ? 26 : 16, offset: Offset(0, p.dark ? 8 : 6), spreadRadius: -8),
                            ],
                          ),
                          child: Material(
                            color: p.accent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onScan,
                              child: Icon(LucideIcons.plus, size: 24, color: p.onAccent),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              item(tr(_ledgerTab.$2), _ledgerTab.$3, current == _ledgerTab.$1, () => onSelect(_ledgerTab.$1)),
              item(tr('More'), LucideIcons.ellipsis, moreActive, onMore),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.current, required this.onSelect, required this.onNewEntry});

  final Section current;
  final ValueChanged<Section> onSelect;
  final VoidCallback onNewEntry;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final theme = context.watch<ThemeController>();
    final email = isConfigured ? Supabase.instance.client.auth.currentUser?.email : null;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: p.line),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: SafeArea(
        top: false,
        // Scrolls on short phones instead of overflowing.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: p.inkA(0.2), borderRadius: BorderRadius.circular(4))),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Label(tr('More'))),
                IconButton(tooltip: tr('Close'), onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.45))),
              ]),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.95,
                children: [
                  for (final s in _moreSections)
                    Semantics(
                      button: true,
                      selected: current == s.$1,
                      label: tr(s.$2),
                      child: Material(
                        color: current == s.$1 ? p.accentA(0.08) : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: current == s.$1 ? p.accentA(0.4) : p.line),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onSelect(s.$1),
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(s.$3, size: 20, color: current == s.$1 ? p.accent : p.muted(0.6)),
                                const SizedBox(height: 6),
                                Text(tr(s.$2),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: bodyStyle(p, 11, weight: FontWeight.w500, color: current == s.$1 ? p.accent : p.muted(0.6))),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(color: p.line, height: 1),
              const SizedBox(height: 14),
              PrimaryButton(
                expand: true,
                height: 48,
                icon: LucideIcons.plus,
                label: tr('New entry'),
                onPressed: onNewEntry,
              ),
              const SizedBox(height: 10),
              _Row(
                label: tr('Vault Mode'),
                info: tr('Treat every transaction as part of your savings vault: income is added to savings and '
                    'expenses are drawn from it, so the savings chart tracks your true net flow.'),
                trailing: GestureDetector(
                  onTap: () => app.setVaultMode(!app.vaultMode),
                  child: Semantics(
                    toggled: app.vaultMode,
                    label: tr('Vault Mode'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: app.vaultMode ? p.accentA(0.5) : p.line),
                        color: app.vaultMode ? p.accentA(0.1) : Colors.transparent,
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.vault, size: 14, color: app.vaultMode ? p.accent : p.muted(0.5)),
                        const SizedBox(width: 6),
                        Text(tr('Vault'), style: bodyStyle(p, 12, weight: FontWeight.w500, color: app.vaultMode ? p.accent : p.muted(0.5))),
                        const SizedBox(width: 8),
                        PillSwitch(on: app.vaultMode, width: 26, height: 15),
                      ]),
                    ),
                  ),
                ),
              ),
              _Row(
                label: tr('Theme'),
                trailing: HairlineIconButton(
                  icon: theme.dark ? LucideIcons.sun : LucideIcons.moon,
                  tooltip: theme.dark ? tr('Switch to light mode') : tr('Switch to dark mode'),
                  onPressed: theme.toggle,
                ),
              ),
              const SizedBox(height: 8),
              HairlineButton(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: () async {
                  Navigator.pop(context);
                  await app.signOut();
                },
                child: Row(children: [
                  Icon(LucideIcons.logOut, size: 16, color: p.muted(0.8)),
                  const SizedBox(width: 12),
                  Text(tr('Sign out'), style: bodyStyle(p, 14, color: p.muted(0.8))),
                  const Spacer(),
                  if (email != null)
                    Flexible(child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 12, color: p.muted(0.4)))),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.trailing, this.info});

  final String label;
  final Widget trailing;
  final String? info;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(label, style: bodyStyle(p, 14, color: p.muted(0.7))),
        if (info != null)
          IconButton(
            tooltip: tr('What is {label}?', {'label': label}),
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.info, size: 15, color: p.muted(0.4)),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(label, style: displayStyle(p, 22)),
                content: Text(info!, style: bodyStyle(p, 14, color: p.muted(0.7), height: 1.5)),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Got it'), style: TextStyle(color: p.accent)))],
              ),
            ),
          ),
        const Spacer(),
        trailing,
      ]),
    );
  }
}

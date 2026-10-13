// App shell — the web's layout on a phone: "TODAY" top bar, the page, and the
// bottom nav (Calendar · Dashboard · + · Ledger · More). The center + scans a
// memo; the More sheet holds the other sections (Journal, To-do, To buy, …),
// New entry, Vault Mode, theme and sign out.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../util/format.dart';
import '../widgets/ui.dart';
import 'bills_screen.dart';
import 'boards_screen.dart';
import 'budgets_screen.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import 'entry_sheet.dart';
import 'goals_screen.dart';
import 'journal_screen.dart';
import 'ledger_screen.dart';
import 'memo_sheet.dart';
import 'settings_screen.dart';

enum Section { calendar, dashboard, ledger, journal, todo, shopping, budgets, goals, bills, settings }

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
  (Section.settings, 'Settings', LucideIcons.settings),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  Section _section = Section.calendar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<AppState>().ensureLoaded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back in the foreground: pick up anything changed on the web meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<AppState>().load();
  }

  void go(Section s) => setState(() => _section = s);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pages = {
      Section.calendar: const CalendarScreen(),
      Section.dashboard: DashboardScreen(onCustomize: () => go(Section.settings)),
      Section.ledger: const LedgerScreen(),
      Section.journal: const JournalScreen(),
      Section.todo: const BoardsScreen(kind: BoardKind.todo),
      Section.shopping: const BoardsScreen(kind: BoardKind.shopping),
      Section.budgets: const BudgetsScreen(),
      Section.goals: const GoalsScreen(),
      Section.bills: const BillsScreen(),
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
                Expanded(child: KeyedSubtree(key: ValueKey(_section), child: pages[_section]!)),
              ],
            ),
          ),
          bottomNavigationBar: _BottomNav(
            current: _section,
            onSelect: go,
            onScan: () => openMemoScanner(context),
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
          const Label('Today'),
          const SizedBox(width: 8),
          Text(fmt(DateTime.now(), 'EEE, MMM d, yyyy'), style: monoStyle(p, 14, color: p.muted(0.7))),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.onSelect, required this.onScan, required this.onMore});

  final Section current;
  final ValueChanged<Section> onSelect;
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
              for (final t in [_calendarTab, _dashboardTab]) item(t.$2, t.$3, current == t.$1, () => onSelect(t.$1)),
              // Scan a memo (photo -> one expense per item) — the center action.
              // Same fixed height as the tabs, so the bar never grows.
              Expanded(
                child: SizedBox(
                  height: 60,
                  child: Center(
                    child: Tooltip(
                      message: 'Scan a memo',
                      child: Semantics(
                        button: true,
                        label: 'Scan a memo',
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
              item(_ledgerTab.$2, _ledgerTab.$3, current == _ledgerTab.$1, () => onSelect(_ledgerTab.$1)),
              item('More', LucideIcons.ellipsis, moreActive, onMore),
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
    final email = Supabase.instance.client.auth.currentUser?.email;
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
                const Expanded(child: Label('More')),
                IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: Icon(LucideIcons.x, color: p.muted(0.45))),
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
                      label: s.$2,
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
                                Text(s.$2,
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
                label: 'New entry',
                onPressed: onNewEntry,
              ),
              const SizedBox(height: 10),
              _Row(
                label: 'Vault Mode',
                info: 'Treat every transaction as part of your savings vault: income is added to savings and '
                    'expenses are drawn from it, so the savings chart tracks your true net flow.',
                trailing: GestureDetector(
                  onTap: () => app.setVaultMode(!app.vaultMode),
                  child: Semantics(
                    toggled: app.vaultMode,
                    label: 'Vault Mode',
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
                        Text('Vault', style: bodyStyle(p, 12, weight: FontWeight.w500, color: app.vaultMode ? p.accent : p.muted(0.5))),
                        const SizedBox(width: 8),
                        PillSwitch(on: app.vaultMode, width: 26, height: 15),
                      ]),
                    ),
                  ),
                ),
              ),
              _Row(
                label: 'Theme',
                trailing: HairlineIconButton(
                  icon: theme.dark ? LucideIcons.sun : LucideIcons.moon,
                  tooltip: theme.dark ? 'Switch to light mode' : 'Switch to dark mode',
                  onPressed: theme.toggle,
                ),
              ),
              const SizedBox(height: 8),
              HairlineButton(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: () async {
                  Navigator.pop(context);
                  await Supabase.instance.client.auth.signOut();
                },
                child: Row(children: [
                  Icon(LucideIcons.logOut, size: 16, color: p.muted(0.8)),
                  const SizedBox(width: 12),
                  Text('Sign out', style: bodyStyle(p, 14, color: p.muted(0.8))),
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
            tooltip: 'What is $label?',
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.info, size: 15, color: p.muted(0.4)),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(label, style: displayStyle(p, 22)),
                content: Text(info!, style: bodyStyle(p, 14, color: p.muted(0.7), height: 1.5)),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text('Got it', style: TextStyle(color: p.accent)))],
              ),
            ),
          ),
        const Spacer(),
        trailing,
      ]),
    );
  }
}

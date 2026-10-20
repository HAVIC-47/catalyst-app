// Settings — port of the web's /app/settings: a list of what can be set, each
// opening its own page: language and currency, notifications (each kind on or
// off — both shared with the web through user metadata), dashboard sections (on
// or off, and their order), categories (icons, colors, order), pasting a bKash /
// Nagad message, About the app (version, updates, every feature, what's new) and
// the account (password, erasing the data, deleting the account).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/account.dart';
import '../data/app_state.dart';
import '../data/offline.dart';
import '../models.dart';
import '../services/notifications.dart';
import '../services/updates.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/category_icons.dart';
import '../util/currency.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/limits.dart';
import '../widgets/ui.dart';
import 'about_screen.dart';
import 'sms_review_sheet.dart';

const _swatches = [
  '#C06A33', '#2E8159', '#3D80BC', '#7A4E86', '#B59A3C', '#CB453B',
  '#4C5B82', '#8E5B6E', '#A6694A', '#2F6F6B', '#6E8C46', '#7A746A',
];

/// The settings pages, each opened from its row in Settings (the two category
/// pages from the Categories page).
enum SettingsPage { language, notifications, dashboard, categories, expenseCategories, incomeCategories, sms, account }

/// Open one settings page on top of the app (the dashboard's "Customize" opens
/// the dashboard sections straight away).
Future<void> openSettingsPage(BuildContext context, SettingsPage page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _SettingsPageView(page)));

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final r = app.reminders;
    final remindersOn = r.onCount;
    final hidden = app.dashboardHidden ?? const <String>[];
    final shown = dashboardSections.where((s) => !hidden.contains(s.$1)).length;
    final cur = currencyOf(app.currency);
    final email = isConfigured ? Supabase.instance.client.auth.currentUser?.email : null;
    final update = Updates.available.value;
    Widget row(SettingsPage page, IconData icon, String title, String hint) =>
        _HubRow(icon: icon, title: title, hint: hint, onTap: () => openSettingsPage(context, page));
    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(kicker: tr('Settings'), title: tr('Make it'), accent: tr('yours.')),
          _HubCard(children: [
            row(SettingsPage.language, LucideIcons.languages, tr('Language & currency'),
                '${app.lang == 'bn' ? 'বাংলা' : tr('English')} · ${cur.symbol.trim()} ${tr(cur.name)}'),
            row(
              SettingsPage.notifications,
              LucideIcons.bellRing,
              tr('Notifications'),
              remindersOn == 0
                  ? tr('All off')
                  : r.checkin
                      ? tr('{n} of {total} on · check-in at {time}', {'n': remindersOn, 'total': ReminderPrefs.kinds, 'time': _time(context, r.checkinTime)})
                      : tr('{n} of {total} on', {'n': remindersOn, 'total': ReminderPrefs.kinds}),
            ),
            row(SettingsPage.dashboard, LucideIcons.layoutGrid, tr('Dashboard'),
                tr('{n} of {total} sections shown', {'n': shown, 'total': dashboardSections.length})),
            row(
              SettingsPage.categories,
              LucideIcons.tags,
              tr('Categories'),
              tr('{expense} expense · {income} income', {
                'expense': app.categories.where((c) => c.kind == Kind.expense).length,
                'income': app.categories.where((c) => c.kind == Kind.income).length,
              }),
            ),
            row(SettingsPage.sms, LucideIcons.messageSquareText, tr('bKash & Nagad'), tr('Add an entry from a payment message')),
          ]),
          const SizedBox(height: 14),
          _HubCard(children: [
            _HubRow(
              icon: LucideIcons.info,
              title: tr('About the app'),
              hint: update != null
                  ? tr('Version {version} is out.', {'version': update.version})
                  : tr("Version, updates, every feature and what's new"),
              accentHint: update != null,
              onTap: () => openAbout(context),
            ),
            row(SettingsPage.account, LucideIcons.userRound, tr('Account'), email ?? tr('Your email, erasing your data and deleting the account')),
          ]),
        ],
      ),
    );
  }

  static String _time(BuildContext context, String hhmm) {
    final parts = hhmm.split(':');
    final time = TimeOfDay(hour: int.tryParse(parts[0]) ?? 21, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
  }
}

/// A card of settings rows, with hairlines between them.
class _HubCard extends StatelessWidget {
  const _HubCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CardBox(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
          child,
        ],
      ]),
    );
  }
}

/// One row in Settings: what it is, its current setting, and a way in.
class _HubRow extends StatelessWidget {
  const _HubRow({required this.icon, required this.title, required this.hint, required this.onTap, this.accentHint = false});

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;
  final bool accentHint;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: p.accentA(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: p.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: bodyStyle(p, 15, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bodyStyle(p, 12.5, color: accentHint ? p.accent : p.muted(0.5)),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(LucideIcons.chevronRight, size: 18, color: p.muted(0.35)),
        ]),
      ),
    );
  }
}

/// One settings page: a back button and its title, then its cards. Built from
/// slivers: the dashboard and category pages hold lists you can drag into order,
/// and dragging a row to the edge of the screen scrolls the page.
class _SettingsPageView extends StatelessWidget {
  const _SettingsPageView(this.page);

  final SettingsPage page;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    Widget boxes(List<Widget> children) => SliverList.list(children: children);
    final (title, slivers) = switch (page) {
      SettingsPage.language => (tr('Language & currency'), [boxes(const [_LanguageSection(), _CurrencySection()])]),
      SettingsPage.notifications => (tr('Notifications'), [boxes(const [_RemindersSection(), _AlertsSection()])]),
      SettingsPage.dashboard => (tr('Dashboard'), const <Widget>[_DashboardSections()]),
      SettingsPage.categories => (
          tr('Categories'),
          [
            boxes([
              Text(
                tr('Add, rename, recolor, or remove categories for expenses and income — give each an icon and drag them into the order you want. Deleting one keeps past transactions labeled.'),
                style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
              ),
              const SizedBox(height: 14),
              _HubCard(children: [
                for (final (kind, page, icon, title) in [
                  (Kind.expense, SettingsPage.expenseCategories, LucideIcons.arrowUpRight, tr('Expense categories')),
                  (Kind.income, SettingsPage.incomeCategories, LucideIcons.arrowDownLeft, tr('Income categories')),
                ])
                  _HubRow(
                    icon: icon,
                    title: title,
                    hint: trn(app.categories.where((c) => c.kind == kind).length, '{n} category', '{n} categories'),
                    onTap: () => openSettingsPage(context, page),
                  ),
              ]),
            ]),
          ],
        ),
      SettingsPage.expenseCategories || SettingsPage.incomeCategories => (
          page == SettingsPage.expenseCategories ? tr('Expense categories') : tr('Income categories'),
          <Widget>[
            _CategorySection(kind: page == SettingsPage.expenseCategories ? Kind.expense : Kind.income),
            if (app.categories.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(tr('Loading categories…'), style: monoStyle(p, 12, color: p.muted(0.3))),
                ),
              ),
          ],
        ),
      SettingsPage.sms => (tr('bKash & Nagad'), [boxes(const [_SmsSection()])]),
      SettingsPage.account => (tr('Account'), [boxes(const [_AccountSection()])]),
    };
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            sliver: SliverMainAxisGroup(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(children: [
                    HairlineIconButton(icon: LucideIcons.arrowLeft, tooltip: tr('Back'), onPressed: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: displayStyle(p, 24)),
                    ),
                  ]),
                ),
              ),
              ...slivers,
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A card (like CardBox) around a header and a sliver list, so the list is part
/// of the page's own scrolling.
class _CardSliver extends StatelessWidget {
  const _CardSliver({required this.header, required this.list});

  final Widget header;
  final Widget list;

  @override
  Widget build(BuildContext context) => DecoratedSliver(
        decoration: cardDecoration(Palette.of(context)),
        sliver: SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverMainAxisGroup(slivers: [SliverToBoxAdapter(child: header), list]),
        ),
      );
}

/// [ids] with the one at [from] moved to [to].
List<String> _moved(List<String> ids, int from, int to) {
  final out = [...ids];
  out.insert(to, out.removeAt(from));
  return out;
}

/// The row being dragged, lifted a little (inside a Material, so its fields still
/// work while it floats above the page).
Widget _lift(Widget child, int index, Animation<double> animation) => AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.02 * Curves.easeOut.transform(animation.value),
        child: Material(type: MaterialType.transparency, child: child),
      ),
      child: child,
    );

/// A row that can be put in order: dragged by its handle, or moved one place at
/// a time with the arrows (the way for screen readers, too).
class _SortRow extends StatelessWidget {
  const _SortRow({
    super.key,
    required this.index,
    required this.count,
    required this.name,
    required this.onMove,
    required this.child,
    this.below,
    this.dim = false,
  });

  final int index;
  final int count;
  final String name; // for the arrows' labels
  final ValueChanged<int> onMove; // to this place
  final Widget child;
  final Widget? below; // full width under the row (a category's icon picker)
  final bool dim; // a hidden dashboard section

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget arrow(IconData icon, String label, int? to) => Tooltip(
          message: label,
          child: InkWell(
            onTap: to == null ? null : () => onMove(to),
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(width: 34, height: 26, child: Icon(icon, size: 16, color: to == null ? p.muted(0.15) : p.muted(0.55))),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dim ? p.inkA(0.06) : p.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ReorderableDragStartListener(
              index: index,
              child: ExcludeSemantics(
                child: SizedBox(width: 30, height: 52, child: Icon(LucideIcons.gripVertical, size: 16, color: p.muted(0.35))),
              ),
            ),
            Expanded(child: child),
            Column(mainAxisSize: MainAxisSize.min, children: [
              arrow(LucideIcons.chevronUp, tr('Move {name} up', {'name': name}), index > 0 ? index - 1 : null),
              arrow(LucideIcons.chevronDown, tr('Move {name} down', {'name': name}), index < count - 1 ? index + 1 : null),
            ]),
          ]),
          ?below,
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- language
class _LanguageSection extends StatelessWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Language'), tr('& words')),
        const SizedBox(height: 4),
        Text(
          tr('The app, the web and your AI summaries follow this.'),
          style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: SegTabs<String>(
            options: const ['en', 'bn'],
            value: app.lang,
            label: (l) => l == 'bn' ? 'বাংলা' : tr('English'),
            onChanged: (l) => app.setLang(l),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- currency
class _CurrencySection extends StatelessWidget {
  const _CurrencySection();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Currency'), tr('& money')),
        const SizedBox(height: 4),
        Text(
          tr("How amounts are written everywhere — here and on the web. It doesn't convert anything: your entries keep their numbers."),
          style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
        ),
        const SizedBox(height: 12),
        AppDropdown(
          value: app.currency,
          items: [for (final c in currencies) c.code],
          labelOf: (code) {
            final c = currencyOf(code);
            return '${c.symbol.trim()} · ${tr(c.name)} (${c.code})';
          },
          onChanged: app.setCurrencyCode,
        ),
        const SizedBox(height: 8),
        Text(tr('Example: {amount}', {'amount': formatCurrency(125000.5)}), style: monoStyle(p, 12, color: p.muted(0.4))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- reminders
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.on, required this.onChanged, required this.label, required this.hint});

  final bool on;
  final ValueChanged<bool> onChanged;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        toggled: on,
        label: label,
        child: Material(
          color: p.inkA(0.02),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(!on),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: bodyStyle(p, 14, color: p.muted(0.85))),
                      Text(hint, style: bodyStyle(p, 11.5, color: p.muted(0.4))),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  PillSwitch(on: on),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemindersSection extends StatefulWidget {
  const _RemindersSection();

  @override
  State<_RemindersSection> createState() => _RemindersSectionState();
}

class _RemindersSectionState extends State<_RemindersSection> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final on = await Notifications.enabled();
    if (mounted) setState(() => _allowed = on);
  }

  Future<void> _allow() async {
    final granted = await Notifications.request();
    if (!granted) await Notifications.openSettings();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final r = app.reminders;
    final parts = r.checkinTime.split(':');
    final time = TimeOfDay(hour: int.tryParse(parts[0]) ?? 21, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Reminders'), tr('that help')),
        const SizedBox(height: 4),
        Text(
          tr("Turn off anything you don't want. Notifications on this phone, and in the web app — shared with the web, so you set them once."),
          style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
        ),
        const SizedBox(height: 12),
        _SwitchRow(
          on: r.checkin,
          onChanged: (v) => app.setReminders(r.copyWith(checkin: v)),
          label: tr('Evening check-in'),
          hint: tr('"How was today?" if no mood is logged'),
        ),
        Opacity(
          opacity: r.checkin ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text(tr('Check-in time'), style: bodyStyle(p, 14, color: p.muted(0.7)))),
              HairlineButton(
                height: 40,
                onPressed: !r.checkin
                    ? null
                    : () async {
                        final picked = await showTimePicker(context: context, initialTime: time);
                        if (picked == null) return;
                        app.setReminders(r.copyWith(checkinTime: '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'));
                      },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(time.format(context), style: bodyStyle(p, 14)),
                  const SizedBox(width: 10),
                  Icon(LucideIcons.clock, size: 15, color: p.muted(0.6)),
                ]),
              ),
            ]),
          ),
        ),
        _SwitchRow(
          on: r.bills,
          onChanged: (v) => app.setReminders(r.copyWith(bills: v)),
          label: tr('Bills'),
          hint: tr("The day before a bill is due"),
        ),
        _SwitchRow(
          on: r.budgets,
          onChanged: (v) => app.setReminders(r.copyWith(budgets: v)),
          label: tr('Budgets'),
          hint: tr('When a category reaches 80% and 100%'),
        ),
        _SwitchRow(
          on: r.dhar,
          onChanged: (v) => app.setReminders(r.copyWith(dhar: v)),
          label: tr('Dhar'),
          hint: tr('The day before money lent or borrowed is due back'),
        ),
        if (Notifications.supported) ...[
          Divider(color: p.line, height: 20),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Notifications on this phone'), style: bodyStyle(p, 14, color: p.muted(0.7))),
                Text(
                  _allowed == null
                      ? '…'
                      : _allowed!
                          ? tr('Allowed — reminders will show here.')
                          : tr('Not allowed yet — reminders only show inside the app.'),
                  style: bodyStyle(p, 11.5, color: p.muted(0.4)),
                ),
              ]),
            ),
            if (_allowed == false) PrimaryButton(label: tr('Allow'), icon: LucideIcons.bellRing, height: 40, onPressed: _allow),
          ]),
        ],
      ]),
    );
  }
}

/// The alerts: a recurring entry added, mood & money, streaks, challenges, app updates.
class _AlertsSection extends StatelessWidget {
  const _AlertsSection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final r = app.reminders;
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Alerts'), tr('when it happens')),
        const SizedBox(height: 12),
        _SwitchRow(
          on: r.recurring,
          onChanged: (v) => app.setReminders(r.copyWith(recurring: v)),
          label: tr('Recurring entries'),
          hint: tr('When a salary, rent or subscription is added by itself'),
        ),
        _SwitchRow(
          on: r.moodSpend,
          onChanged: (v) => app.setReminders(r.copyWith(moodSpend: v)),
          label: tr('Mood & money'),
          hint: tr('When a low day comes with a lot of spending'),
        ),
        _SwitchRow(
          on: r.streaks,
          onChanged: (v) => app.setReminders(r.copyWith(streaks: v)),
          label: tr('Streaks'),
          hint: tr('Milestones, and when a streak is about to end'),
        ),
        _SwitchRow(
          on: r.challenges,
          onChanged: (v) => app.setReminders(r.copyWith(challenges: v)),
          label: tr('Challenges'),
          hint: tr('Won, missed, or on its last day'),
        ),
        _SwitchRow(
          on: r.updates,
          onChanged: (v) => app.setReminders(r.copyWith(updates: v)),
          label: tr('App updates'),
          hint: tr('A pop-up when a new version is out (the banner stays)'),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- bKash / Nagad messages
/// A bKash / Nagad message becomes an entry when it's shared to the app (from the
/// Messages app) or pasted here. No SMS permission: nothing else is read.
class _SmsSection extends StatelessWidget {
  const _SmsSection();

  Future<void> _paste(BuildContext context) async {
    final copied = await Clipboard.getData(Clipboard.kTextPlain);
    if (context.mounted) await reviewSharedText(context, copied?.text ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('bKash & Nagad'), tr('messages')),
        const SizedBox(height: 4),
        Text(
          tr('Turn a bKash or Nagad confirmation into an entry: in your Messages app, press and hold the message, tap '
              'Share, then Catalyst. Or copy it and tap Paste below. It\'s read on this phone only, and you check it before '
              'anything is saved.'),
          style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: HairlineButton(
            onPressed: () => _paste(context),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.clipboardPaste, size: 15, color: p.muted(0.7)),
              const SizedBox(width: 8),
              Flexible(child: Text(tr('Paste a message'), style: bodyStyle(p, 13.5, color: p.muted(0.8)))),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- account
/// Change the password: the current one, then the new one twice. Google-only
/// accounts have no password to change — they're pointed to "Forgot password?".
class _PasswordChange extends StatefulWidget {
  const _PasswordChange();

  @override
  State<_PasswordChange> createState() => _PasswordChangeState();
}

class _PasswordChangeState extends State<_PasswordChange> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  void _close() => setState(() {
        _open = false;
        _error = null;
        _current.clear();
        _next.clear();
        _again.clear();
      });

  Future<void> _save() async {
    if (_busy) return;
    final String? problem = _current.text.isEmpty
        ? tr('Type your current password.')
        : _next.text.length < 8
            ? tr('Use at least 8 characters.')
            : _next.text != _again.text
                ? tr("The two passwords don't match.")
                : null;
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await changePassword(current: _current.text, next: _next.text);
      if (!mounted) return;
      _close();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Password changed.'))));
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (isConfigured && !accountHasPassword()) {
      return Text(
        tr('You sign in with Google, so there\'s no password to change. To add one, sign out and use "Forgot password?" on the login screen.'),
        style: bodyStyle(p, 12.5, color: p.muted(0.5), height: 1.45),
      );
    }
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: HairlineButton(
          height: 40,
          onPressed: () => setState(() => _open = true),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.keyRound, size: 15, color: p.muted(0.7)),
            const SizedBox(width: 8),
            Text(tr('Change password'), style: bodyStyle(p, 13.5, color: p.muted(0.8))),
          ]),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Change password'), style: bodyStyle(p, 14, weight: FontWeight.w600)),
        const SizedBox(height: 10),
        PasswordField(controller: _current, hint: tr('Current password'), autofillHints: const [AutofillHints.password]),
        const SizedBox(height: 10),
        PasswordField(controller: _next, hint: tr('New password (min 8)'), autofillHints: const [AutofillHints.newPassword]),
        const SizedBox(height: 10),
        PasswordField(controller: _again, hint: tr('Type it again'), onSubmitted: (_) => _save()),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: bodyStyle(p, 12.5, color: p.expense, height: 1.4)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          TextButton(onPressed: _busy ? null : _close, child: Text(tr('Cancel'), style: bodyStyle(p, 13.5, color: p.muted(0.6)))),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: PrimaryButton(label: tr('Change password'), height: 42, busy: _busy, onPressed: _save),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Erase my data: every entry goes, the account stays (login and settings) — for
/// starting over, or handing the account back clean after a try-out.
class _EraseData extends StatefulWidget {
  const _EraseData();

  @override
  State<_EraseData> createState() => _EraseDataState();
}

class _EraseDataState extends State<_EraseData> {
  final _confirm = TextEditingController();
  bool _open = false;
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _typed => _confirm.text.trim() == 'ERASE';

  Future<void> _erase() async {
    if (!_typed || _busy) return;
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await eraseData();
      await app.afterErase();
      if (!mounted) return;
      setState(() {
        _open = false;
        _done = true;
        _confirm.clear();
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accentA(0.3)),
        color: p.accentA(0.04),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Erase my data'), style: bodyStyle(p, 14, color: p.muted(0.8))),
        const SizedBox(height: 2),
        Text(
          _done
              ? tr('Done — everything you recorded is gone. Your account and settings are still here.')
              : tr("Deletes every entry, mood, wallet, bill, goal, board and journal note, but keeps your account, password and settings — for starting fresh. This can't be undone."),
          style: bodyStyle(p, 11.5, color: _done ? p.income : p.muted(0.45), height: 1.4),
        ),
        const SizedBox(height: 10),
        if (!_open)
          Align(
            alignment: Alignment.centerLeft,
            child: HairlineButton(
              height: 40,
              borderColor: p.accentA(0.5),
              onPressed: () => setState(() {
                _done = false;
                _open = true;
              }),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.eraser, size: 15, color: p.accent),
                const SizedBox(width: 8),
                Text(tr('Erase…'), style: bodyStyle(p, 13.5, weight: FontWeight.w600, color: p.accent)),
              ]),
            ),
          )
        else ...[
          TextField(
            controller: _confirm,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: monoStyle(p, 14),
            decoration: InputDecoration(hintText: tr('Type ERASE')),
          ),
          const SizedBox(height: 10),
          Row(children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _open = false;
                        _confirm.clear();
                      }),
              child: Text(tr('Cancel'), style: bodyStyle(p, 13.5, color: p.muted(0.6))),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: PrimaryButton(label: tr('Erase my data'), height: 42, busy: _busy, onPressed: _typed ? _erase : null),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _AccountSection extends StatefulWidget {
  const _AccountSection();

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  final _confirm = TextEditingController();
  bool _open = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_confirm.text.trim() != 'DELETE' || _busy) return;
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await deleteAccount();
      await Outbox.instance.clear();
      await app.signOut();
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final email = isConfigured ? Supabase.instance.client.auth.currentUser?.email : null;
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Your'), tr('account')),
        const SizedBox(height: 4),
        Text(
          tr('Signed in as {email}.', {'email': email ?? '…'}),
          style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
        ),
        const SizedBox(height: 14),
        const _PasswordChange(),
        const SizedBox(height: 14),
        const _EraseData(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.expense.withValues(alpha: 0.3)),
            color: p.expense.withValues(alpha: 0.04),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Delete account'), style: bodyStyle(p, 14, color: p.muted(0.8))),
            const SizedBox(height: 2),
            Text(
              tr("Permanently removes your account and everything in it — entries, moods, boards, wallets, dhar. This can't be undone."),
              style: bodyStyle(p, 11.5, color: p.muted(0.45), height: 1.4),
            ),
            const SizedBox(height: 10),
            if (!_open)
              Align(
                alignment: Alignment.centerLeft,
                child: HairlineButton(
                  height: 40,
                  borderColor: p.expense.withValues(alpha: 0.4),
                  onPressed: () => setState(() => _open = true),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.trash2, size: 15, color: p.expense),
                    const SizedBox(width: 8),
                    Text(tr('Delete…'), style: bodyStyle(p, 13.5, weight: FontWeight.w600, color: p.expense)),
                  ]),
                ),
              )
            else ...[
              TextField(
                controller: _confirm,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                style: monoStyle(p, 14),
                decoration: InputDecoration(hintText: tr('Type DELETE')),
              ),
              const SizedBox(height: 10),
              Row(children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _open = false;
                            _confirm.clear();
                          }),
                  child: Text(tr('Cancel'), style: bodyStyle(p, 13.5, color: p.muted(0.6))),
                ),
                const Spacer(),
                Opacity(
                  opacity: _confirm.text.trim() == 'DELETE' ? 1 : 0.4,
                  child: Material(
                    color: p.expense,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _confirm.text.trim() == 'DELETE' && !_busy ? _delete : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_busy) ...[
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white)),
                            const SizedBox(width: 8),
                          ],
                          Text(tr('Delete my account'), style: bodyStyle(p, 13.5, weight: FontWeight.w600, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Each dashboard section on or off, and in the order you want them.
class _DashboardSections extends StatelessWidget {
  const _DashboardSections();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final hidden = app.dashboardHidden ?? const <String>[];
    final order = app.dashboardOrder;
    final byId = {for (final s in dashboardSections) s.$1: s};
    final rows = [for (final id in order) byId[id]!];
    final defaultOrder = [for (final s in dashboardSections) s.$1];
    final isDefault = order.join(',') == defaultOrder.join(',');
    return _CardSliver(
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: CardTitle(tr('Dashboard'), tr('sections'))),
          Label(digits('${dashboardSections.length - hidden.length} / ${dashboardSections.length}')),
        ]),
        const SizedBox(height: 4),
        Text(
          tr('Choose what the dashboard shows, and drag the sections into the order you want — the ones you care about most at the top. Hidden sections keep all their data.'),
          style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
        ),
        if (!isDefault || hidden.isNotEmpty)
          Wrap(spacing: 4, children: [
            if (!isDefault)
              TextButton(
                onPressed: () => app.setDashboardOrder(defaultOrder),
                child: Text(tr('DEFAULT ORDER'), style: monoStyle(p, 11, color: p.accentA(0.85), letterSpacing: 1.4)),
              ),
            if (hidden.isNotEmpty)
              TextButton(
                onPressed: () => app.setDashboardHidden([]),
                child: Text(tr('SHOW ALL'), style: monoStyle(p, 11, color: p.accentA(0.85), letterSpacing: 1.4)),
              ),
          ]),
        const SizedBox(height: 12),
      ]),
      list: SliverReorderableList(
        itemCount: rows.length,
        onReorderStart: (_) => HapticFeedback.selectionClick(),
        onReorderItem: (from, to) => app.setDashboardOrder(_moved(order, from, to)),
        proxyDecorator: _lift,
        itemBuilder: (context, i) {
          final s = rows[i];
          final on = !hidden.contains(s.$1);
          return _SortRow(
            key: ValueKey(s.$1),
            index: i,
            count: rows.length,
            name: tr(s.$2),
            dim: !on,
            onMove: (to) => app.setDashboardOrder(_moved(order, i, to)),
            child: Semantics(
              toggled: on,
              label: tr(s.$2),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: app.dashboardHidden == null
                    ? null
                    : () => app.setDashboardHidden(on ? [...hidden, s.$1] : hidden.where((id) => id != s.$1).toList()),
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 9, 8, 9),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr(s.$2), style: bodyStyle(p, 14, color: on ? p.muted(0.85) : p.muted(0.45))),
                          Text(tr(s.$3), style: bodyStyle(p, 11.5, color: p.muted(0.35))),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      PillSwitch(on: on),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategorySection extends StatefulWidget {
  const _CategorySection({required this.kind});
  final Kind kind;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  final _name = TextEditingController();
  String _color = _swatches.first;
  String? _icon; // null = picked from the name
  String? _picking; // the category whose icon picker is open, or 'new'
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Icons need the 1.6 database update (categories.icon); say so instead of a raw error.
  void _failed(Object e) {
    if (!mounted) return;
    if ('$e'.toLowerCase().contains('icon')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Category icons need the database update — run db/supabase.sql in Supabase.'))));
    } else {
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final list = app.categories.where((c) => c.kind == widget.kind).toList();
    final kindName = widget.kind == Kind.expense ? tr('Expense') : tr('Income');
    final newName = _name.text.trim().isEmpty ? '—' : _name.text.trim();

    Future<void> add() async {
      final n = _name.text.trim();
      if (n.isEmpty || _busy) return;
      setState(() => _busy = true);
      try {
        // First in its list: below the lowest sort number of its kind.
        final first = list.isEmpty ? 0 : list.map((c) => c.sort).reduce((a, b) => a < b ? a : b) - 1;
        await app.createCategory(name: n, kind: widget.kind, color: _color, sort: first, icon: _icon);
        _name.clear();
        _icon = null;
        _picking = null;
      } catch (e) {
        _failed(e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    Future<void> restoreDefaults() async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        final defaults = widget.kind == Kind.expense ? defaultExpenseCategories : defaultIncomeCategories;
        final have = {for (final c in list) c.name.toLowerCase()};
        var i = list.isEmpty ? 0 : list.map((c) => c.sort).reduce((a, b) => a > b ? a : b) + 1;
        for (final d in defaults) {
          if (have.contains(d.$1.toLowerCase())) continue;
          await app.createCategory(name: d.$1, kind: widget.kind, color: d.$2, sort: i++);
        }
      } catch (e) {
        _failed(e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    void reorder(int from, int to) => app.reorderCategories(_moved([for (final c in list) c.id], from, to)).catchError(_failed);

    return _CardSliver(
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(kindName, style: displayStyle(p, 20))),
          TextButton(
            onPressed: _busy ? null : restoreDefaults,
            child: Text(tr('RESTORE DEFAULTS'), style: monoStyle(p, 10.5, color: p.accentA(0.85), letterSpacing: 1.3)),
          ),
          Label('${list.length}'),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _BadgeButton(
                name: newName,
                icon: _icon,
                color: hexColor(_color),
                open: _picking == 'new',
                tooltip: tr('Choose an icon'),
                onTap: () => setState(() => _picking = _picking == 'new' ? null : 'new'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _name,
                  inputFormatters: maxChars(Limits.name),
                  onSubmitted: (_) => add(),
                  decoration: InputDecoration(hintText: tr('New {name} category', {'name': tr(widget.kind.name)})),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: PrimaryButton(label: '', semanticLabel: tr('Add category'), icon: LucideIcons.plus, height: 44, busy: _busy, onPressed: _name.text.trim().isEmpty ? null : add),
              ),
            ]),
            if (_picking == 'new') ...[
              const SizedBox(height: 12),
              _IconPicker(
                name: newName,
                value: _icon,
                color: hexColor(_color),
                onPick: (v) => setState(() {
                  _icon = v;
                  _picking = null;
                }),
              ),
            ],
            const SizedBox(height: 12),
            _Swatches(value: _color, onPick: (s) => setState(() => _color = s)),
          ]),
        ),
        const SizedBox(height: 12),
        Text(
          tr('Drag to put them in the order you want — the entry screen lists them the same way.'),
          style: bodyStyle(p, 11.5, color: p.muted(0.45), height: 1.4),
        ),
        const SizedBox(height: 8),
      ]),
      list: SliverReorderableList(
        itemCount: list.length,
        onReorderStart: (_) => HapticFeedback.selectionClick(),
        onReorderItem: reorder,
        proxyDecorator: _lift,
        itemBuilder: (context, i) {
          final c = list[i];
          return _CategoryRow(
            key: ValueKey(c.id),
            category: c,
            index: i,
            count: list.length,
            picking: _picking == c.id,
            onPicking: () => setState(() => _picking = _picking == c.id ? null : c.id),
            onMove: (to) => reorder(i, to),
            onFailed: _failed,
          );
        },
      ),
    );
  }
}

class _CategoryRow extends StatefulWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.index,
    required this.count,
    required this.picking,
    required this.onPicking,
    required this.onMove,
    required this.onFailed,
  });

  final Category category;
  final int index;
  final int count;
  final bool picking; // its icon and color picker is open
  final VoidCallback onPicking;
  final ValueChanged<int> onMove;
  final void Function(Object error) onFailed;

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  late final _ctrl = TextEditingController(text: widget.category.name);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _rename();
    });
  }

  @override
  void didUpdateWidget(_CategoryRow old) {
    super.didUpdateWidget(old);
    // Renamed elsewhere (or put back after a failed save): show it, unless it's being typed.
    if (old.category.name != widget.category.name && !_focus.hasFocus) _ctrl.text = widget.category.name;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty || v == widget.category.name) return;
    try {
      await context.read<AppState>().editCategory(widget.category.id, name: v);
    } catch (e) {
      widget.onFailed(e);
    }
  }

  Future<void> _edit({String? color, String? icon, bool clearIcon = false}) async {
    try {
      await context.read<AppState>().editCategory(widget.category.id, color: color, icon: icon, clearIcon: clearIcon);
    } catch (e) {
      widget.onFailed(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.read<AppState>();
    final c = widget.category;
    return _SortRow(
      index: widget.index,
      count: widget.count,
      name: tr(c.name),
      onMove: widget.onMove,
      below: widget.picking ? _picker(p, c) : null,
      child: Row(children: [
        _BadgeButton(
          name: c.name,
          icon: c.icon,
          color: hexColor(c.color),
          open: widget.picking,
          tooltip: tr('Change the icon of {name}', {'name': tr(c.name)}),
          onTap: widget.onPicking,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            inputFormatters: maxChars(Limits.name),
            onSubmitted: (_) => _rename(),
            style: bodyStyle(p, 14, color: p.muted(0.85)),
            decoration: const InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        TrashButton(
          tooltip: tr('Delete {name}', {'name': c.name}),
          onPressed: () async {
            if (!await confirm(context, tr('Delete "{name}"?', {'name': c.name}))) return;
            try {
              await app.removeCategory(c.id);
            } catch (e) {
              widget.onFailed(e);
            }
          },
        ),
      ]),
    );
  }

  /// Under the row: its icon, then its color.
  Widget _picker(Palette p, Category c) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Divider(color: p.line, height: 1),
          const SizedBox(height: 12),
          _IconPicker(
            name: c.name,
            value: c.icon,
            color: hexColor(c.color),
            onPick: (v) {
              widget.onPicking();
              _edit(icon: v, clearIcon: v == null);
            },
          ),
          const SizedBox(height: 12),
          _Swatches(value: c.color.toUpperCase(), onPick: (s) => _edit(color: s)),
        ]),
      );
}

/// A category's badge as a button: opens its icon (and color) picker.
class _BadgeButton extends StatelessWidget {
  const _BadgeButton({required this.name, required this.icon, required this.color, required this.open, required this.tooltip, required this.onTap});

  final String name;
  final String? icon;
  final Color color;
  final bool open;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: open ? p.accentA(0.6) : Colors.transparent, width: 1.5),
          ),
          child: CategoryBadge(name: name, icon: icon, color: color, size: 36),
        ),
      ),
    );
  }
}

/// Every icon a category can have, plus Auto (picked from its name).
class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.name, required this.value, required this.color, required this.onPick});

  final String name;
  final String? value; // null = Auto
  final Color color; // the category's, as stored
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final auto = categoryIconName(name);
    final tint = p.tintText(p.vivid(color));
    Widget cell({required bool on, required bool suggested, required String label, required VoidCallback onTap, required Widget child}) => Tooltip(
          message: label,
          child: Semantics(
            selected: on,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(9),
              child: Container(
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: on ? p.accentA(0.1) : null,
                  border: Border.all(color: on ? p.accentA(0.6) : (suggested ? p.accentA(0.35) : p.line)),
                ),
                child: child,
              ),
            ),
          ),
        );
    final cells = [
      cell(
        on: value == null,
        suggested: false,
        label: tr('Auto — from the name'),
        onTap: () => onPick(null),
        child: Text(tr('Auto'), maxLines: 1, style: monoStyle(p, 9.5, weight: FontWeight.w600, color: value == null ? p.ink : p.muted(0.5))),
      ),
      for (final e in categoryIcons.entries)
        cell(
          on: value == e.key,
          suggested: value == null && e.key == auto,
          label: e.key.replaceAll('-', ' '),
          onTap: () => onPick(e.key),
          child: Icon(e.value, size: 19, color: tint),
        ),
    ];
    return LayoutBuilder(builder: (context, box) {
      const gap = 6.0;
      final perRow = ((box.maxWidth + gap) / 48).floor().clamp(6, 10);
      final w = ((box.maxWidth - gap * (perRow - 1)) / perRow).floorToDouble();
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in cells) SizedBox(width: w, child: c)]);
    });
  }
}

/// The category colors to pick from.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.value, required this.onPick});

  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final s in _swatches)
        Semantics(
          button: true,
          selected: value == s,
          label: tr('Pick color {s}', {'s': s}),
          child: InkWell(
            onTap: () => onPick(s),
            customBorder: const CircleBorder(),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: p.vivid(hexColor(s)), shape: BoxShape.circle),
              child: value == s ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null,
            ),
          ),
        ),
    ]);
  }
}

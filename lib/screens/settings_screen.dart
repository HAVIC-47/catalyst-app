// Settings — port of the web's /app/settings: language, currency and reminders
// (shared with the web through user metadata), bKash / Nagad SMS capture (this
// phone only), dashboard sections, categories, the app's version and updates,
// About the app (every feature, what's new) and the account (delete).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/account.dart';
import '../data/app_state.dart';
import '../data/offline.dart';
import '../models.dart';
import '../services/notifications.dart';
import '../services/sms.dart';
import '../services/updates.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(kicker: tr('Settings'), title: tr('Make it'), accent: tr('yours.')),
          const _LanguageSection(),
          const _CurrencySection(),
          const _RemindersSection(),
          const _SmsSection(),
          const _DashboardSections(),
          const SizedBox(height: 28),
          CardTitle(tr('Your'), tr('categories.'), size: 24),
          const SizedBox(height: 4),
          Text(
            tr('Add, rename, recolor, or remove categories for expenses and income. Deleting one keeps past transactions labeled.'),
            style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
          ),
          const SizedBox(height: 14),
          const _CategorySection(kind: Kind.expense),
          const SizedBox(height: 14),
          const _CategorySection(kind: Kind.income),
          if (app.categories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr('Loading categories…'), style: monoStyle(p, 12, color: p.muted(0.3))),
            ),
          const SizedBox(height: 28),
          const _AppSection(),
          const _AccountSection(),
        ],
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
          tr('Notifications on this phone, and in the web app. Shared with the web, so you set them once.'),
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

// ---------------------------------------------------------------- bKash / Nagad SMS
class _SmsSection extends StatefulWidget {
  const _SmsSection();

  @override
  State<_SmsSection> createState() => _SmsSectionState();
}

class _SmsSectionState extends State<_SmsSection> {
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final on = await SmsCapture.isOn() && await SmsCapture.hasPermission();
    if (mounted) setState(() => _on = on);
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_on ?? false) {
        await SmsCapture.disable();
      } else if (!await SmsCapture.enable() && mounted) {
        showError(context, tr('Without permission to read SMS this stays off. You can allow it any time.'));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      await _read();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final found = await SmsCapture.pending();
    if (!mounted) return;
    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('No new bKash or Nagad messages.'))));
    } else {
      await openSmsReview(context, found);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (!Notifications.supported) return const SizedBox.shrink();
    final on = _on ?? false;
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('bKash & Nagad'), tr('messages')),
        const SizedBox(height: 4),
        Text(
          tr('Suggest entries from your bKash and Nagad confirmation SMS. Messages are read and understood on this phone '
              'only — never uploaded. You review each one, and only what you add is saved.'),
          style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
        ),
        const SizedBox(height: 12),
        _SwitchRow(
          on: on,
          onChanged: (_) => _toggle(),
          label: tr('Read bKash / Nagad SMS'),
          hint: on ? tr('On — new messages show up for review when you open the app.') : tr('Off'),
        ),
        if (on)
          Align(
            alignment: Alignment.centerLeft,
            child: HairlineButton(
              onPressed: _scan,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.scanSearch, size: 15, color: p.muted(0.7)),
                const SizedBox(width: 8),
                Text(tr('Check messages now'), style: bodyStyle(p, 13.5, color: p.muted(0.8))),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- app version
class _AppSection extends StatefulWidget {
  const _AppSection();

  @override
  State<_AppSection> createState() => _AppSectionState();
}

class _AppSectionState extends State<_AppSection> {
  bool _checking = false;
  UpdateInfo? _found;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _found = Updates.available.value;
    if (Updates.current.isEmpty) Updates.check().then((_) => mounted ? setState(() {}) : null);
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final u = await Updates.check(force: true);
    if (mounted) {
      setState(() {
        _checking = false;
        _checked = true;
        _found = u;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final found = _found;
    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('The'), tr('app')),
        const SizedBox(height: 4),
        Text(
          Updates.current.isEmpty ? tr('Catalyst') : tr('Catalyst {version} for Android', {'version': Updates.current}),
          style: bodyStyle(p, 13.5, color: p.muted(0.55)),
        ),
        if (found != null) ...[
          const SizedBox(height: 4),
          Text(tr('Version {version} is out.', {'version': found.version}), style: bodyStyle(p, 13.5, color: p.accent)),
        ] else if (_checked) ...[
          const SizedBox(height: 4),
          Text(tr("You're on the latest version."), style: bodyStyle(p, 13, color: p.muted(0.45))),
        ],
        const SizedBox(height: 12),
        const _AboutTile(),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (found != null)
            PrimaryButton(icon: LucideIcons.download, label: tr('Update'), height: 42, onPressed: () => Updates.download(found)),
          HairlineButton(
            height: 42,
            onPressed: _checking ? null : _check,
            child: _checking
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: p.accent))
                : Text(tr('Check for updates'), style: bodyStyle(p, 13.5, color: p.muted(0.8))),
          ),
        ]),
      ]),
    );
  }
}

/// Opens About the app: every feature, and what's new.
class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openAbout(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const BrandLogo(size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('About the app'), style: bodyStyle(p, 14.5, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(tr("Every feature, and what's new"), style: bodyStyle(p, 12.5, color: p.muted(0.5))),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight, size: 18, color: p.muted(0.4)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- account
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
          tr('Signed in as {email}. To change your password, sign out and use "Forgot password?" on the login screen.', {'email': email ?? '…'}),
          style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
        ),
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

class _DashboardSections extends StatelessWidget {
  const _DashboardSections();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final hidden = app.dashboardHidden ?? const <String>[];
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: CardTitle(tr('Dashboard'), tr('sections'))),
            if (hidden.isNotEmpty)
              TextButton(
                onPressed: () => app.setDashboardHidden([]),
                child: Text(tr('SHOW ALL'), style: monoStyle(p, 11, color: p.accentA(0.85), letterSpacing: 1.4)),
              ),
            Label(digits('${dashboardSections.length - hidden.length} / ${dashboardSections.length}')),
          ]),
          const SizedBox(height: 4),
          Text(
            tr("Choose what the dashboard shows. Hidden sections keep all their data — it's still recorded and comes back the moment you turn the section on."),
            style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
          ),
          const SizedBox(height: 12),
          for (final s in dashboardSections)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Builder(builder: (context) {
                final on = !hidden.contains(s.$1);
                return Semantics(
                  toggled: on,
                  label: tr(s.$2),
                  child: Material(
                    color: on ? p.inkA(0.02) : Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: app.dashboardHidden == null
                          ? null
                          : () => app.setDashboardHidden(on ? [...hidden, s.$1] : hidden.where((id) => id != s.$1).toList()),
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tr(s.$2), style: bodyStyle(p, 14, color: on ? p.muted(0.85) : p.muted(0.45))),
                                  Text(tr(s.$3), style: bodyStyle(p, 11.5, color: p.muted(0.35))),
                                ],
                              ),
                            ),
                            PillSwitch(on: on),
                          ]),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final list = app.categories.where((c) => c.kind == widget.kind).toList();
    final kindName = widget.kind == Kind.expense ? tr('Expense') : tr('Income');

    Future<void> add() async {
      final n = _name.text.trim();
      if (n.isEmpty || _busy) return;
      setState(() => _busy = true);
      try {
        await app.createCategory(name: n, kind: widget.kind, color: _color, sort: list.length);
        _name.clear();
      } catch (e) {
        if (context.mounted) showError(context, e);
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
        var i = list.length;
        for (final d in defaults) {
          if (have.contains(d.$1.toLowerCase())) continue;
          await app.createCategory(name: d.$1, kind: widget.kind, color: d.$2, sort: i++);
        }
      } catch (e) {
        if (context.mounted) showError(context, e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(kindName, style: displayStyle(p, 20))),
            TextButton(
              onPressed: _busy ? null : restoreDefaults,
              child: Text(tr('RESTORE DEFAULTS'), style: monoStyle(p, 10.5, color: p.accentA(0.85), letterSpacing: 1.3)),
            ),
            Label('${list.length}'),
          ]),
          const SizedBox(height: 8),
          for (final c in list) _CategoryRow(key: ValueKey(c.id), category: c),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
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
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in _swatches)
                    GestureDetector(
                      onTap: () => setState(() => _color = s),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(color: hexColor(s), shape: BoxShape.circle),
                        child: _color == s ? const Icon(LucideIcons.check, size: 14, color: Colors.white) : null,
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatefulWidget {
  const _CategoryRow({super.key, required this.category});
  final Category category;

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
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.read<AppState>();
    final c = widget.category;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
        color: p.inkA(0.02),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            CategoryBadge(name: c.name, color: hexColor(c.color), size: 32),
            const SizedBox(width: 10),
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
                  if (context.mounted) showError(context, e);
                }
              },
            ),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            for (final s in _swatches.take(8))
              GestureDetector(
                onTap: () async {
                  try {
                    await app.editCategory(c.id, color: s);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: hexColor(s),
                    shape: BoxShape.circle,
                    border: c.color.toUpperCase() == s ? Border.all(color: p.ink, width: 2) : null,
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

// Settings — port of the web's /app/settings: dashboard sections (shared with
// the web through user metadata) and category management.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../widgets/ui.dart';

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
          const PageHeader(kicker: 'Settings', title: 'Make it', accent: 'yours.'),
          const _DashboardSections(),
          const SizedBox(height: 28),
          const CardTitle('Your', 'categories.', size: 24),
          const SizedBox(height: 4),
          Text(
            'Add, rename, recolor, or remove categories for expenses and income. Deleting one keeps past transactions labeled.',
            style: bodyStyle(p, 13.5, color: p.muted(0.45), height: 1.45),
          ),
          const SizedBox(height: 14),
          const _CategorySection(kind: Kind.expense),
          const SizedBox(height: 14),
          const _CategorySection(kind: Kind.income),
          if (app.categories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Loading categories…', style: monoStyle(p, 12, color: p.muted(0.3))),
            ),
        ],
      ),
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
            const Expanded(child: CardTitle('Dashboard', 'sections')),
            if (hidden.isNotEmpty)
              TextButton(
                onPressed: () => app.setDashboardHidden([]),
                child: Text('SHOW ALL', style: monoStyle(p, 11, color: p.accentA(0.85), letterSpacing: 1.4)),
              ),
            Label('${dashboardSections.length - hidden.length} / ${dashboardSections.length}'),
          ]),
          const SizedBox(height: 4),
          Text(
            "Choose what the dashboard shows. Hidden sections keep all their data — it's still recorded and comes back the moment you turn the section on.",
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
                  label: s.$2,
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
                                  Text(s.$2, style: bodyStyle(p, 14, color: on ? p.muted(0.85) : p.muted(0.45))),
                                  Text(s.$3, style: bodyStyle(p, 11.5, color: p.muted(0.35))),
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
    final kindName = widget.kind == Kind.expense ? 'Expense' : 'Income';

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
              child: Text('RESTORE DEFAULTS', style: monoStyle(p, 10.5, color: p.accentA(0.85), letterSpacing: 1.3)),
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
                      onSubmitted: (_) => add(),
                      decoration: InputDecoration(hintText: 'New ${widget.kind.name} category'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: PrimaryButton(label: '', semanticLabel: 'Add category', icon: LucideIcons.plus, height: 44, busy: _busy, onPressed: _name.text.trim().isEmpty ? null : add),
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
              tooltip: 'Delete ${c.name}',
              onPressed: () async {
                if (!await confirm(context, 'Delete "${c.name}"?')) return;
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

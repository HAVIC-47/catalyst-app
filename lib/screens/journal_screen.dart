// Journal — port of the web's /app/journal: daily entries with a mood face, plus
// custom daily-life activities you tick off for today.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../widgets/mood_face.dart';
import '../widgets/ui.dart';

const _actColors = ['#3D80BC', '#2E8159', '#7A4E86', '#C06A33', '#CB453B', '#8E5B6E', '#3D80BC'];

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _act = TextEditingController();
  int? _mood;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _body, _act]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _act.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final today = toDateKey(DateTime.now());
    final doneToday = {for (final l in app.activityLogs) if (l.loggedOn == today) l.activityId};
    final canSave = _title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty;

    Future<void> save() async {
      if (!canSave || _busy) return;
      setState(() => _busy = true);
      try {
        await app.createJournal(entryOn: today, mood: _mood, title: _title.text.trim(), body: _body.text.trim());
        _title.clear();
        _body.clear();
        setState(() => _mood = null);
      } catch (e) {
        if (context.mounted) showError(context, e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    Future<void> addActivity() async {
      final n = _act.text.trim();
      if (n.isEmpty) return;
      try {
        await app.createActivity(n, _actColors[app.activities.length % _actColors.length]);
        _act.clear();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return RefreshIndicator(
      onRefresh: app.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PageHeader(kicker: 'Journal · ${fmt(DateTime.now(), 'EEEE, MMM d')}', title: 'Daily', accent: 'log.'),
          CardBox(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Label('New entry · today'),
                const SizedBox(height: 10),
                TextField(controller: _title, decoration: const InputDecoration(hintText: 'Title')),
                const SizedBox(height: 8),
                TextField(
                  controller: _body,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(hintText: 'How did the day go? What happened?'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final m in moodPresets)
                      Semantics(
                        button: true,
                        selected: _mood == m.value,
                        label: m.label,
                        child: Tooltip(
                          message: m.label,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () => setState(() => _mood = _mood == m.value ? null : m.value),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                color: _mood == m.value ? m.color.withValues(alpha: 0.1) : Colors.transparent,
                                border: Border.all(color: _mood == m.value ? m.color.withValues(alpha: 0.5) : p.line),
                              ),
                              child: Center(child: MoodFace(m.value, size: 20, muted: _mood != m.value, color: p.muted(0.4))),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    PrimaryButton(label: 'Save entry', height: 42, busy: _busy, onPressed: canSave ? save : null),
                  ],
                ),
              ],
            ),
          ),
          if (!app.loading && app.journal.isEmpty)
            const Padding(padding: EdgeInsets.only(bottom: 16), child: EmptyCard('No journal entries yet. Write your first above.')),
          for (final j in app.journal)
            CardBox(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    if (j.mood != null) ...[MoodFace(j.mood!, size: 20), const SizedBox(width: 8)],
                    Expanded(child: Text(j.title.isEmpty ? 'Untitled' : j.title, style: displayStyle(p, 18))),
                    Text(fmt(fromDateKey(j.entryOn), 'MMM d, yyyy'), style: monoStyle(p, 11, color: p.muted(0.35))),
                    TrashButton(
                      tooltip: 'Delete entry',
                      onPressed: () async {
                        if (!await confirm(context, 'Delete this entry?')) return;
                        try {
                          await app.removeJournal(j.id);
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                    ),
                  ]),
                  if (j.body.isNotEmpty) Text(j.body, style: bodyStyle(p, 14, color: p.muted(0.65), height: 1.55)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          // custom activities
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Label("Today's activities"),
                const SizedBox(height: 6),
                Text('Track custom daily-life habits. Tap to mark done for today.', style: bodyStyle(p, 12, color: p.muted(0.4))),
                const SizedBox(height: 12),
                if (app.activities.isEmpty) Text('No activities yet. Add one below.', style: bodyStyle(p, 12, color: p.muted(0.3))),
                for (final a in app.activities)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: Material(
                          color: doneToday.contains(a.id) ? p.inkA(0.06) : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: doneToday.contains(a.id) ? p.inkA(0.25) : p.line),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              try {
                                await app.toggleActivity(a.id, today);
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              child: Row(children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: doneToday.contains(a.id) ? hexColor(a.color) : p.inkA(0.2)),
                                    color: doneToday.contains(a.id) ? hexColor(a.color).withValues(alpha: 0.2) : Colors.transparent,
                                  ),
                                  child: doneToday.contains(a.id) ? Icon(LucideIcons.check, size: 14, color: hexColor(a.color)) : null,
                                ),
                                const SizedBox(width: 10),
                                Text(a.name, style: bodyStyle(p, 14, color: doneToday.contains(a.id) ? p.ink : p.muted(0.55))),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove ${a.name}',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          if (!await confirm(context, 'Remove "${a.name}"?', action: 'Remove')) return;
                          try {
                            await app.removeActivity(a.id);
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                        },
                        icon: Icon(LucideIcons.x, size: 16, color: p.muted(0.3)),
                      ),
                    ]),
                  ),
                const SizedBox(height: 8),
                Divider(color: p.line, height: 1),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _act,
                      onSubmitted: (_) => addActivity(),
                      decoration: const InputDecoration(hintText: 'e.g. Workout, Read, Sleep 8h'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 46,
                    child: PrimaryButton(label: '', semanticLabel: 'Add activity', icon: LucideIcons.plus, height: 46, onPressed: _act.text.trim().isEmpty ? null : addActivity),
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

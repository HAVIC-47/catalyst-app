// AI summary card — port of the web's AiInsights: a short read of one topic (or
// a few, as tabs) for a week, month or year, plus suggestions, written by Gemini
// on the web app's server from the user's own data. The saved summary shows
// straight away; it's only rewritten on request, and the card says when newer
// entries exist.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_state.dart';
import '../data/insights.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/format.dart';
import '../util/range.dart';
import 'charts.dart';
import 'ui.dart';

const _periods = [Range.week, Range.month, Range.year];

const _pitch = {
  InsightTopic.ledger: 'A quick read on where your money came from and went — and what to change.',
  InsightTopic.savings: 'How much you kept and put away, and realistic ways to save more.',
  InsightTopic.goals: 'Whether your saving pace will reach each goal, and how to get there sooner.',
  InsightTopic.bills: "What's due, what's overdue, and how to keep your bills under control.",
  InsightTopic.journal: 'What your entries were about, how the days felt, and small things that might help.',
  InsightTopic.mood: 'How your mood moved, what lifted or lowered it, and gentle ways to feel better.',
  InsightTopic.todo: "What's done, what's overdue or due soon, and what to tackle first.",
  InsightTopic.shopping: "What's still to buy, what it'll cost, and ways to shop smarter.",
};

const _suggestionsLabel = {
  InsightTopic.ledger: 'Money moves',
  InsightTopic.savings: 'To save more',
  InsightTopic.goals: 'To reach your goals',
  InsightTopic.bills: 'To stay on top of bills',
  InsightTopic.journal: 'Small things to try',
  InsightTopic.mood: 'To feel better',
  InsightTopic.todo: 'To get through it',
  InsightTopic.shopping: 'To shop smarter',
};

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return 'on ${fmt(t, 'MMM d')}';
}

class AiInsightsCard extends StatefulWidget {
  const AiInsightsCard({super.key, required this.topics, this.initiallyOpen = true});

  final List<InsightTopic> topics;

  /// Folded or not on a first visit; after that the card remembers the user's choice.
  /// The boards start it folded, so the board stays near the top.
  final bool initiallyOpen;

  /// Where summaries come from — tests swap in an answer that needs no server.
  @visibleForTesting
  static Future<InsightResult> Function({required InsightTopic topic, required Range period, required String start, required bool generate}) request =
      requestInsight;

  @override
  State<AiInsightsCard> createState() => _AiInsightsCardState();
}

class _AiInsightsCardState extends State<AiInsightsCard> {
  late InsightTopic _topic = widget.topics.first;
  Range _period = Range.week;
  int _offset = 0;
  late bool _open = widget.initiallyOpen;

  String _key = ''; // what _data / _loadError belong to
  InsightResult? _data;
  String? _loadError;
  int _run = 0; // bumps per request, so a late reply for an old period is ignored
  String? _generating; // key being written
  String? _genErrorKey;
  String _genError = '';
  String _signature = '';
  Timer? _recheck;

  String get _prefsKey => 'ai-open:${widget.topics.map((t) => t.name).join('+')}';
  Window get _win => rangeWindow(_period, _offset);
  String get _currentKey => '${_topic.name}|${_period.name}|${_win.startKey}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getBool(_prefsKey);
      if (mounted && saved != null && saved != _open) setState(() => _open = saved);
    });
  }

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  // The collections behind each topic: when one changes (AppState swaps in a new
  // list), quietly re-check whether the saved summary is out of date.
  List<Object> _sources(AppState a) => switch (_topic) {
        InsightTopic.ledger => [a.transactions, a.budgets],
        InsightTopic.savings => [a.transactions, a.goals],
        InsightTopic.goals => [a.goals, a.transactions],
        InsightTopic.bills => [a.bills, a.transactions],
        InsightTopic.journal => [a.journal, a.activities, a.activityLogs],
        InsightTopic.mood => [a.moods, a.transactions, a.journal, a.activityLogs],
        InsightTopic.todo => [a.boards, a.boardColumns, a.tickets],
        InsightTopic.shopping => [a.boards, a.boardColumns, a.tickets, a.transactions],
      };

  Future<void> _fetch({bool quiet = false}) async {
    final key = _currentKey;
    final run = ++_run;
    if (!quiet) {
      setState(() {
        _key = key;
        _data = null;
        _loadError = null;
      });
    }
    try {
      final r = await AiInsightsCard.request(topic: _topic, period: _period, start: _win.startKey, generate: false);
      if (!mounted || run != _run) return;
      setState(() {
        _key = key;
        _data = r;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || run != _run || quiet) return;
      setState(() => _loadError = _message(e));
    }
  }

  static String _message(Object e) => e is InsightError ? e.message : "AI summaries aren't available right now.";

  Future<void> _generate() async {
    final key = _currentKey;
    setState(() {
      _generating = key;
      _genErrorKey = null;
    });
    try {
      final r = await AiInsightsCard.request(topic: _topic, period: _period, start: _win.startKey, generate: true);
      if (!mounted) return;
      if (key == _currentKey) {
        _run++; // a re-check still in flight mustn't overwrite this
        setState(() {
          _key = key;
          _data = r;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _genErrorKey = key;
          _genError = _message(e);
        });
      }
    } finally {
      if (mounted && _generating == key) setState(() => _generating = null);
    }
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      if (!_open) _signature = ''; // reopening re-checks
    });
    SharedPreferences.getInstance().then((p) => p.setBool(_prefsKey, _open));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final app = context.watch<AppState>();
    final key = _currentKey;

    if (!app.loading && _open) {
      final sig = '$key#${_sources(app).map(identityHashCode).join('.')}';
      if (sig != _signature) {
        final fresh = !_signature.startsWith('$key#') || _key != key;
        _signature = sig;
        _recheck?.cancel();
        if (fresh) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fetch();
          });
        } else {
          _recheck = Timer(const Duration(milliseconds: 800), () {
            if (mounted) _fetch(quiet: true);
          });
        }
      }
    }

    final data = _key == key ? _data : null;
    final loadError = _key == key ? _loadError : null;
    final generating = _generating == key;
    final periodName = _offset == 0 ? 'this ${_period.name}' : _win.label;
    final title = widget.topics.length > 1 ? 'AI insights' : 'AI ${insightLabels[_topic]!.toLowerCase()} summary';

    final Widget body;
    if (loadError != null) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(loadError, style: bodyStyle(p, 13.5, color: p.expense)),
        TextButton(
          onPressed: _fetch,
          child: Text('TRY AGAIN', style: monoStyle(p, 11, color: p.accentA(0.85), letterSpacing: 1.4)),
        ),
      ]);
    } else if (data == null) {
      body = _Skeleton(p: p);
    } else if (data.insight case final insight?) {
      body = Opacity(
        opacity: generating ? 0.5 : 1,
        child: _InsightBody(
          insight: insight,
          suggestionsLabel: _suggestionsLabel[_topic]!,
          footer: Row(children: [
            if (data.stale && !generating) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: p.accentA(0.12), borderRadius: BorderRadius.circular(99)),
                child: Text('New entries since', style: bodyStyle(p, 11, weight: FontWeight.w600, color: p.accent)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                'Written ${data.generatedAt == null ? '' : '${_ago(data.generatedAt!)} '}by Gemini · can be wrong',
                style: bodyStyle(p, 11, color: p.muted(0.45)),
              ),
            ),
            TextButton.icon(
              onPressed: generating ? null : _generate,
              icon: generating
                  ? SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.6, color: p.accent))
                  : Icon(LucideIcons.refreshCw, size: 14, color: p.accentA(0.85)),
              label: Text(
                generating ? 'WRITING…' : (data.stale ? 'UPDATE' : 'REFRESH'),
                style: monoStyle(p, 11, color: p.accentA(0.85), letterSpacing: 1.2),
              ),
            ),
          ]),
        ),
      );
    } else if (data.empty) {
      body = Text('Nothing logged for $periodName yet. Add some entries and a summary can be written.',
          style: bodyStyle(p, 13.5, color: p.muted(0.5), height: 1.45));
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_pitch[_topic]!, style: bodyStyle(p, 13.5, color: p.muted(0.6), height: 1.45)),
        const SizedBox(height: 12),
        PrimaryButton(
          icon: LucideIcons.sparkles,
          label: generating ? 'Writing…' : 'Summarize $periodName',
          busy: generating,
          height: 44,
          onPressed: _generate,
        ),
      ]);
    }

    return CardBox(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: title,
            child: InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: ExcludeSemantics(
                  child: Row(children: [
                    Icon(LucideIcons.sparkles, size: 16, color: p.accent),
                    const SizedBox(width: 8),
                    // One line that truncates at its end: the label, then topic and period.
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: title.toUpperCase(),
                            style: TextStyle(fontFamily: Fonts.mono, fontSize: 11, letterSpacing: 11 * 0.18, color: p.labelColor),
                          ),
                          TextSpan(
                            text: '  · ${widget.topics.length > 1 ? '${insightLabels[_topic]} · ' : ''}${_win.label}',
                            style: monoStyle(p, 11, color: p.muted(0.4)),
                          ),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16, color: p.muted(0.4)),
                  ]),
                ),
              ),
            ),
          ),
          if (_open) ...[
            Divider(color: p.line, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.topics.length > 1) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegTabs<InsightTopic>(
                        options: widget.topics,
                        value: _topic,
                        compact: true,
                        label: (t) => insightLabels[t]!,
                        onChanged: (t) => setState(() => _topic = t),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  RangeControls(
                    ranges: _periods,
                    range: _period,
                    offset: _offset,
                    onRange: (r) => setState(() => _period = r),
                    onOffset: (o) => setState(() => _offset = o),
                  ),
                  const SizedBox(height: 14),
                  body,
                  if (_genErrorKey == key) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: p.expense.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.expense.withValues(alpha: 0.3)),
                      ),
                      child: Text(_genError, style: bodyStyle(p, 12.5, color: p.expense)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightBody extends StatelessWidget {
  const _InsightBody({required this.insight, required this.suggestionsLabel, required this.footer});

  final Insight insight;
  final String suggestionsLabel;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (insight.headline.isNotEmpty) Text(insight.headline, style: displayStyle(p, 22).copyWith(height: 1.15)),
        const SizedBox(height: 8),
        Text(insight.summary, style: bodyStyle(p, 14, color: p.muted(0.75), height: 1.5)),
        if (insight.highlights.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final h in insight.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, right: 10),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(color: p.accentA(0.8), shape: BoxShape.circle),
                ),
                Expanded(child: Text(h, style: bodyStyle(p, 13.5, color: p.muted(0.7), height: 1.4))),
              ]),
            ),
        ],
        if (insight.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Label(suggestionsLabel),
          const SizedBox(height: 8),
          for (final (title, detail) in insight.suggestions)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.line),
                color: p.inkA(0.02),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 9),
                  child: Icon(LucideIcons.lightbulb, size: 16, color: p.accent),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (title.isNotEmpty) Text(title, style: bodyStyle(p, 14, weight: FontWeight.w600)),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(detail, style: bodyStyle(p, 12.5, color: p.muted(0.6), height: 1.45)),
                    ],
                  ]),
                ),
              ]),
            ),
        ],
        const SizedBox(height: 6),
        Divider(color: p.line, height: 1),
        const SizedBox(height: 4),
        footer,
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.p});

  final Palette p;

  @override
  Widget build(BuildContext context) {
    Widget bar(double factor, double h, double a) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: factor,
          child: Container(height: h, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: p.inkA(a), borderRadius: BorderRadius.circular(6))),
        );
    return Semantics(
      label: 'Loading summary',
      child: Column(children: [bar(0.65, 22, 0.07), bar(1, 13, 0.05), bar(0.85, 13, 0.05)]),
    );
  }
}

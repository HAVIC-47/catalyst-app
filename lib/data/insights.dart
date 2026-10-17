// AI summaries — the web app's /api/ai-insights (src/lib/insights.ts there).
// The server reads the user's own rows and asks Gemini for a short summary and
// suggestions; the app sends only the topic, period, language and its login
// token. The Gemini key never leaves the server.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../util/format.dart';
import '../util/i18n.dart';
import '../util/range.dart';

enum InsightTopic { journal, ledger, goals, savings, bills, mood, todo, shopping, recap }

/// Tab label for each topic (same as the web).
const insightLabels = {
  InsightTopic.journal: 'Journal',
  InsightTopic.ledger: 'Money',
  InsightTopic.goals: 'Goals',
  InsightTopic.savings: 'Savings',
  InsightTopic.bills: 'Bills',
  InsightTopic.mood: 'Mood',
  InsightTopic.todo: 'To-do',
  InsightTopic.shopping: 'To-buy',
  InsightTopic.recap: 'Recap',
};

class Insight {
  const Insight({required this.headline, required this.summary, required this.highlights, required this.suggestions});

  final String headline;
  final String summary;
  final List<String> highlights;
  final List<(String, String)> suggestions; // (title, detail)

  static Insight? fromJson(Object? j) {
    if (j is! Map) return null;
    final summary = j['summary'];
    if (summary is! String || summary.isEmpty) return null;
    return Insight(
      headline: j['headline'] as String? ?? '',
      summary: summary,
      highlights: [for (final h in (j['highlights'] as List? ?? const [])) if (h is String && h.isNotEmpty) h],
      suggestions: [
        for (final s in (j['suggestions'] as List? ?? const []).whereType<Map>()) ('${s['title'] ?? ''}', '${s['detail'] ?? ''}'),
      ],
    );
  }
}

class InsightResult {
  const InsightResult({required this.insight, required this.generatedAt, required this.stale, required this.empty});

  final Insight? insight;
  final DateTime? generatedAt;
  final bool stale; // there's newer data than the saved summary
  final bool empty; // nothing logged for this topic in the period

  factory InsightResult.fromJson(Map<String, dynamic> j) => InsightResult(
        insight: Insight.fromJson(j['insight']),
        generatedAt: DateTime.tryParse('${j['generatedAt'] ?? ''}')?.toLocal(),
        stale: j['stale'] == true,
        empty: j['empty'] == true,
      );
}

class InsightError implements Exception {
  const InsightError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The saved summary for a period ([generate] false — no AI call), or a fresh
/// one ([generate] true — counts toward the daily limit).
Future<InsightResult> requestInsight({
  required InsightTopic topic,
  required Range period,
  required String start,
  required bool generate,
}) async {
  final auth = Supabase.instance.client.auth;
  var session = auth.currentSession;
  if (session != null && session.isExpired) session = (await auth.refreshSession()).session;
  if (session == null) throw InsightError(tr('Log in again to use AI summaries.'));

  http.Response res;
  try {
    res = await http
        .post(
          Uri.parse('$apiBaseUrl/api/ai-insights'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
          body: jsonEncode({
            'topic': topic.name,
            'period': period.name,
            'start': start,
            'today': toDateKey(DateTime.now()),
            'mode': generate ? 'generate' : 'cached',
            'lang': appLang, // the summary is written in the app's language
          }),
        )
        .timeout(Duration(seconds: generate ? 75 : 20));
  } on TimeoutException {
    throw InsightError(generate ? tr('The AI took too long — try again.') : tr('Couldn\'t load the summary — try again.'));
  } catch (_) {
    throw InsightError(tr('No connection — try again.'));
  }
  Map<String, dynamic>? data;
  try {
    data = jsonDecode(res.body) as Map<String, dynamic>?;
  } catch (_) {
    data = null;
  }
  if (res.statusCode != 200 || data == null) {
    throw InsightError(data?['error'] as String? ?? tr('AI summaries aren\'t available right now.'));
  }
  return InsightResult.fromJson(data);
}

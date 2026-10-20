// About the app (Settings → About the app): the version and updates, what's new
// in this version, then everything the Android app does (lib/data/features.dart).
// The same "what's new" pops up once after each update (showWhatsNew), and a
// newer version on GitHub pops up with an Update button (showUpdateDialog) — both
// called by the shell.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/features.dart';
import '../services/updates.dart';
import '../services/whats_new.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/i18n.dart';
import '../widgets/ui.dart';

/// Open About on top of the app.
Future<void> openAbout(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = Updates.current;
  UpdateInfo? _found = Updates.available.value;
  bool _checking = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    if (_version.isEmpty) {
      Updates.version().then((v) {
        if (mounted) setState(() => _version = v);
      }, onError: (Object _) {});
    }
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
    final latest = releaseFor(_version);
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: HairlineIconButton(
                icon: LucideIcons.arrowLeft,
                tooltip: tr('Back'),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(height: 16),
            PageHeader(kicker: tr('About the app'), title: tr('Everything it'), accent: tr('does.')),
            CardBox(
              margin: const EdgeInsets.only(bottom: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const BrandLogo(size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Catalyst'), style: displayStyle(p, 26)),
                      if (_version.isNotEmpty)
                        Text(tr('Version {version} · Android', {'version': _version}), style: monoStyle(p, 12, color: p.muted(0.5))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  tr('Mood × money: an honest ledger that maps every taka against how the day actually felt.'),
                  style: bodyStyle(p, 14, color: p.muted(0.6), height: 1.5),
                ),
                if (_found != null) ...[
                  const SizedBox(height: 10),
                  Text(tr('Version {version} is out.', {'version': _found!.version}), style: bodyStyle(p, 13.5, color: p.accent)),
                ] else if (_checked) ...[
                  const SizedBox(height: 10),
                  Text(tr("You're on the latest version."), style: bodyStyle(p, 13, color: p.muted(0.45))),
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  if (_found != null)
                    PrimaryButton(icon: LucideIcons.download, label: tr('Update'), height: 42, onPressed: () => Updates.download(_found!)),
                  HairlineButton(
                    height: 42,
                    onPressed: _checking ? null : _check,
                    child: _checking
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: p.accent))
                        : Text(tr('Check for updates'), style: bodyStyle(p, 13.5, color: p.muted(0.8))),
                  ),
                ]),
              ]),
            ),
            if (latest != null) _WhatsNewCard(release: latest),
            for (final g in appFeatures())
              CardBox(
                margin: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CardTitle(g.title, g.accent),
                  const SizedBox(height: 14),
                  for (final f in g.features) FeatureRow(feature: f),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the installed version brought — on top of the feature list.
class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard({required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.accentA(p.dark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.accentA(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.gift, size: 16, color: p.accent),
          const SizedBox(width: 8),
          Expanded(child: Label(tr("What's new in {version}", {'version': release.version}), color: p.accent)),
        ]),
        const SizedBox(height: 14),
        for (final f in release.notes) FeatureRow(feature: f),
      ]),
    );
  }
}

/// One feature: its icon in a tinted square, the name, a line about it.
class FeatureRow extends StatelessWidget {
  const FeatureRow({super.key, required this.feature});

  final Feature feature;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: p.accentA(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(feature.icon, size: 16, color: p.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(feature.title, style: bodyStyle(p, 14.5, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(feature.body, style: bodyStyle(p, 13, color: p.muted(0.55), height: 1.45)),
          ]),
        ),
      ]),
    );
  }
}

/// The pop-up when a newer version is out: Update starts the APK download.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo update) =>
    showDialog<void>(context: context, builder: (_) => UpdateDialog(update: update));

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.update});

  final UpdateInfo update;

  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    if (!await Updates.download(update)) {
      messenger.showSnackBar(SnackBar(content: Text(tr("Couldn't open the download — get it from {url}", {'url': latestReleaseUrl}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.line)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const BrandLogo(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label(tr('Update available'), color: p.accent),
                  const SizedBox(height: 2),
                  Text(tr('Catalyst {version}', {'version': update.version}), style: displayStyle(p, 24)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Text(
              tr('You have {current}. Update downloads the new version — open the file when it finishes and install it '
                  "over this one. Your data stays, and you'll see what's new once it's installed.", {'current': Updates.current}),
              style: bodyStyle(p, 14, color: p.muted(0.6), height: 1.5),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: HairlineButton(
                  height: 44,
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Later'), maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(p, 14, color: p.muted(0.8))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(icon: LucideIcons.download, label: tr('Update'), height: 44, expand: true, onPressed: () => _download(context)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The pop-up after an update: what the releases since the last version opened
/// brought, newest first. True when "All features" was chosen.
Future<bool> showWhatsNew(BuildContext context, List<Release> due) async =>
    await showDialog<bool>(context: context, builder: (_) => WhatsNewDialog(releases: due)) ?? false;

class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key, required this.releases});

  final List<Release> releases;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.line)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Row(children: [
              const BrandLogo(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label(tr("What's new"), color: p.accent),
                  const SizedBox(height: 2),
                  Text(tr('Catalyst {version}', {'version': releases.first.version}), style: displayStyle(p, 24)),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: p.line),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              children: [
                for (final r in releases) ...[
                  if (releases.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Label(tr('Version {version}', {'version': r.version})),
                    ),
                  for (final f in r.notes) FeatureRow(feature: f),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: p.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(children: [
              Expanded(
                child: HairlineButton(
                  height: 44,
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    tr('All features'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(p, 14, color: p.muted(0.8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(label: tr('Got it'), height: 44, expand: true, onPressed: () => Navigator.pop(context, false)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

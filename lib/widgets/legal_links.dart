// The website's Privacy Policy and Terms, linked from the login screen and the foot
// of About the app (Google Play wants the policy reachable inside the app).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../util/i18n.dart';

class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget link(String label, String url) => TextButton(
          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(label, style: bodyStyle(p, 12.5, color: p.muted(0.5))),
        );
    return Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
      link(tr('Privacy Policy'), privacyUrl),
      link(tr('Terms of Service'), termsUrl),
    ]);
  }
}

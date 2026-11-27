/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:flutter/material.dart';
import 'package:qanis/ui/configuration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qanis/l10n/app_localizations.dart';
import 'package:qanis/ui/component/utils.dart';

import '../../app_update/app_update_repository.dart';
import 'donate.dart';

/// 关于
class About extends StatefulWidget {
  const About({super.key});

  @override
  State<StatefulWidget> createState() {
    return _AboutState();
  }
}

class _AboutState extends State<About> {
  bool checkUpdating = false;

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    final bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    String gitHub = "https://github.com/wanghongenpin/proxypin";
    final String downloadUrl = isCN ? "https://gitee.com/wanghongenpin/proxypin/releases" : "$gitHub/releases";
    const String developerUrl = "https://t.me/maho_s9";

    // QANIS brand accent: amber #E8A33D (DarkPalette.warn), darkened for light backgrounds.
    final Color brandColor =
        Theme.of(context).brightness == Brightness.dark ? DarkPalette.warn : const Color(0xFFB07415);

    return Scaffold(
        appBar: AppBar(title: Text(localizations.about, style: const TextStyle(fontSize: 16)), centerTitle: true),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const SizedBox(height: 6),
          Center(
              child: Text("QANIS",
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: brandColor, fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Center(child: Text("Based on QANIS (Apache-2.0)", style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 10),
          Center(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(localizations.proxyPinSoftware, textAlign: TextAlign.center))),
          const SizedBox(height: 8),
          Center(child: Text("Version ${AppConfiguration.version}")),
          const SizedBox(height: 12),
          Card(
              color: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                ListTile(
                    title: const Text("GitHub"),
                    trailing: const Icon(Icons.open_in_new, size: 22),
                    onTap: () {
                      _safeLaunch(Uri.parse(gitHub));
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.feedback),
                    trailing: const Icon(Icons.open_in_new, size: 22),
                    onTap: () {
                      _safeLaunch(Uri.parse("$gitHub/issues"));
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.appUpdateCheckVersion),
                    trailing: checkUpdating
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync, size: 22),
                    onTap: () async {
                      if (checkUpdating) return;
                      setState(() => checkUpdating = true);
                      await AppUpdateRepository.checkUpdate(context, canIgnore: false, showToast: true);
                      if (mounted) setState(() => checkUpdating = false);
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.download),
                    trailing: const Icon(Icons.open_in_new, size: 22),
                    onTap: () {
                      _safeLaunch(Uri.parse(downloadUrl));
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.privacyPolicy),
                    trailing: const Icon(Icons.privacy_tip_outlined, size: 22),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(localizations.privacyPolicy),
                          content: SingleChildScrollView(
                              child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 385),
                                  child: Text(localizations.privacyContent, style: const TextStyle(height: 1.35)))),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(localizations.close))
                          ],
                        ),
                      );
                    }),
                Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                // Sponsor / Donate entry
                ListTile(
                  title: Text(localizations.sponsorDonate),
                  subtitle: Text(localizations.sponsorSupport, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.favorite, color: Colors.redAccent, size: 22),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DonatePage())),
                ),
              ])),
          const SizedBox(height: 12),
          // Developer block
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: DarkPalette.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DarkPalette.divider, width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Developer", style: TextStyle(fontSize: 12, color: DarkPalette.text2)),
                const SizedBox(height: 6),
                const Text("Ahmed Alhrrani", style: TextStyle(fontSize: 14, color: DarkPalette.text1)),
                const SizedBox(height: 4),
                InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _safeLaunch(Uri.parse(developerUrl)),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(developerUrl,
                            style: const TextStyle(fontSize: 13, color: DarkPalette.primary)))),
              ])),
          const SizedBox(height: 12),
        ]));
  }

  Future<void> _safeLaunch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

}

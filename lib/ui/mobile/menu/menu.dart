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
import 'dart:io';

import 'package:date_format/date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:qanis/l10n/app_localizations.dart';
import 'package:qanis/native/vpn.dart';
import 'package:qanis/utils/ip.dart';
import 'package:qanis/network/bin/server.dart';
import 'package:qanis/ui/component/proxy_port_setting.dart';
import 'package:qanis/ui/component/svg_icon.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/ui/mobile/menu/drawer.dart' show FilterMenu;
import 'package:qanis/ui/mobile/mobile.dart';
import 'package:qanis/ui/mobile/request/domians.dart';
import 'package:qanis/ui/mobile/setting/app_filter.dart';
import 'package:qanis/ui/mobile/setting/proxy.dart';
import 'package:qanis/ui/mobile/setting/report_servers.dart';
import 'package:qanis/ui/mobile/widgets/highlight.dart';
import 'package:qanis/ui/mobile/widgets/remote_device.dart';

/// Traffic ⋮ menu — flat 15-row panel (Reqable-style), dark #333333 surface.
///
/// Constructor and call site are unchanged; only the presentation and the row
/// set are rebuilt.
class MoreMenu extends StatelessWidget {
  /// Current list ordering. Kept as a static so the ordering survives rebuilds
  /// of the traffic screen (same contract as before).
  static bool sortDesc = true;

  final ProxyServer proxyServer;

  /// Retained so the existing call site stays unchanged. No row in the current
  /// 15-row spec drives the remote-device page any more.
  final ValueNotifier<RemoteModel> remoteDevice;

  const MoreMenu({super.key, required this.proxyServer, required this.remoteDevice});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      width: 38,
      child: IconButton(
        onPressed: () => _showMenu(context),
        padding: EdgeInsets.zero,
        iconSize: 26,
        splashRadius: 20,
        icon: const Icon(Icons.more_vert, size: 26),
      ),
    );
  }

  /// Opens the panel anchored under the ⋮ action.
  void _showMenu(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 110),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (dialogContext, animation, _, __) {
        return FadeTransition(
          opacity: animation,
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(dialogContext).top + 46, right: 8),
              child: _TrafficMenuPanel(hostContext: context, proxyServer: proxyServer),
            ),
          ),
        );
      },
    );
  }
}

/// The 15-row flat menu body.
class _TrafficMenuPanel extends StatefulWidget {
  /// Context of the ⋮ action itself; stays mounted after the panel closes, so
  /// page pushes and toasts must use it rather than the dialog's own context.
  final BuildContext hostContext;
  final ProxyServer proxyServer;

  const _TrafficMenuPanel({required this.hostContext, required this.proxyServer});

  @override
  State<_TrafficMenuPanel> createState() => _TrafficMenuPanelState();
}

class _TrafficMenuPanelState extends State<_TrafficMenuPanel> {
  static const String _notAvailable = 'Not available in this build';

  ProxyServer get proxyServer => widget.proxyServer;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final externalProxy = proxyServer.configuration.externalProxy;
    final appCount = proxyServer.configuration.appWhitelist.length;

    return Container(
      width: 268,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
      decoration: BoxDecoration(
        color: DarkPalette.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DarkPalette.divider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Filter
            _row(
              icon: 'funnel',
              label: 'Filter',
              onTap: () => _open(FilterMenu(proxyServer: proxyServer)),
            ),
            _sep(),
            // 2. Search
            _row(
              icon: 'search',
              label: localizations.search,
              onTap: () {
                _close();
                MobileApp.searchStateKey.currentState?.showSearch();
              },
            ),
            _sep(),
            // 3. Sort — existing two-state ordering (newest / oldest)
            _row(
              icon: 'sort',
              label: 'Sort',
              value: MoreMenu.sortDesc ? localizations.timeDesc : localizations.timeAsc,
              onTap: () {
                MoreMenu.sortDesc = !MoreMenu.sortDesc;
                MobileApp.requestStateKey.currentState?.sort(MoreMenu.sortDesc);
                setState(() {});
              },
            ),
            _sep(),
            // 4. Share — no share implementation exists in this build
            _row(
              icon: 'share',
              label: localizations.share,
              value: '—',
              disabled: true,
              chevron: false,
              onTap: () => _toast(_notAvailable),
            ),
            _sep(),
            // 5. Export — existing export handler
            _row(
              icon: 'export',
              label: localizations.export,
              onTap: () {
                final host = widget.hostContext;
                _close();
                final name = formatDate(DateTime.now(), [m, '-', d, ' ', HH, ':', nn, ':', ss]);
                MobileApp.requestStateKey.currentState?.export(host, 'QANIS$name');
              },
            ),
            _sep(),
            // 6. Group by Host — the Domain List view
            _row(
              icon: 'group_host',
              label: 'Group by Host',
              value: 'Domain List',
              onTap: () {
                _close();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                          backgroundColor: DarkPalette.bg,
                          appBar: AppBar(
                            toolbarHeight: 52,
                            backgroundColor: DarkPalette.panel,
                            foregroundColor: DarkPalette.text1,
                            surfaceTintColor: Colors.transparent,
                            elevation: 0,
                            scrolledUnderElevation: 0,
                            shape: const Border(
                                bottom: BorderSide(color: DarkPalette.divider, width: 0.5)),
                            title: const Text('Domain List',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: DarkPalette.text1)),
                          ),
                          body: DomainList(
                              list: MobileApp.container,
                              proxyServer: proxyServer),
                        )));
              },
            ),
            _sep(),
            // 7. Application (N) — existing app whitelist page
            _row(
              icon: 'application',
              label: 'Application ($appCount)',
              value: proxyServer.configuration.appWhitelistEnabled ? 'On' : 'Off',
              onTap: () => _open(AppWhitelist(proxyServer: proxyServer)),
            ),
            _sep(),
            // 8. Proxy Port — current port, opens the port editor
            _row(
              icon: 'port',
              label: 'Proxy Port',
              value: '${proxyServer.port}',
              onTap: () => _open(_PortSettingPage(proxyServer: proxyServer)),
            ),
            _sep(),
            // 9. Record Mode — VPN or plain proxy, live state
            _row(
              icon: Vpn.isVpnStarted ? 'record_mode' : 'proxy',
              label: 'Record Mode',
              value: Vpn.isVpnStarted ? 'VPN' : 'Proxy (${proxyServer.port})',
              onTap: () async {
                _close();
                if (Vpn.isVpnStarted) {
                  Vpn.stopVpn();
                  if (context.mounted) FlutterToastr.show('Switched to Proxy mode', context);
                } else {
                  String host = Platform.isAndroid ? await localIp(readCache: false) : '127.0.0.1';
                  Vpn.startVpn(host, proxyServer.port, proxyServer.configuration);
                  if (context.mounted) FlutterToastr.show('Switched to VPN mode', context);
                }
              },
            ),
            _sep(),
            // 10. Enhanced Mode — HTTPS decryption
            _row(
              icon: 'lock',
              label: 'Enhanced Mode',
              value: proxyServer.enableSsl ? 'On' : 'Off',
              onTap: () {
                proxyServer.enableSsl = !proxyServer.enableSsl;
                proxyServer.configuration.flushConfig();
                _close();
              },
            ),
            _sep(),
            // 11. SSL Proxying — wired to proxyServer.enableSsl
            _row(
              icon: 'ssl',
              label: 'SSL Proxying',
              value: proxyServer.enableSsl ? 'On' : 'Off',
              chevron: false,
              onTap: () {
                proxyServer.enableSsl = !proxyServer.enableSsl;
                setState(() {});
              },
            ),
            _sep(),
            // 12. Auto Highlight — existing keyword highlight page
            _row(
              icon: 'highlight',
              label: 'Auto Highlight',
              onTap: () => _open(const KeywordHighlight()),
            ),
            _sep(),
            // 13. Secondary Proxy — existing external proxy dialog
            _row(
              icon: 'proxy',
              label: 'Secondary Proxy',
              value: externalProxy == null ? 'Off' : '${externalProxy.host}:${externalProxy.port}',
              onTap: () {
                final host = widget.hostContext;
                _close();
                showDialog(
                  context: host,
                  builder: (_) => ExternalProxyDialog(configuration: proxyServer.configuration),
                );
              },
            ),
            _sep(),
            // 14. Access Control — existing app blacklist page
            _row(
              icon: 'access',
              label: 'Access Control',
              onTap: () => _open(AppBlacklist(proxyServer: proxyServer)),
            ),
            _sep(),
            // 15. Report Server — existing report/MCP page
            _row(
              icon: 'report',
              label: 'Report Server',
              onTap: () => _open(const ReportServersPageMobile()),
            ),
          ],
        ),
      ),
    );
  }

  /// One 44dp row: 18dp leading icon, 14sp label, 12.5sp value, optional chevron.
  ///
  /// [icon] names a stroke SVG in `assets/icons/` (see [SvgIcon]). It is tinted
  /// `DarkPalette.text2`, or `DarkPalette.primary` when the row reads `On`.
  /// Rows that pass no [icon] keep the previous icon-free alignment.
  Widget _row({
    required String label,
    String? value,
    required VoidCallback onTap,
    bool disabled = false,
    bool chevron = true,
    String? icon,
  }) {
    final labelColor = disabled ? DarkPalette.text3 : DarkPalette.text1;
    final valueColor = disabled ? DarkPalette.text3 : DarkPalette.text2;
    final iconColor = value == 'On' ? DarkPalette.primary : DarkPalette.text2;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: DarkPalette.hoverWeak,
        highlightColor: DarkPalette.hoverWeak,
        splashColor: Colors.transparent,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                if (icon != null) ...[
                  SvgIcon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: labelColor),
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 8),
                  Text(value, style: TextStyle(fontSize: 12.5, color: valueColor)),
                ],
                if (chevron) ...[
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 16, color: DarkPalette.text3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 0.5dp hairline between rows.
  Widget _sep() => const Divider(height: 0.5, thickness: 0.5, color: DarkPalette.divider);

  void _close() => Navigator.of(context).pop();

  /// Closes the panel, then pushes [page] from the host (still-mounted) context.
  void _open(Widget page) {
    final host = widget.hostContext;
    _close();
    Navigator.of(host).push(MaterialPageRoute(builder: (BuildContext context) => page));
  }

  void _toast(String message) {
    final host = widget.hostContext;
    _close();
    FlutterToastr.show(message, host);
  }
}

/// Minimal port setting page: reuses the app's [PortWidget] (the same editor
/// used on the settings page) so the port handler stays in one place.
class _PortSettingPage extends StatelessWidget {
  final ProxyServer proxyServer;

  const _PortSettingPage({required this.proxyServer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DarkPalette.bg,
      appBar: AppBar(
        backgroundColor: DarkPalette.panel,
        foregroundColor: DarkPalette.text1,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Proxy Port', style: TextStyle(fontSize: 16)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: DarkPalette.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DarkPalette.divider, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: PortWidget(
            proxyServer: proxyServer,
            textStyle: const TextStyle(fontSize: 14, color: DarkPalette.text1),
          ),
        ),
      ),
    );
  }
}

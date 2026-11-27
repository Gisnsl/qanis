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

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:qanis/l10n/app_localizations.dart';
import 'package:qanis/network/bin/server.dart';
import 'package:qanis/network/components/host_filter.dart';
import 'package:qanis/network/components/manager/hosts_manager.dart';
import 'package:qanis/network/components/manager/request_block_manager.dart';
import 'package:qanis/network/components/manager/request_breakpoint_manager.dart';
import 'package:qanis/network/components/manager/request_rewrite_manager.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/network/util/system_proxy.dart';
import 'package:qanis/storage/histories.dart';
import 'package:qanis/ui/mobile/menu/weak_network_tile.dart';
import 'package:qanis/ui/mobile/setting/hosts.dart';
import 'package:qanis/ui/mobile/setting/request_breakpoint.dart';
import 'package:qanis/ui/mobile/setting/request_map.dart';
import 'package:qanis/ui/mobile/menu/bottom_navigation.dart';
import 'package:qanis/ui/mobile/menu/codec_hub.dart';
import 'package:qanis/ui/toolbox/toolbox.dart';
import 'package:qanis/ui/component/svg_icon.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/ui/configuration.dart';
import 'package:qanis/ui/mobile/setting/preference.dart';
import 'package:qanis/ui/mobile/request/favorite.dart';
import 'package:qanis/ui/mobile/request/history.dart';
import 'package:qanis/ui/mobile/setting/app_filter.dart';
import 'package:qanis/ui/mobile/setting/environment.dart';
import 'package:qanis/ui/mobile/setting/filter.dart';
import 'package:qanis/ui/mobile/setting/mcp.dart';
import 'package:qanis/ui/mobile/setting/request_block.dart';
import 'package:qanis/ui/mobile/setting/request_rewrite.dart';
import 'package:qanis/ui/mobile/setting/request_crypto.dart';
import 'package:qanis/ui/mobile/setting/script.dart';
import 'package:qanis/ui/mobile/setting/ssl.dart';
import 'package:qanis/ui/mobile/widgets/about.dart';
import 'package:qanis/utils/listenable_list.dart';

import '../../component/proxy_port_setting.dart';
import '../../component/widgets.dart';
import '../../desktop/setting/external_proxy.dart';

/// 左侧抽屉
///
/// 视觉参考 Reqable：扁平面板 + 头像头部 + 琥珀色 Desktop App 横幅 +
/// 可折叠的 Tabs / Tools / Others 分组。导航目标与原实现完全一致。
class DrawerWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest> container;

  DrawerWidget({super.key, required this.proxyServer, required this.container});

  @override
  State<DrawerWidget> createState() => _DrawerWidgetState();
}

class _DrawerWidgetState extends State<DrawerWidget> {
  late final HistoryTask historyTask;

  /// 请求数监听（ListenableList 使用自定义 ListenerListEvent 机制）
  late final _RequestCountListener _countListener;

  bool _tabsExpanded = true;
  bool _toolsExpanded = true;
  bool _othersExpanded = true;

  bool _countUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    historyTask = HistoryTask.ensureInstance(widget.proxyServer.configuration, widget.container);
    _countListener = _RequestCountListener(_onRequestsChanged);
    widget.container.addListener(_countListener);
  }

  /// 列表可能在 build 过程中被写入，因此延后到帧结束再刷新计数
  void _onRequestsChanged() {
    if (!mounted || _countUpdateScheduled) return;
    _countUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _countUpdateScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.container.removeListener(_countListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    return Drawer(
      backgroundColor: DarkPalette.panel,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(isCN),
            _buildDesktopAppBanner(context, isCN),
            // Tabs
            _SectionHeader(
              title: isCN ? '标签' : 'Tabs',
              expanded: _tabsExpanded,
              onTap: () => setState(() => _tabsExpanded = !_tabsExpanded),
            ),
            if (_tabsExpanded)
              ..._withHairlines([
                _DrawerItem(
                  icon: 'list',
                  label: '${isCN ? '流量' : 'Traffic'} (${widget.container.length})',
                  active: true,
                  showDot: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ]),
            // Tools
            _SectionHeader(
              title: isCN ? '工具' : 'Tools',
              expanded: _toolsExpanded,
              onTap: () => setState(() => _toolsExpanded = !_toolsExpanded),
            ),
            if (_toolsExpanded)
              ..._withHairlines([
                _DrawerItem(
                  icon: 'favorite',
                  label: localizations.favorites,
                  onTap: () => navigator(context, MobileFavorites(proxyServer: widget.proxyServer)),
                ),
                _DrawerItem(
                  icon: 'history',
                  label: localizations.history,
                  onTap: () => navigator(
                      context,
                      MobileHistory(
                          proxyServer: widget.proxyServer,
                          container: widget.container,
                          historyTask: historyTask)),
                ),
                _DrawerItem(
                  icon: 'encode',
                  label: isCN ? '编解码' : 'Encode / Decode',
                  onTap: () => navigator(context, const CodecHubPage()),
                ),
                _DrawerItem(
                  icon: 'wrench',
                  label: localizations.toolbox,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (BuildContext context) {
                      return Scaffold(
                          appBar: AppBar(title: Text(localizations.toolbox), centerTitle: true),
                          body: Toolbox(proxyServer: widget.proxyServer));
                    }),
                  ),
                ),
                _DrawerItem(
                  icon: widget.proxyServer.enableSsl ? 'lock' : 'ssl',
                  label: localizations.httpsProxy,
                  onTap: () => navigator(context, MobileSslWidget(proxyServer: widget.proxyServer)),
                ),
                _DrawerItem(
                  icon: 'funnel',
                  label: localizations.filter,
                  onTap: () => navigator(context, FilterMenu(proxyServer: widget.proxyServer)),
                ),
                _DrawerItem(
                  icon: 'group_host',
                  label: localizations.hosts,
                  onTap: () async {
                    var hostsManager = await HostsManager.instance;
                    if (context.mounted) {
                      navigator(context, HostsPage(hostsManager: hostsManager));
                    }
                  },
                ),
                _DrawerItem(
                  icon: 'block',
                  label: localizations.requestBlock,
                  onTap: () async {
                    var requestBlockManager = await RequestBlockManager.instance;
                    if (context.mounted) {
                      navigator(context, MobileRequestBlock(requestBlockManager: requestBlockManager));
                    }
                  },
                ),
                _DrawerItem(
                  icon: 'compose',
                  label: localizations.requestRewrite,
                  onTap: () async {
                    var requestRewrites = await RequestRewriteManager.instance;
                    if (context.mounted) {
                      navigator(context, MobileRequestRewrite(requestRewrites: requestRewrites));
                    }
                  },
                ),
                _DrawerItem(
                  icon: 'swap',
                  label: localizations.requestMap,
                  onTap: () => navigator(context, MobileRequestMapPage()),
                ),
                _DrawerItem(
                  icon: 'key',
                  label: localizations.requestCrypto,
                  onTap: () => navigator(context, const MobileRequestCryptoPage()),
                ),
                _DrawerItem(
                  icon: 'code',
                  label: localizations.script,
                  onTap: () => navigator(context, const MobileScript()),
                ),
                _DrawerItem(
                  icon: 'breakpoint',
                  label: localizations.breakpoint,
                  onTap: () async {
                    var manager = await RequestBreakpointManager.instance;
                    if (context.mounted) {
                      navigator(context, MobileRequestBreakpointPage(manager: manager));
                    }
                  },
                ),
                // 弱网模拟：沿用原有组件，行为不变
                const WeakNetworkMenuTile(),
                _DrawerItem(
                  icon: 'globe',
                  label: localizations.environmentVariables,
                  onTap: () => navigator(context, const MobileEnvironmentPage()),
                ),
                _DrawerItem(
                  icon: 'mcp',
                  label: localizations.mcpService,
                  onTap: () => navigator(context, MobileMcpSetting(proxyServer: widget.proxyServer)),
                ),
              ]),
            // Others
            _SectionHeader(
              title: isCN ? '其他' : 'Others',
              expanded: _othersExpanded,
              onTap: () => setState(() => _othersExpanded = !_othersExpanded),
            ),
            if (_othersExpanded)
              ..._withHairlines([
                _DrawerItem(
                  icon: 'sliders',
                  label: localizations.config,
                  onTap: () => navigator(context, ConfigPage(proxyServer: widget.proxyServer)),
                ),
                _DrawerItem(
                  icon: 'gear',
                  label: localizations.setting,
                  onTap: () => navigator(
                      context,
                      futureWidget(
                          AppConfiguration.instance,
                          (appConfiguration) => _SettingPage(
                              proxyServer: widget.proxyServer, appConfiguration: appConfiguration))),
                ),
                _DrawerItem(
                  icon: 'info',
                  label: localizations.about,
                  onTap: () => navigator(context, const About()),
                ),
              ]),
            const SizedBox(height: 24)
          ],
        ),
      ),
    );
  }

  /// 头部：44dp 琥珀色调圆形头像 + 名称 + 副标题
  Widget _buildHeader(bool isCN) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DarkPalette.primary.withValues(alpha: 0.16),
              border: Border.all(color: DarkPalette.primary.withValues(alpha: 0.28), width: 0.5),
            ),
            child: Center(
              child: Image.asset(
                'assets/icon_foreground.png',
                width: 26,
                height: 26,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('QANIS',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DarkPalette.text1,
                        letterSpacing: 0.3)),
                const SizedBox(height: 2),
                Text(isCN ? '安卓流量抓取工具' : 'Traffic capture for Android',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: DarkPalette.text2)),
              ],
            ),
          )
        ],
      ),
    );
  }

  /// 琥珀色 Desktop App 横幅：仅提示，无实际功能
  Widget _buildDesktopAppBanner(BuildContext context, bool isCN) {
    return InkWell(
      onTap: () => FlutterToastr.show(
          isCN ? '本版本不包含桌面端同步' : 'Desktop sync is not part of this build', context),
      splashColor: Colors.transparent,
      highlightColor: Colors.white.withValues(alpha: 0.06),
      child: Ink(
        height: 44,
        color: DarkPalette.primary,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.desktop_windows_outlined, size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(isCN ? '桌面端' : 'Desktop App',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.white)
            ],
          ),
        ),
      ),
    );
  }

  /// 在行之间插入 0.5dp 内缩细线
  List<Widget> _withHairlines(List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(const _Hairline());
      children.add(rows[i]);
    }
    return children;
  }
}

/// 请求数变化监听：ListenableList 使用自定义事件接口
class _RequestCountListener extends ListenerListEvent<HttpRequest> {
  final VoidCallback onChanged;

  _RequestCountListener(this.onChanged);

  @override
  void onAdd(HttpRequest item) => onChanged();

  @override
  void onRemove(HttpRequest item) => onChanged();

  @override
  void onUpdate(HttpRequest item) => onChanged();

  @override
  void onBatchRemove(List<HttpRequest> items) => onChanged();

  @override
  void clear(List<HttpRequest> items) => onChanged();
}

/// 分组标题：11sp 大写灰字 + 折叠箭头
class _SectionHeader extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onTap;

  const _SectionHeader({required this.title, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: DarkPalette.hoverWeak,
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: DarkPalette.text3)),
              ),
              AnimatedRotation(
                turns: expanded ? 0 : -0.25,
                duration: const Duration(milliseconds: 160),
                child: const Icon(Icons.expand_more, size: 18, color: DarkPalette.text3),
              )
            ],
          ),
        ),
      ),
    );
  }
}

/// 导航行：20dp 单色 SVG 图标 + 14sp 文本，54dp 高，选中时左侧 2dp 琥珀条
class _DrawerItem extends StatelessWidget {
  /// assets/icons/<name>.svg 的名称（单色线条图标集）
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool showDot;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: DarkPalette.hoverWeak,
      child: SizedBox(
        height: 54,
        child: Stack(
          children: [
            if (active)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: DarkPalette.primary),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SvgIcon(icon,
                      size: 20, color: active ? DarkPalette.primary : DarkPalette.text2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                            color: DarkPalette.text1)),
                  ),
                  if (showDot)
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          const BoxDecoration(shape: BoxShape.circle, color: DarkPalette.primary),
                    )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 16),
      color: DarkPalette.divider,
    );
  }
}

///跳转页面
void navigator(BuildContext context, Widget widget) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (BuildContext context) {
      return widget;
    }),
  );
}

class _SettingPage extends StatelessWidget {
  final ProxyServer proxyServer;
  final AppConfiguration appConfiguration;

  const _SettingPage({required this.proxyServer, required this.appConfiguration});

  @override
  Widget build(BuildContext context) {
    final configuration = proxyServer.configuration;
    var textEditingController = TextEditingController(text: configuration.proxyPassDomains);

    AppLocalizations localizations = AppLocalizations.of(context)!;
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    Widget section(List<Widget> tiles) => Card(
          color: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
              borderRadius: BorderRadius.circular(10)),
          child: Column(children: tiles),
        );

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: AppBar(
              title: Text(localizations.setting, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              centerTitle: true,
            )),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          // Port and switches
          Card(
              color: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                PortWidget(
                    proxyServer: proxyServer,
                    title: '${localizations.proxy}${isCN ? '' : ' '}${localizations.port}',
                    textStyle: const TextStyle(fontSize: 16)),
                Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                if (Platform.isAndroid)
                  ListTile(
                      title: Text(localizations.systemProxy),
                      trailing: SwitchWidget(
                          value: configuration.enableSystemProxy,
                          scale: 0.8,
                          onChanged: (value) {
                            configuration.enableSystemProxy = value;
                            proxyServer.configuration.flushConfig();
                          })),
                if (Platform.isAndroid)
                  Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: const Text("SOCKS5"),
                    trailing: SwitchWidget(
                        value: configuration.enableSocks5,
                        scale: 0.8,
                        onChanged: (value) {
                          configuration.enableSocks5 = value;
                          proxyServer.configuration.flushConfig();
                        })),
                Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.enabledHTTP2),
                    trailing: SwitchWidget(
                        value: configuration.enabledHttp2,
                        scale: 0.8,
                        onChanged: (value) {
                          configuration.enabledHttp2 = value;
                          proxyServer.configuration.flushConfig();
                        })),
                Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                ListTile(
                    title: Text(localizations.externalProxy),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: () {
                      showDialog(
                          context: context,
                          builder: (_) => ExternalProxyDialog(configuration: proxyServer.configuration));
                    }),
                Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                Padding(
                    padding: const EdgeInsets.only(left: 15),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(localizations.proxyIgnoreDomain, style: const TextStyle(fontSize: 14)),
                          const SizedBox(height: 3),
                          Text(isCN ? "多个使用;分割" : "Use ';' to separate multiple entries",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      )),
                      Padding(
                          padding: const EdgeInsets.only(left: 35),
                          child: TextButton(
                            child: Text(localizations.reset),
                            onPressed: () {
                              textEditingController.text = SystemProxy.proxyPassDomains;
                            },
                          ))
                    ])),
                const SizedBox(height: 5),
                Padding(
                    padding: const EdgeInsets.only(left: 15, right: 5),
                    child: TextField(
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontSize: 13),
                        controller: textEditingController,
                        onSubmitted: (_) {
                          configuration.proxyPassDomains = textEditingController.text;
                          proxyServer.configuration.flushConfig();
                        },
                        decoration:
                            const InputDecoration(contentPadding: EdgeInsets.all(10), border: OutlineInputBorder()),
                        maxLines: 5,
                        minLines: 1)),
                const SizedBox(height: 10),
              ])),
          const SizedBox(height: 12),
          section([
            ListTile(
                title: Text(localizations.preference),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () =>
                    navigator(context, Preference(proxyServer: proxyServer, appConfiguration: appConfiguration))),
            Divider(height: 0, thickness: 0.3, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
            ListTile(
                title: Text(localizations.about),
                trailing: const Icon(Icons.keyboard_arrow_right),
                onTap: () => navigator(context, const About())),
          ]),
          const SizedBox(height: 8),
        ]));
  }
}

///抓包过滤菜单
class FilterMenu extends StatelessWidget {
  final ProxyServer proxyServer;

  const FilterMenu({super.key, required this.proxyServer});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Scaffold(
        appBar: AppBar(title: Text(localizations.filter, style: const TextStyle(fontSize: 16)), centerTitle: true),
        body: Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
                color: Colors.transparent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                      title: Text(localizations.domainWhitelist),
                      trailing: const Icon(Icons.arrow_right),
                      onTap: () => navigator(
                          context,
                          MobileFilterWidget(
                              configuration: proxyServer.configuration, hostList: HostFilter.whitelist))),
                  Divider(height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                  ListTile(
                      title: Text(localizations.domainBlacklist),
                      trailing: const Icon(Icons.arrow_right),
                      onTap: () => navigator(
                          context,
                          MobileFilterWidget(
                              configuration: proxyServer.configuration, hostList: HostFilter.blacklist))),
                  Platform.isIOS
                      ? const SizedBox()
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Divider(
                              height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                          ListTile(
                              title: Text(localizations.appWhitelist),
                              trailing: const Icon(Icons.arrow_right),
                              onTap: () => navigator(context, AppWhitelist(proxyServer: proxyServer))),
                          Divider(
                              height: 0, thickness: 0.4, color: Theme.of(context).dividerColor.withValues(alpha: 0.22)),
                          ListTile(
                              title: Text(localizations.appBlacklist),
                              trailing: const Icon(Icons.arrow_right),
                              onTap: () => navigator(context, AppBlacklist(proxyServer: proxyServer)))
                        ])
                ]))));
  }
}

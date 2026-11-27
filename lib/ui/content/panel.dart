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

import 'dart:convert';
import 'dart:io';

import 'package:qanis/ui/component/multi_window_compat.dart';
import 'package:qanis/ui/content/request_detail_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:qanis/l10n/app_localizations.dart';
import 'package:qanis/network/bin/server.dart';
import 'package:qanis/network/channel/host_port.dart';
import 'package:qanis/network/http/content_type.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/network/http/http_client.dart';
import 'package:qanis/storage/favorites.dart';
import 'package:qanis/ui/component/json/json_text.dart';
import 'package:qanis/ui/component/json/theme.dart';
import 'package:qanis/ui/component/state_component.dart';
import 'package:qanis/ui/component/svg_icon.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/ui/content/web_socket.dart';
import 'package:qanis/ui/content/mqtt.dart';
import 'package:qanis/utils/lang.dart';
import 'package:qanis/utils/platform.dart';

import 'body.dart';
import 'headers.dart';
import 'menu.dart';

///网络请求详情页
///@Author: wanghongen
class NetworkTabController extends StatefulWidget {
  static GlobalKey<NetworkTabState>? currentKey;
  final String? windowId;
  final ProxyServer? proxyServer;
  final ValueWrap<HttpRequest> request = ValueWrap();
  final ValueWrap<HttpResponse> response = ValueWrap();
  final Widget? title;
  final TextStyle? tabStyle;

  /// 初始选中的 tab 下标（默认 0 = 概览）
  final int initialTab;

  NetworkTabController(
      {HttpRequest? httpRequest,
      HttpResponse? httpResponse,
      this.title,
      this.tabStyle,
      this.proxyServer,
      this.windowId,
      this.initialTab = 0})
      : super(key: GlobalKey<NetworkTabState>()) {
    currentKey = key as GlobalKey<NetworkTabState>;
    request.set(httpRequest);
    response.set(httpResponse);
  }

  void change(HttpRequest? request, HttpResponse? response) {
    this.request.set(request);
    this.response.set(response);
    var state = key as GlobalKey<NetworkTabState>;
    state.currentState?.changeState();
  }

  void changeState() {
    var state = key as GlobalKey<NetworkTabState>;
    state.currentState?.changeState();
  }

  ///更新当前详情请求的响应，请求在详情页打开期间完成时刷新响应内容
  void updateResponse(HttpResponse? response) {
    var currentRequest = request.get();
    if (response?.request == null || currentRequest == null) {
      return;
    }
    if (currentRequest.requestId != response!.request!.requestId) {
      return;
    }
    this.response.set(response);
    changeState();
  }

  @override
  State<StatefulWidget> createState() {
    return NetworkTabState();
  }

  static NetworkTabController? get current => currentKey?.currentWidget as NetworkTabController?;
}

class NetworkTabState extends State<NetworkTabController> with TickerProviderStateMixin {
  late List<String> tabs;
  late bool _mqttTabs;

  final TextStyle textStyle = const TextStyle(fontSize: 14);
  late TabController _tabController;

  final GlobalKey<HttpBodyState> requestHttpBodyKey = GlobalKey<HttpBodyState>();
  final GlobalKey<HttpBodyState> responseHttpBodyKey = GlobalKey<HttpBodyState>();

  /// 当前请求的手动收藏状态，按 requestId 缓存避免每次 build 查存储
  String? _favoritedId;
  bool _favorited = false;

  void _checkFavorited(HttpRequest request) {
    if (_favoritedId == request.requestId) return;
    var id = request.requestId;
    FavoriteStorage.favorites.then((favorites) {
      if (!mounted) return;
      setState(() {
        _favoritedId = id;
        _favorited = favorites.any((f) => f.request.requestId == id);
      });
    });
  }

  Future<void> _toggleFavorite(HttpRequest request) async {
    var localizations = AppLocalizations.of(context)!;
    if (_favorited) {
      var favorites = await FavoriteStorage.favorites;
      Favorite? target;
      for (final f in favorites) {
        if (f.request.requestId == request.requestId) {
          target = f;
          break;
        }
      }
      if (target != null) {
        await FavoriteStorage.removeFavorite(target);
      }
      if (!mounted) return;
      setState(() => _favorited = false);
      FlutterToastr.show(localizations.deleteSuccess, context);
    } else {
      await FavoriteStorage.addFavorite(request);
      if (!mounted) return;
      setState(() => _favorited = true);
      FlutterToastr.show(localizations.addSuccess, context);
    }
  }

  void changeState() {
    final mqtt = widget.request.get()?.protocolVersion == 'MQTT';
    if (mqtt != _mqttTabs) {
      _tabController.dispose();
      _configureTabs(mqtt);
    }
    setState(() {});
  }

  void _configureTabs(bool mqtt) {
    _mqttTabs = mqtt;
    tabs = mqtt ? ['General', 'MQTT'] : RequestDetailTabs.resolve();
    _tabController =
        TabController(length: tabs.length, vsync: this, initialIndex: widget.initialTab.clamp(0, tabs.length - 1));
    _tabController.addListener(() {
      if (_tabController.index != 1) {
        requestHttpBodyKey.currentState?.hideSearchOverlay();
      }
      if (_tabController.index != 2) {
        responseHttpBodyKey.currentState?.hideSearchOverlay();
      }
    });
  }

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _configureTabs(widget.request.get()?.protocolVersion == 'MQTT');

    if (widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    bool isMqtt = widget.request.get()?.protocolVersion == 'MQTT';
    bool isWebSocket = widget.request.get()?.isWebSocket == true;
    bool isSse = widget.response.get()?.headers.contentType.toLowerCase().startsWith('text/event-stream') == true;
    bool isStreamMessages = isWebSocket || isSse;
    if (isMqtt) {
      tabs[tabs.length - 1] = 'MQTT';
    } else if (isSse) {
      tabs[tabs.length - 1] = "SSE";
    } else if (isWebSocket) {
      tabs[tabs.length - 1] = "WebSocket";
    } else {
      tabs[tabs.length - 1] = 'Cookies';
    }

    var theme = Theme.of(context);
    var isDesktop = Platforms.isDesktop();
    // 标签条高度固定，下划线/发丝线位置可预测（不依赖 TabBar 自身测量）
    var tabStripHeight = isDesktop ? _detailTabStripHeight : _detailTabStripHeightMobile;

    // ---- Reqable 风格标签条 -------------------------------------------------
    // 选中：13.5sp medium text-1 + 26x2 琥珀色下划线；未选中 text-2；
    // indicatorSize.label 让下划线跟随标签，自定义装饰再把宽度收敛为 26dp 并居中。
    // 标签条始终可横向滚动并左对齐：标签宽度按文案自然测量，一旦超出可用宽度
    // （长本地化文案 / 大字体缩放）就滚动而不是把末尾标签裁掉。
    var tabBar = TabBar(
      padding: const EdgeInsets.only(bottom: 0),
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicator: _ReqableTabIndicator(color: detailPrimaryColor(theme)),
      indicatorSize: TabBarIndicatorSize.label,
      // 标签条底部 0.5px 发丝线
      dividerColor: detailHairlineColor(theme),
      dividerHeight: 0.5,
      // 收紧左右内边距，让更多标签在窄屏上一屏放下
      labelPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 8),
      labelStyle: widget.tabStyle ??
          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: detailText1Color(theme)),
      unselectedLabelStyle: widget.tabStyle ??
          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: detailText2Color(theme)),
      labelColor: detailText1Color(theme),
      unselectedLabelColor: detailText2Color(theme),
      tabs: tabs
          .map((title) =>
              Tab(height: isDesktop ? 34 : 42, child: Text(tabLabel(title), style: widget.tabStyle, maxLines: 1)))
          .toList(),
    );

    var request = widget.request.get();
    // 顶栏底部的 0.5px 发丝线（顶栏与 URL 块之间）
    final headerHairline = Divider(height: _detailHairline, thickness: _detailHairline, color: detailHairlineColor(theme));
    // URL 块 + 标签条的总高度（AppBar.bottom / PreferredSize 需要精确值）
    final urlAndTabsHeight = _detailUrlBlockHeight + tabStripHeight;

    PreferredSizeWidget appBar;
    if (widget.title != null) {
      appBar = AppBar(
        title: widget.title,
        centerTitle: true,
        // 扁平面板顶栏：panel 底 + text-1 前景，无 elevation / 无 surface tint
        backgroundColor: detailPanelColor(theme),
        foregroundColor: detailText1Color(theme),
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
            preferredSize:
                Size.fromHeight(request != null ? urlAndTabsHeight + _detailHairline : tabStripHeight),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (request != null) headerHairline,
              if (request != null) urlBlock(request),
              tabStrip(tabBar, tabStripHeight),
            ])),
        actions: [
          ShareWidget(
              proxyServer: widget.proxyServer, request: widget.request.get(), response: widget.response.get()),
          const SizedBox(width: 3),
          DetailMenuWidget(request: widget.request.get()),
          const SizedBox(width: 10),
        ],
      );
    } else if (widget.windowId == null && Platforms.isDesktop()) {
      if (request == null) {
        // 未选中请求：不展示标题栏和 tab 条，右侧面板留白
        appBar = const PreferredSize(preferredSize: Size.zero, child: SizedBox());
      } else {
        appBar = PreferredSize(
            preferredSize: Size.fromHeight(_detailToolbarHeight + _detailHairline + urlAndTabsHeight),
            child: Container(
                color: detailPanelColor(theme),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  detailTitleBar(request),
                  headerHairline,
                  urlBlock(request),
                  tabStrip(tabBar, tabStripHeight),
                ])));
      }
    } else if (Platforms.isDesktop()) {
      // 桌面子窗口：同主窗口详情，URL 标题栏 + URL 块 + tab 条；
      // 标题栏同时把 tab 条压到 macOS 红绿灯（隐藏式标题栏，悬浮在左上约 72px）之下，
      // 标题栏自身内容也要右移避开红绿灯
      if (request == null) {
        appBar = PreferredSize(
            preferredSize: Size.fromHeight(tabStripHeight),
            child: Container(color: detailPanelColor(theme), child: tabStrip(tabBar, tabStripHeight)));
      } else {
        appBar = PreferredSize(
            preferredSize: Size.fromHeight(_detailToolbarHeight + _detailHairline + urlAndTabsHeight),
            child: Container(
                color: detailPanelColor(theme),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: EdgeInsets.only(left: Platform.isMacOS ? 72 : 0),
                      child: detailTitleBar(request)),
                  headerHairline,
                  urlBlock(request),
                  tabStrip(tabBar, tabStripHeight),
                ])));
      }
    } else {
      // 手机端无标题栏分支：URL 块 + 标签条
      if (request == null) {
        appBar = PreferredSize(
            preferredSize: Size.fromHeight(tabStripHeight),
            child: Container(color: detailPanelColor(theme), child: tabStrip(tabBar, tabStripHeight)));
      } else {
        appBar = PreferredSize(
            preferredSize: Size.fromHeight(urlAndTabsHeight),
            child: Container(
                color: detailPanelColor(theme),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  urlBlock(request),
                  tabStrip(tabBar, tabStripHeight),
                ])));
      }
    }

    // 底部 Request/Response 切换：仅普通 HTTP 详情（tabs 含 Request/Response）时显示
    var showBottomToggle =
        request != null && !isMqtt && tabs.contains('Request') && tabs.contains('Response');

    return Scaffold(
      endDrawerEnableOpenDragGesture: false,
      // 桌面端详情区用设计稿 --bg 底色
      backgroundColor: isDesktop ? detailSurfaceColor(theme) : null,
      appBar: appBar,
      body: Column(children: [
        Expanded(
            child: Padding(
                padding: EdgeInsets.only(
                    left: isDesktop ? 16 : 20, right: isDesktop ? 16 : 20, top: isDesktop ? 14 : 10),
                child: isDesktop && request == null
                    ? const SizedBox() // 未选中请求：空白，不渲染 tab 内容
                    : TabBarView(
                        physics: Platforms.isDesktop() ? const NeverScrollableScrollPhysics() : null, //桌面禁止滑动
                        controller: _tabController,
                        children: isMqtt
                            ? [
                                SelectionArea(child: Overview(widget.request, widget.response)),
                                SelectionArea(child: MqttMessages(widget.request)),
                              ]
                            : [
                                SelectionArea(child: Overview(widget.request, widget.response)),
                                KeepAliveWrapper(child: this.request()),
                                KeepAliveWrapper(child: this.response()),
                                SelectionArea(
                                    child: isStreamMessages
                                        ? Websocket(widget.request, widget.response)
                                        : Cookies(widget.request, widget.response)),
                              ],
                      ))),
        if (showBottomToggle) bottomToggle(),
      ]),
    );
  }

  /// 标签条容器：固定高度并底部对齐，使 26x2 下划线与发丝线紧贴标签条底边，
  /// 顶栏 preferredSize 也据此精确计算，不依赖 TabBar 的自身测量。
  Widget tabStrip(Widget tabBar, double stripHeight) => SizedBox(
      height: stripHeight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Spacer(), tabBar]));

  /// Reqable 风格 URL 块：panel 底、16dp 左内边距、等宽 13sp、最多 2 行省略。
  /// scheme://host 用主色，path/query 用 text-2，右侧一个复制按钮。
  Widget urlBlock(HttpRequest request) {
    var theme = Theme.of(context);
    var url = request.requestUrl;

    // 按原始文本切分 scheme://authority 与 path/query，避免 Uri 归一化改写大小写
    var schemeHost = '';
    var rest = url;
    var sep = url.indexOf('://');
    if (sep > 0) {
      var authorityEnd = url.length;
      for (var k = sep + 3; k < url.length; k++) {
        var c = url[k];
        if (c == '/' || c == '?' || c == '#') {
          authorityEnd = k;
          break;
        }
      }
      schemeHost = url.substring(0, authorityEnd);
      rest = url.substring(authorityEnd);
      if (rest.isEmpty) rest = '/';
    }
    try {
      rest = Uri.decodeFull(rest);
    } catch (_) {}

    return Container(
        height: _detailUrlBlockHeight,
        color: detailPanelColor(theme),
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(children: [
          Expanded(
              child: SelectionArea(
                  child: Text.rich(
                      TextSpan(children: [
                        if (schemeHost.isNotEmpty)
                          TextSpan(
                              text: schemeHost,
                              style: TextStyle(color: detailPrimaryColor(theme), fontWeight: FontWeight.w600)),
                        TextSpan(text: rest, style: TextStyle(color: detailText2Color(theme))),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.3)))),
          const SizedBox(width: 4),
          miniAction(
              tooltip: localizations.copyUrl,
              icon: 'copy',
              color: text3Color(theme),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: request.requestUrl)).then((_) {
                  if (mounted) FlutterToastr.show(localizations.copied, context);
                });
              }),
        ]));
  }

  /// 底部 Request/Response 切换条：48dp、panel 底、顶部发丝线、等分两半。
  /// 只是切换既有的 Request(1)/Response(2) tab，数据来源与原来完全一致。
  Widget bottomToggle() {
    var theme = Theme.of(context);
    return AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          var index = _tabController.index;
          return Container(
              decoration: BoxDecoration(
                  color: detailPanelColor(theme),
                  border: Border(top: BorderSide(color: detailHairlineColor(theme), width: _detailHairline))),
              // 手机端避开底部手势条；桌面端 inset 为 0，布局不变
              child: SafeArea(
                  top: false,
                  child: SizedBox(
                      height: 48,
                      child: Row(children: [
                        Expanded(
                            child: bottomToggleHalf(
                                '↑ ${localizations.request}', index == 1, () => selectDetailTab(1))),
                        Expanded(
                            child: bottomToggleHalf(
                                '↓ ${localizations.response}', index == 2, () => selectDetailTab(2))),
                      ]))));
        });
  }

  /// 切换条的一半：选中主色、未选中 text-3；点击走 TabController.animateTo
  Widget bottomToggleHalf(String label, bool active, VoidCallback onTap) {
    var theme = Theme.of(context);
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            hoverColor: theme.brightness == Brightness.dark ? DarkPalette.hover : null,
            child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? detailPrimaryColor(theme) : text3Color(theme))))));
  }

  void selectDetailTab(int index) {
    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  /// 设计稿 .dp-panel：桌面端请求/响应/Cookies tab 内容包白卡片（圆角 10 + 边框）
  Widget detailCard(Widget child) {
    if (!Platforms.isDesktop()) {
      return child; // 手机端保持平铺
    }
    var theme = Theme.of(context);
    return Container(
        decoration: BoxDecoration(
            color: detailSurfaceColor(theme),
            border: Border.all(color: cardBorderColor(theme), width: _detailHairline),
            borderRadius: BorderRadius.circular(10)),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child));
  }

  Widget request() {
    if (widget.request.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController(); //处理body也有滚动条问题
    // 路径带查询参数（pathAndQuery），下方「查询参数」分区仍提供逐项解析
    var path = widget.request.get()?.pathAndQuery ?? '';
    try {
      path = Uri.decodeFull(path);
    } catch (_) {}

    return detailCard(SingleChildScrollView(
        controller: scrollController,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          overviewRow(context, localizations.path, path),
          RequestParams(widget.request),
          ...message(widget.request.get(), "Request", scrollController)
        ])));
  }

  Widget response() {
    if (widget.response.get() == null) {
      return const SizedBox();
    }

    var scrollController = ScrollController();
    return detailCard(SingleChildScrollView(
        controller: scrollController,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 设计稿：状态码值按状态码语义色（200 绿）
          overviewRow(context, localizations.statusCode, widget.response.get()?.status.toString(),
              valueColor: statusColor(widget.response.get()?.status.code, Theme.of(context))),
          ...message(widget.response.get(), "Response", scrollController)
        ])));
  }

  String tabLabel(String title) {
    switch (title) {
      case 'General':
        return localizations.overview;
      case 'Request':
        return localizations.request;
      case 'Response':
        return localizations.response;
      default:
        return title; // Cookies / WebSocket / SSE / MQTT 保持原文
    }
  }

  /// 扁平面板顶栏：方法徽标 + 操作按钮（URL 交给下方独立的 URL 块展示，避免重复两遍）
  Widget detailTitleBar(HttpRequest request) {
    var theme = Theme.of(context);
    return Container(
        height: _detailToolbarHeight,
        color: detailPanelColor(theme),
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(children: [
          Text(request.method.name.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: request.isWebSocket == true
                      // 设计稿 --ws：浅色 #6E3FC1，暗黑 #9B72E0
                      ? (theme.brightness == Brightness.light ? const Color(0xFF6E3FC1) : DarkPalette.ws)
                      : methodColor(request.method, theme))),
          const Spacer(),
          const SizedBox(width: 4),
          miniAction(
              tooltip: localizations.copyUrl,
              icon: 'copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: request.requestUrl)).then((_) {
                  if (mounted) FlutterToastr.show(localizations.copied, context);
                });
              }),
          miniAction(
              tooltip: localizations.repeat, icon: 'refresh', onPressed: () => resendRequest(request)),
          Builder(builder: (context) {
            _checkFavorited(request);
            var favorited = _favoritedId == request.requestId && _favorited;
            // 已收藏：琥珀色实心星（Material filled）；未收藏：中性灰线条星（设计 SVG）
            var amber = Theme.of(context).brightness == Brightness.light ? const Color(0xFFB76E00) : DarkPalette.warn;
            return miniAction(
                tooltip: localizations.favorite,
                icon: 'star',
                iconWidget: favorited ? Icon(Icons.star, size: 16, color: amber) : null,
                onPressed: () => _toggleFavorite(request));
          }),
        ]));
  }

  /// 设计稿 .mini：26x26 灰色小图标按钮（iconWidget 优先于 icon，用于实心/自定义图标）
  Widget miniAction(
      {required String tooltip,
      required String icon,
      required VoidCallback onPressed,
      Color? color,
      Widget? iconWidget}) {
    return Tooltip(
        message: tooltip,
        child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed,
            child: SizedBox(
                width: 26,
                height: 26,
                child: Center(
                    child: iconWidget ?? SvgIcon(icon, size: 15, color: color ?? detailText2Color(Theme.of(context)))))));
  }

  void resendRequest(HttpRequest httpRequest) {
    var proxyServer = widget.proxyServer;
    var proxyInfo = proxyServer != null && proxyServer.isRunning
        ? ProxyInfo.of("127.0.0.1", proxyServer.port)
        : null;
    HttpClients.proxyRequest(httpRequest.copy(uri: httpRequest.requestUrl), proxyInfo: proxyInfo);
    FlutterToastr.show(localizations.reSendRequest, context, rootNavigator: true);
  }

  List<Widget> message(HttpMessage? message, String type, ScrollController scrollController) {
    Widget bodyWidgets = HttpBodyWidget(
        key: type == "Request" ? requestHttpBodyKey : responseHttpBodyKey,
        hideRequestRewrite: widget.windowId != null,
        httpMessage: message,
        scrollController: scrollController);

    return [
      HeadersWidget(title: type, message: message, valueTextStyle: textStyle),
      // 卡片内统一 14px 水平内边距（设计稿 .kv/.d-sec padding 14）
      // body/raw 查看器容器：仅换底色（--bg）与发丝描边，查看器自身行为不变
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
              decoration: BoxDecoration(
                  color: detailSurfaceColor(Theme.of(context)),
                  border: Border.all(color: detailHairlineColor(Theme.of(context)), width: _detailHairline),
                  borderRadius: BorderRadius.circular(6)),
              child: ClipRRect(borderRadius: BorderRadius.circular(6), child: bodyWidgets))),
    ];
  }
}

/// 详情页顶栏/URL 块/切换条等“面板”表面：暗黑用设计稿 --panel，浅色沿用主题 surface
Color detailPanelColor(ThemeData theme) =>
    theme.brightness == Brightness.dark ? DarkPalette.panel : theme.colorScheme.surface;

/// 详情页内容底色（body/raw 查看器、卡片容器）：暗黑用设计稿 --bg，浅色沿用主题 surface
Color detailSurfaceColor(ThemeData theme) =>
    theme.brightness == Brightness.dark ? DarkPalette.bg : theme.colorScheme.surface;

/// 主文字色：暗黑 --text-1
Color detailText1Color(ThemeData theme) =>
    theme.brightness == Brightness.dark ? DarkPalette.text1 : theme.colorScheme.onSurface;

/// 次要文字色：暗黑 --text-2
Color detailText2Color(ThemeData theme) =>
    theme.brightness == Brightness.dark ? DarkPalette.text2 : theme.colorScheme.onSurfaceVariant;

/// 强调色（琥珀）：暗黑 --primary
Color detailPrimaryColor(ThemeData theme) =>
    theme.brightness == Brightness.dark ? DarkPalette.primary : theme.colorScheme.primary;

/// 发丝分隔线：暗黑 --divider
Color detailHairlineColor(ThemeData theme) =>
    theme.brightness == Brightness.dark ? DarkPalette.divider : theme.dividerColor;

/// 详情页顶栏高度（方法徽标 + 操作按钮一行）
const double _detailToolbarHeight = 44;

/// URL 块高度（13sp 等宽两行 + 上下留白 ≈ 16dp 视觉内边距）
const double _detailUrlBlockHeight = 58;

/// 标签条高度（桌面：34dp 标签 + 上方留白）
const double _detailTabStripHeight = 46;

/// 标签条高度（手机：42dp 标签 + 上方留白）
const double _detailTabStripHeightMobile = 50;

/// 发丝线宽度（0.5dp）
const double _detailHairline = 0.5;

/// Reqable 风格标签下划线：固定 26x2dp 圆角横条，水平居中贴标签底部。
/// 配合 TabBarIndicatorSize.label 使用，把默认“整条标签宽”的下划线收敛成固定宽度。
class _ReqableTabIndicator extends Decoration {
  final Color color;
  final double width;
  final double height;
  final Radius radius;

  const _ReqableTabIndicator({
    required this.color,
    this.width = 26,
    this.height = 2,
    this.radius = const Radius.circular(1),
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _ReqableTabIndicatorPainter(this, onChanged);
}

class _ReqableTabIndicatorPainter extends BoxPainter {
  final _ReqableTabIndicator decoration;

  _ReqableTabIndicatorPainter(this.decoration, VoidCallback? onChanged) : super(onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) {
      return;
    }
    final barWidth = decoration.width < size.width ? decoration.width : size.width;
    final rect = Rect.fromLTWH(offset.dx + (size.width - barWidth) / 2,
        offset.dy + size.height - decoration.height, barWidth, decoration.height);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, decoration.radius), Paint()..color = decoration.color);
  }
}

/// 设计稿 --text-3：浅色 #8F959E，暗黑 #6F747D
Color text3Color(ThemeData theme) =>
    theme.brightness == Brightness.light ? const Color(0xFF8F959E) : DarkPalette.text3;

/// 设计稿 行 hover（.row:hover / .rl-row:hover）：浅色 #F7F8FA，暗黑 --hover-weak #2A2D33
Color rowHoverColor(ThemeData theme) =>
    theme.brightness == Brightness.light ? const Color(0xFFF7F8FA) : DarkPalette.hoverWeak;

/// 设计稿 .kv 行之间的 #F2F3F5 细分隔线
Widget kvDivider(BuildContext context) {
  return Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.35));
}

/// 可折叠分区小标题（Cookies/Query 参数共用）：文字 + 尾部 chevron，折叠时显示条数；整行 hover 效果
Widget collapsibleSectionLabel(BuildContext context, String label, int count, bool expanded, VoidCallback onTap) {
  var theme = Theme.of(context);
  var text3 = text3Color(theme);
  var style = TextStyle(fontSize: 14, height: 1.5, letterSpacing: 0.3, color: text3);
  return InkWell(
      onTap: onTap,
      // 整行 hover 焦点效果：设计稿行 hover #F7F8FA
      hoverColor: rowHoverColor(theme),
      child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, top: 10, bottom: 4),
          child: Row(children: [
            Text(label, style: style),
            const SizedBox(width: 2),
            Icon(expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 16, color: text3),
            if (!expanded && count > 0) Text(' · $count', style: style),
          ])));
}

class RequestParams extends StatefulWidget {
  /// 展开状态跨请求保持（旧版行为）：默认折叠，点开一个详情的折叠/展开对后续详情生效
  static bool initiallyExpanded = false;

  final ValueWrap<HttpRequest> request;

  const RequestParams(this.request, {super.key});

  @override
  State<RequestParams> createState() => _RequestParamsState();
}

class _RequestParamsState extends State<RequestParams> {
  @override
  Widget build(BuildContext context) {
    var request = widget.request.get();
    if (request == null) {
      return const SizedBox();
    }
    var params = request.requestUri?.queryParametersAll;
    if (params == null || params.isEmpty) {
      return const SizedBox();
    }
    var content = <Widget>[];
    var count = 0;
    params.forEach((name, values) {
      for (var val in values) {
        if (content.isNotEmpty) {
          content.add(kvDivider(context));
        }
        content.add(overviewRow(context, name, val));
        count++;
      }
    });

    var expanded = RequestParams.initiallyExpanded;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 与 Cookies 同款可折叠小标题：chevron + 折叠时显示条数
      collapsibleSectionLabel(context, AppLocalizations.of(context)!.queryParams, count, expanded, () {
        setState(() => RequestParams.initiallyExpanded = !expanded);
      }),
      if (expanded) ...content,
    ]);
  }
}

class Overview extends StatefulWidget {
  final ValueWrap<HttpRequest> request;

  final ValueWrap<HttpResponse> response;

  const Overview(this.request, this.response, {super.key});

  @override
  State<Overview> createState() => _OverviewState();
}

class _OverviewState extends State<Overview> {
  final GlobalKey _infoCardKey = GlobalKey();

  /// 信息卡实测高度；首帧为 null，post-frame 测量后更新
  double? _infoCardHeight;

  void _scheduleMeasureInfoCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderBox = _infoCardKey.currentContext?.findRenderObject();
      if (renderBox is RenderBox && renderBox.hasSize && mounted) {
        final height = renderBox.size.height;
        if (height != _infoCardHeight) {
          setState(() => _infoCardHeight = height);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    var request = widget.request.get();
    if (request == null) {
      return const SizedBox();
    }
    var localizations = AppLocalizations.of(context)!;
    var response = widget.response.get();
    String requestUrl = request.requestUrl;
    try {
      requestUrl = Uri.decodeFull(request.requestUrl);
    } catch (_) {}
    if (request.protocolVersion == 'MQTT') {
      return Container(
          color: detailSurfaceColor(Theme.of(context)),
          child: ListView(padding: const EdgeInsets.only(top: 2, bottom: 12), children: [
            overviewCard(context, [
              overviewRow(context, 'Connection', requestUrl),
              overviewRow(context, 'Protocol', 'MQTT over TLS'),
              overviewRow(context, 'Packets', request.messages.length.toString()),
              overviewRow(context, 'Start Time', request.requestTime.formatMillisecond()),
              if (request.processInfo != null) overviewRow(context, 'App', request.processInfo!.name),
            ])
          ]));
    }

    // 设计稿 Overview 卡：状态码/协议/耗时/大小/远程地址/请求时间/App 七行（桌面端严格对齐）；
    // URL/方法/双 Content-Type 仅手机端 General 保留（桌面端 URL+方法已在顶部标题栏，类型见 Body 分区标签）
    var isDesktop = Platforms.isDesktop();
    return LayoutBuilder(builder: (context, constraints) {
      _scheduleMeasureInfoCard();
      // 预览吃掉信息卡之外的全部剩余视口高度；首帧未测出信息卡高度时用比例公式兜底
      final previewMaxHeight =
          responsePreviewMaxHeight(constraints.maxHeight, infoCardHeight: _infoCardHeight);
      return Container(
          color: detailSurfaceColor(Theme.of(context)),
          child: ListView(padding: const EdgeInsets.only(top: 2, bottom: 12), children: [
            overviewCard(context, [
              overviewRow(context, localizations.statusCode, response?.status.toString(),
                  valueColor: statusColor(response?.status.code, Theme.of(context))),
              overviewRow(context, localizations.protocol, request.protocolVersion),
              overviewRow(context, localizations.duration, _durationText(response)),
              overviewRow(context, localizations.size, _sizeText(context, request, response)),
              overviewRow(context, localizations.remoteAddress,
                  '${response?.remoteHost ?? ''}${response?.remotePort == null ? '' : ':${response?.remotePort}'}'),
              overviewRow(context, localizations.requestTime, request.requestTime.formatMillisecond()),
              if (request.processInfo != null) overviewRow(context, localizations.app, request.processInfo!.name),
              if (!isDesktop) ...[
                overviewRow(context, localizations.requestUrl, requestUrl),
                overviewRow(context, localizations.requestMethod, request.method.name),
                overviewRow(context, localizations.requestType, request.headers.contentType),
                overviewRow(context, localizations.responseType, response?.headers.contentType),
              ],
            ], key: _infoCardKey),
            if (response != null && (response.body?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              ResponsePreviewCard(response, maxHeight: previewMaxHeight),
            ],
          ]));
    });
  }
}

/// 响应体预览在矮窗口下的最小限高，再小则由卡片内部滚动承接、外层 ListView 滚动
const double _previewMinHeight = 120;

/// 信息卡之外的固定垂直开销：ListView 上下内边距(2+12)、卡间距(12)、预览卡头(36+1)
const double _overviewChromeHeight = 2 + 12 + 12 + 36 + 1;

/// 计算响应体预览（卡片内部滚动区）限高。
///
/// 已测出 [infoCardHeight] 时：预览占掉信息卡之外的全部剩余视口高度，消除底部留白；
/// 首帧未测出（null）或高度无界时回退到视口 45%、夹在 [_previewMinHeight] 与
/// [ResponsePreviewCard.maxHeightCap] 之间的兜底值。
double responsePreviewMaxHeight(double viewportHeight, {double? infoCardHeight}) {
  if (!viewportHeight.isFinite) {
    return ResponsePreviewCard.maxHeightCap;
  }
  if (infoCardHeight == null) {
    return (viewportHeight * 0.45).clamp(_previewMinHeight, ResponsePreviewCard.maxHeightCap);
  }
  final remaining = viewportHeight - infoCardHeight - _overviewChromeHeight;
  return remaining.clamp(_previewMinHeight, viewportHeight);
}

/// 设计稿 Overview 耗时长："342 ms"（数值与单位间空格；costTime 原始格式 "84ms"/"1.23s"）
String? _durationText(HttpResponse? response) {
  var cost = response?.costTime();
  if (cost == null || cost.isEmpty) {
    return cost;
  }
  return cost.replaceAllMapped(RegExp(r'(\d)(ms|s)$'), (m) => '${m[1]} ${m[2]}');
}

/// 设计稿 Overview 大小行：请求 1.2 KB · 响应 8.6 KB (gzip)
String _sizeText(BuildContext context, HttpRequest request, HttpResponse? response) {
  var localizations = AppLocalizations.of(context)!;
  var reqSize = _kbText(request.packageSize);
  var respSize = _kbText(response?.packageSize);
  if (respSize.isEmpty) {
    return '${localizations.request} $reqSize';
  }
  var text = '${localizations.request} $reqSize · ${localizations.response} $respSize';
  if (response?.headers.isGzip == true) {
    text += ' (gzip)';
  }
  return text;
}

/// 1.2 KB / 8.6 KB 风格（去除多余的 0）
String _kbText(int? size) {
  if (size == null) {
    return '';
  }
  if (size < 1025) {
    return '$size B';
  }
  if (size > 1024 * 1024) {
    var mb = size / 1024 / 1024;
    return '${mb.toStringAsFixed(mb == mb.roundToDouble() ? 0 : 1)} MB';
  }
  var kb = size / 1024;
  return '${kb.toStringAsFixed(kb == kb.roundToDouble() ? 0 : 1)} KB';
}

/// 手机端详情 AppBar 标题（设计稿 .p-ptitle）：METHOD（语义色加粗）+ host/path，单行省略
Widget mobileDetailTitle(BuildContext context, HttpRequest request) {
  var theme = Theme.of(context);
  // 收藏/历史从 JSON 恢复时 hostAndPort 不持久化（为 null），退回 remoteDomain() 解析 uri
  var host = request.hostAndPort?.toString() ?? request.remoteDomain() ?? '';
  return Text.rich(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      TextSpan(children: [
        TextSpan(
            text: '${request.method.name} ',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: methodColor(request.method, theme))),
        TextSpan(text: '$host${request.pathAndQuery}', style: const TextStyle(fontSize: 15)),
      ]));
}

/// 卡片描边色：浅色在设计稿 --border 基础上降透明度弱化；暗黑直接用设计稿 --border（深底上对比已足够低）
Color cardBorderColor(ThemeData theme) =>
    theme.brightness == Brightness.light ? theme.dividerColor.withValues(alpha: 0.6) : theme.dividerColor;

/// 方法颜色按设计稿：浅色 --get #1F8B4C / --post #B76E00 / --put #0E6BB8 / --delete #C4321F；
/// 暗黑对应 --get #3FB96A / --post #E8A33D / --put #4C9BE8 / --delete #E35B48
Color methodColor(HttpMethod method, ThemeData theme) {
  bool dark = theme.brightness == Brightness.dark;
  switch (method) {
    case HttpMethod.get:
      return dark ? DarkPalette.ok : const Color(0xFF1F8B4C);
    case HttpMethod.post:
      return dark ? DarkPalette.warn : const Color(0xFFB76E00);
    case HttpMethod.put:
      return dark ? DarkPalette.put : const Color(0xFF0E6BB8);
    case HttpMethod.delete:
      return dark ? DarkPalette.err : const Color(0xFFC4321F);
    default:
      return theme.colorScheme.onSurfaceVariant;
  }
}

/// 状态码颜色同方法色：2xx 绿 / 3xx 橙 / 其余红，暗黑用设计稿高亮版
Color? statusColor(int? status, ThemeData theme) {
  if (status == null) {
    return null;
  }
  bool dark = theme.brightness == Brightness.dark;
  if (status >= 200 && status < 300) {
    return dark ? DarkPalette.ok : const Color(0xFF1F8B4C);
  }
  if (status >= 300 && status < 400) {
    return dark ? DarkPalette.warn : const Color(0xFFB76E00);
  }
  return dark ? DarkPalette.err : const Color(0xFFC4321F);
}

Widget overviewCard(BuildContext context, List<Widget> rows, {Key? key}) {
  var theme = Theme.of(context);
  var children = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) {
      children.add(Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.35)));
    }
    children.add(rows[i]);
  }
  return Container(
      key: key,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cardBorderColor(theme), width: _detailHairline),
          color: detailSurfaceColor(theme)),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Column(children: children)));
}

Widget overviewRow(BuildContext context, String label, String? value, {Color? valueColor}) {
  var theme = Theme.of(context);
  return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 13, height: 1.5, color: text3Color(theme)))),
        Expanded(
            child: SelectableText(value ?? '',
                contextMenuBuilder: contextMenu,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                    color: valueColor ?? detailText1Color(theme)))),
      ]));
}

/// Overview 响应体预览卡（设计稿 .code-card）：卡头 Response Body + JSON/Raw/Preview 分段，限高内部滚动
class ResponsePreviewCard extends StatefulWidget {
  /// 首帧信息卡高度未测出、或无界高度时的兜底限高；正常布局下预览会填满剩余视口，不受此值限制
  static const double maxHeightCap = 520;

  final HttpResponse response;

  final double maxHeight;

  const ResponsePreviewCard(this.response, {super.key, this.maxHeight = maxHeightCap});

  @override
  State<ResponsePreviewCard> createState() => _ResponsePreviewCardState();
}

class _ResponsePreviewCardState extends State<ResponsePreviewCard> {
  late final List<String> views;
  int viewIndex = 0;

  @override
  void initState() {
    super.initState();
    views = [
      if (_isImage()) 'Preview',
      if (_isJson()) 'JSON',
      if (!_isImage()) 'Raw',
    ];
  }

  bool _isImage() => widget.response.contentType == ContentType.image;

  bool _isJson() {
    if (widget.response.contentType == ContentType.json) return true;
    var body = widget.response.getBodyString();
    var trimmed = body.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cardBorderColor(theme), width: _detailHairline),
            color: detailSurfaceColor(theme)),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  height: 36,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(children: [
                        Text(AppLocalizations.of(context)!.responseBody,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        const Spacer(),
                        for (var i = 0; i < views.length; i++) fmtButton(i),
                      ]))),
              Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.35)),
              ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: SizedBox(width: double.infinity, child: bodyView()))),
            ])));
  }

  /// 设计稿 .fmt 分段小胶囊（选中底色由 Material 绘制，hover/水波纹可见）
  Widget fmtButton(int index) {
    var theme = Theme.of(context);
    var selected = index == viewIndex;
    return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Material(
            color: selected ? primarySoftBg(theme, lightAlpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
                borderRadius: BorderRadius.circular(5),
                // 设计稿小控件 hover：浅色 #F0F1F3，暗黑 --hover #31343B
                hoverColor: theme.brightness == Brightness.light ? const Color(0xFFF0F1F3) : DarkPalette.hover,
                onTap: () => setState(() => viewIndex = index),
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(views[index],
                        style: TextStyle(
                            fontSize: 11,
                            color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant))))));
  }

  Widget bodyView() {
    var view = views[viewIndex];
    if (view == 'Preview' && _isImage()) {
      return Center(
          child: Image.memory(Uint8List.fromList(widget.response.body ?? []), fit: BoxFit.scaleDown));
    }
    return futureWidget(widget.response.decodeBodyString(), (body) {
      if (view == 'JSON') {
        try {
          return JsonText(
              json: json.decode(body),
              indent: '  ',
              colorTheme: ColorTheme.of(context),
              contextMenuBuilder: contextMenu);
        } catch (_) {
          // 解析失败回退 Raw
        }
      }
      return SelectableText(body,
          contextMenuBuilder: contextMenu,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5));
    }, initialData: widget.response.getBodyString());
  }
}

class Cookies extends StatefulWidget {
  final ValueWrap<HttpRequest> request;

  final ValueWrap<HttpResponse> response;

  const Cookies(this.request, this.response, {super.key});

  @override
  State<Cookies> createState() => _CookiesState();
}

class _CookiesState extends State<Cookies> {
  /// 请求/响应 Cookies 分区默认展开，点击小标题折叠；
  /// 展开状态跨请求保持（同 RequestParams.initiallyExpanded / HeadersWidget._lastExpanded 手法）
  static bool _requestExpanded = true;
  static bool _responseExpanded = true;

  /// 请求 Cookie 个数：headers.cookies 是原始 Cookie 头行（通常 1 行含全部 cookie），
  /// 需按 ';' 拆开数键值对，否则折叠条数恒为行数（与展开后的行数对不上）
  int _requestCookieCount(List<String>? headerLines) {
    if (headerLines == null) return 0;
    var count = 0;
    for (final line in headerLines) {
      count += line.split(';').where((e) => e.contains('=')).length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    var requestCookies = widget.request.get()?.cookies;
    var responseCookies = widget.response.get()?.headers.getList("Set-Cookie");

    var requestRows = requestCookies?.expand((cookie) => _cookieWidget(context, cookie)!).toList();
    var responseRows = responseCookies?.expand((e) => _cookieWidget(context, e)!).toList();

    var localizations = AppLocalizations.of(context)!;
    var content = ListView(children: [
      if (requestRows != null) ...[
        collapsibleSectionLabel(context, localizations.requestCookies, _requestCookieCount(requestCookies),
            _requestExpanded, () => setState(() => _requestExpanded = !_requestExpanded)),
        if (_requestExpanded) ...requestRows,
      ],
      if (responseRows != null) ...[
        collapsibleSectionLabel(context, localizations.responseCookies, responseCookies?.length ?? 0,
            _responseExpanded, () => setState(() => _responseExpanded = !_responseExpanded)),
        if (_responseExpanded) ...responseRows,
      ],
    ]);

    if (!Platforms.isDesktop()) {
      return content;
    }
    var theme = Theme.of(context);
    return Container(
        decoration: BoxDecoration(
            color: detailSurfaceColor(theme),
            border: Border.all(color: cardBorderColor(theme), width: _detailHairline),
            borderRadius: BorderRadius.circular(10)),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: content));
  }

  Iterable<Widget>? _cookieWidget(BuildContext context, String? cookie) {
    var headers = <Widget>[];

    cookie?.split(";").map((e) => Strings.splitFirst(e, "=")).where((element) => element != null).forEach((e) {
      if (headers.isNotEmpty) {
        headers.add(kvDivider(context));
      }
      headers.add(overviewRow(context, e!.key.trim(), e.value));
    });

    return headers;
  }
}

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
import 'package:flutter/services.dart';
import 'package:qanis/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:qanis/network/bin/server.dart';
import 'package:qanis/network/components/manager/request_rewrite_manager.dart';
import 'package:qanis/network/components/manager/rewrite_rule.dart';
import 'package:qanis/network/components/manager/script_manager.dart';
import 'package:qanis/network/channel/host_port.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/network/http/http_client.dart';
import 'package:qanis/network/util/cache.dart';
import 'package:qanis/storage/favorites.dart';
import 'package:qanis/ui/component/multi_select_controller.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/ui/component/widgets.dart';
import 'package:qanis/ui/configuration.dart';
import 'package:qanis/ui/content/code_snippet.dart';
import 'package:qanis/ui/content/panel.dart';
import 'package:qanis/ui/desktop/request/request.dart';
import 'package:qanis/ui/mobile/request/repeat.dart';
import 'package:qanis/utils/replay_task.dart';
import 'package:qanis/ui/mobile/request/request_editor.dart';
import 'package:qanis/ui/mobile/setting/request_rewrite.dart';
import 'package:qanis/ui/mobile/setting/script.dart';
import 'package:qanis/utils/curl.dart';
import 'package:qanis/utils/keyword_highlight.dart';
import 'package:qanis/utils/lang.dart';
import 'package:qanis/utils/navigator.dart';
import 'package:shared_preferences/shared_preferences.dart';

///请求行
class RequestRow extends StatefulWidget {
  final int index;
  final HttpRequest request;
  final ProxyServer proxyServer;
  final bool displayDomain;
  final Function(HttpRequest)? onRemove;
  final MultiSelectController selectionController;
  final RequestSelectionHandlers selectionHandlers;
  final Function(VoidCallback refresh)? onMount; // 注册刷新回调
  final VoidCallback? onUnmount; // 注销刷新回调

  const RequestRow({
    super.key,
    required this.request,
    required this.proxyServer,
    this.displayDomain = true,
    this.onRemove,
    required this.selectionController,
    required this.index,
    required this.selectionHandlers,
    this.onMount,
    this.onUnmount,
  });

  @override
  State<StatefulWidget> createState() {
    return RequestRowState();
  }
}

class RequestRowState extends State<RequestRow> {
  static ExpiringCache<String, Image> imageCache = ExpiringCache<String, Image>(const Duration(minutes: 5));
  static const int maxAutoReadEntries = 5000;
  static LruCacheSet<String> autoReadRequests = LruCacheSet<String>(5000);

  static bool markAutoRead(String requestId) {
    return autoReadRequests.add(requestId);
  }

  static void removeAutoReadByIds(Iterable<String> requestIds) {
    autoReadRequests.removeAll(requestIds);
  }

  late HttpRequest request;
  HttpResponse? response;
  bool selected = false;
  Color? highlightColor; //高亮颜色

  AppLocalizations get localizations => AppLocalizations.of(availableContext)!;

  @override
  void initState() {
    request = widget.request;
    response = request.response;
    super.initState();
    // 注册响应刷新回调
    widget.onMount?.call(() {
      response = request.response;
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    widget.onUnmount?.call();
    super.dispose();
  }

  Color? color(String url) {
    if (highlightColor != null) {
      return highlightColor;
    }

    highlightColor = KeywordHighlights.getHighlightColor(url);
    if (highlightColor != null) {
      return highlightColor;
    }

    return autoReadRequests.contains(request.requestId) ? Colors.grey : null;
  }

  BuildContext getContext() => mounted ? super.context : NavigatorHelper().context;

  BuildContext get availableContext => getContext();

  @override
  Widget build(BuildContext context) {
    String url = widget.displayDomain ? request.requestUrl : request.path;
    var highlightColor = color(url);
    var isMqtt = request.protocolVersion == 'MQTT';

    return GestureDetector(
        onLongPressStart: menu,
        child: ListTile(
          // 高度由 ListTileTheme.minTileHeight(72) 决定，这里不再压缩行高
          minLeadingWidth: 5,
          minVerticalPadding: 0,
          selected: selected ||
              (widget.selectionController.isSelectionMode && widget.selectionController.contains(request.requestId)),
          textColor: highlightColor,
          selectedColor: highlightColor,
          selectedTileColor: DarkPalette.hoverWeak,
          splashColor: DarkPalette.hover,
          leading: rowLeading(),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              nameLine(highlightColor),
              const SizedBox(height: 3),
              methodUrlLine(url, isMqtt),
              const SizedBox(height: 3),
              statusLine(isMqtt),
            ],
          ),
          trailing: isMqtt
              ? const Icon(Icons.hub_outlined, size: 18, color: DarkPalette.ws)
              : getIcon(response, color: highlightColor),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          onTap: () {
            if (widget.selectionController.isSelectionMode) {
              widget.selectionController.toggle(request.requestId);
              return;
            }

            if (AppConfiguration.current?.autoReadEnabled == true) {
              if (markAutoRead(request.requestId)) {
                setState(() {});
              }
            }

            Navigator.of(getContext()).push(MaterialPageRoute(builder: (context) {
              return NetworkTabController(
                  proxyServer: widget.proxyServer,
                  httpRequest: request,
                  httpResponse: response,
                  title: mobileDetailTitle(context, request));
            }));
          },
        ));
  }

  /// 第一行：应用/域名 + 序号胶囊 + 时间
  Widget nameLine(Color? highlightColor) {
    var name = request.remoteDomain() ?? request.hostAndPort?.host ?? '';
    if (name.isEmpty) name = request.path.isNotEmpty ? request.path : request.requestUrl;

    return Row(children: [
      Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: highlightColor ?? DarkPalette.text1))),
      const SizedBox(width: 6),
      sequencePill(),
      const SizedBox(width: 8),
      Text(formatDate(request.requestTime, [HH, ':', nn, ':', ss]),
          style: const TextStyle(fontSize: 11.5, height: 1.2, color: DarkPalette.text3)),
    ]);
  }

  /// 序号胶囊
  Widget sequencePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: DarkPalette.countBg, borderRadius: BorderRadius.circular(12)),
      child: Text('#${widget.index}',
          style: const TextStyle(fontSize: 10.5, height: 1.1, color: DarkPalette.text2)),
    );
  }

  /// 第二行：请求方法 + URL
  Widget methodUrlLine(String url, bool isMqtt) {
    var operationName = request.graphqlOperationName;
    var methodColor = isMqtt ? DarkPalette.ws : methodColorOf(request.method);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isMqtt ? 'MQTT' : request.method.name,
            style: TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w600, color: methodColor)),
        const SizedBox(width: 8),
        Expanded(
            child: Text.rich(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                TextSpan(children: [
                  TextSpan(
                      text: Strings.autoLineString(url),
                      style: const TextStyle(fontSize: 13, height: 1.25, color: DarkPalette.text2)),
                  if (operationName != null) graphqlOperationSpan(request, fontSize: 13)!,
                ]))),
      ],
    );
  }

  /// 第三行：状态码 + 大小 + json 标记
  Widget statusLine(bool isMqtt) {
    var code = response?.status.code;
    Widget left;
    if (isMqtt) {
      left = Text('${request.messages.length} packets',
          style: const TextStyle(fontSize: 12, height: 1.15, color: DarkPalette.text3));
    } else if (code == null) {
      left = const Text('—', style: TextStyle(fontSize: 12, height: 1.15, color: DarkPalette.text3));
    } else {
      left = Text('$code',
          style: TextStyle(fontSize: 12, height: 1.15, fontWeight: FontWeight.w500, color: statusColorOf(code)));
    }

    var size = formatBodySize(response?.body?.length);

    return Row(children: [
      left,
      const Spacer(),
      if (size != null)
        Text(size, style: const TextStyle(fontSize: 12, height: 1.15, color: DarkPalette.text3)),
      if (isJsonResponse()) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: DarkPalette.countBg, borderRadius: BorderRadius.circular(12)),
          child: const Text('{}', style: TextStyle(fontSize: 10.5, height: 1.1, color: DarkPalette.text3)),
        ),
      ],
    ]);
  }

  /// 请求方法对应的主题色
  static Color methodColorOf(HttpMethod method) {
    switch (method) {
      case HttpMethod.get:
        return DarkPalette.ok;
      case HttpMethod.post:
        return DarkPalette.warn;
      case HttpMethod.put:
      case HttpMethod.patch:
        return DarkPalette.put;
      case HttpMethod.delete:
        return DarkPalette.err;
      case HttpMethod.mqtt:
        return DarkPalette.ws;
      default:
        return DarkPalette.text2;
    }
  }

  /// 状态码对应的主题色
  static Color statusColorOf(int code) {
    if (code < 0) return DarkPalette.err;
    if (code >= 200 && code < 300) return DarkPalette.ok;
    if (code >= 300 && code < 400) return DarkPalette.put;
    if (code >= 400 && code < 500) return DarkPalette.warn;
    if (code >= 500) return DarkPalette.err;
    return DarkPalette.text3;
  }

  /// 响应体大小（B / KB / MB）
  static String? formatBodySize(int? length) {
    if (length == null) return null;
    if (length < 1024) return '$length B';
    if (length < 1024 * 1024) return '${(length / 1024).toStringAsFixed(1)} KB';
    return '${(length / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// 响应内容是否为 json
  bool isJsonResponse() {
    return response?.headers.contentType.toLowerCase().contains('json') == true;
  }

  Widget? rowLeading() {
    var icon = appIcon();
    if (!widget.selectionController.isSelectionMode) {
      return icon;
    }

    bool isSelected = widget.selectionController.contains(request.requestId);
    var checkbox = Icon(isSelected ? Icons.check_box_outlined : Icons.check_box_outline_blank_outlined,
        size: 20, color: isSelected ? Theme.of(context).colorScheme.primary : null);

    if (icon == null) {
      return checkbox;
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [checkbox, const SizedBox(width: 6), icon]);
  }

  Widget? appIcon() {
    if (Platform.isIOS) {
      return null;
    }
    if (request.processInfo == null) {
      return roundedIcon(const Icon(Icons.question_mark, size: 22, color: DarkPalette.text3));
    }

    //如果有缓存图标直接返回图标
    if (request.processInfo!.hasCacheIcon) {
      final cached = imageCache.putIfAbsent(request.processInfo!.id, () {
        return Image.memory(request.processInfo!.cacheIcon!, width: 40, gaplessPlayback: true);
      });
      return roundedIcon(
          cached ?? const Icon(Icons.question_mark, size: 22, color: DarkPalette.text3));
    }

    return FutureBuilder(
        future: request.processInfo!.getIcon(),
        builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
          if (snapshot.hasData) {
            return roundedIcon(Image.memory(snapshot.data!, width: 40));
          }
          return roundedIcon(const SizedBox(width: 40));
        });
  }

  /// 应用图标：40dp、8dp 圆角
  Widget roundedIcon(Widget icon) {
    return SizedBox(
        width: 40,
        height: 40,
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Center(child: icon)));
  }

  ///菜单
  void menu(details) {
    setState(() {
      selected = true;
    });

    var globalPosition = details.globalPosition;
    MediaQueryData mediaQuery = MediaQuery.of(context);
    var position = RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx, globalPosition.dy);
    final selectionMode = widget.selectionController.isSelectionMode;
    // Trigger haptic feedback
    if (Platform.isAndroid) HapticFeedback.mediumImpact();

    showMenu(
        context: context,
        constraints: BoxConstraints(maxWidth: mediaQuery.size.width * 0.88),
        position: position,
        items: [
          PopupMenuContainer(
              child: Column(
            children: selectionMode
                ? [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                          padding: EdgeInsets.only(left: 20, top: 5),
                          child: Text(localizations.selectAction, style: Theme.of(context).textTheme.bodyLarge)),
                    ),
                    menuItem(
                      left: itemButton(
                          onPressed: () {
                            widget.selectionHandlers.onExportSelected?.call();
                            Navigator.maybePop(availableContext);
                          },
                          label: localizations.export,
                          icon: Icons.checklist_rtl_outlined),
                      right: itemButton(
                          onPressed: () {
                            widget.selectionHandlers.onRepeatSelected?.call();
                            Navigator.maybePop(availableContext);
                          },
                          label: localizations.repeat,
                          icon: Icons.delete_outline),
                    ),
                    SizedBox(height: 1),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      itemButton(
                          onPressed: () {
                            widget.selectionHandlers.onDeleteSelected?.call();
                            Navigator.maybePop(availableContext);
                          },
                          label: localizations.delete,
                          icon: Icons.delete_outline),
                      SizedBox(width: 15),
                    ]),
                  ]
                : [
                    //复制url
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                          padding: EdgeInsets.only(left: 20, top: 5),
                          child: Text(localizations.selectAction, style: Theme.of(context).textTheme.bodyLarge)),
                    ),
                    //copy
                    menuItem(
                      left: itemButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: request.requestUrl)).then((value) {
                              FlutterToastr.show(localizations.copied, getContext());
                              Navigator.maybePop(getContext());
                            });
                          },
                          label: localizations.copyUrl,
                          icon: Icons.link,
                          iconSize: 22),
                      right: itemButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: curlRequest(request))).then((value) {
                              FlutterToastr.show(localizations.copied, getContext());
                              Navigator.maybePop(getContext());
                            });
                          },
                          label: localizations.copyCurl,
                          icon: Icons.code),
                    ),
                    // Code snippet: same captured request, any language (page has the picker).
                    menuItem(
                      left: itemButton(
                          onPressed: () async {
                            await Navigator.maybePop(availableContext);
                            var pageRoute =
                                MaterialPageRoute(builder: (context) => CodeSnippetPage(request: request));
                            Navigator.push(getContext(), pageRoute);
                          },
                          label: 'Code snippet…',
                          icon: Icons.terminal),
                      right: const SizedBox.shrink(),
                    ),
                    //repeat
                    menuItem(
                      left: itemButton(
                          onPressed: () {
                            onRepeat(request);
                            Navigator.maybePop(getContext());
                          },
                          label: localizations.repeat,
                          icon: Icons.repeat_one),
                      right: itemButton(
                          onPressed: () => showCustomRepeat(request),
                          label: localizations.customRepeat,
                          icon: Icons.repeat),
                    ),
                    //favorite and edit
                    menuItem(
                      left: itemButton(
                          onPressed: () {
                            FavoriteStorage.addFavorite(widget.request);
                            FlutterToastr.show(localizations.addSuccess, availableContext);
                            Navigator.maybePop(availableContext);
                          },
                          label: localizations.favorite,
                          icon: Icons.favorite_outline),
                      right: itemButton(
                          onPressed: () async {
                            await Navigator.maybePop(availableContext);

                            var pageRoute = MaterialPageRoute(
                                builder: (context) =>
                                    MobileRequestEditor(request: widget.request, proxyServer: widget.proxyServer));
                            Navigator.push(getContext(), pageRoute);
                          },
                          label: localizations.editRequest,
                          icon: Icons.replay_outlined),
                    ),
                    //script and rewrite
                    menuItem(
                      left: itemButton(
                          onPressed: () async {
                            Navigator.maybePop(availableContext);

                            var scriptManager = await ScriptManager.instance;
                            var url = request.domainPath;
                            var scriptItem = scriptManager.list.firstWhereOrNull((it) => it.urls.contains(url));
                            String? script = scriptItem == null ? null : await scriptManager.getScript(scriptItem);

                            var pageRoute = MaterialPageRoute(
                                builder: (context) => ScriptEdit(
                                    scriptItem: scriptItem,
                                    script: script,
                                    urls: scriptItem?.urls ?? [url],
                                    title: request.hostAndPort?.host));

                            Navigator.push(getContext(), pageRoute);
                          },
                          label: localizations.script,
                          icon: Icons.javascript_outlined),
                      right: itemButton(
                          onPressed: () async {
                            Navigator.maybePop(availableContext);
                            bool isRequest = response == null;
                            var requestRewrites = await RequestRewriteManager.instance;

                            var ruleType = isRequest ? RuleType.requestReplace : RuleType.responseReplace;
                            var rule = requestRewrites.getRequestRewriteRule(request, ruleType);

                            var rewriteItems = await requestRewrites.getRewriteItems(rule);

                            var pageRoute = MaterialPageRoute(
                                builder: (_) => RewriteRule(rule: rule, items: rewriteItems, request: request));
                            var context = availableContext;
                            if (context.mounted) Navigator.push(context, pageRoute);
                          },
                          label: localizations.requestRewrite,
                          icon: Icons.edit_outlined),
                    ),
                    menuItem(
                      left: itemButton(
                          onPressed: () {
                            highlightColor = Theme.of(availableContext).colorScheme.primary;
                            Navigator.maybePop(availableContext);
                          },
                          label: localizations.highlight,
                          icon: Icons.highlight_outlined),
                      right: itemButton(
                          onPressed: () {
                            AppConfiguration.current?.autoReadEnabled = !AppConfiguration.current!.autoReadEnabled;
                            highlightColor = Colors.grey;
                            Navigator.maybePop(availableContext);
                          },
                          label: localizations.autoRead,
                          icon: AppConfiguration.current?.autoReadEnabled == true
                              ? Icons.check_box_outlined
                              : Icons.check_box_outline_blank_outlined),
                    ),
                    SizedBox(height: 1),
                    menuItem(
                      left: itemButton(
                          onPressed: () {
                            widget.selectionController.toggle(request.requestId);
                            Navigator.maybePop(availableContext);
                          },
                          label: localizations.select,
                          icon: Icons.checklist_rtl_outlined),
                      right: itemButton(
                          onPressed: () {
                            widget.onRemove?.call(request);
                            FlutterToastr.show(localizations.deleteSuccess, availableContext);
                            Navigator.maybePop(availableContext);
                          },
                          label: localizations.delete,
                          icon: Icons.delete_outline),
                    ),
                  ],
          )),
        ]).then((value) {
      selected = false;
      if (mounted) setState(() {});
    });
  }

  //显示高级重发
  Future<void> showCustomRepeat(HttpRequest request) async {
    await Navigator.maybePop(availableContext);
    var pageRoute = MaterialPageRoute(
        builder: (context) => futureWidget(SharedPreferences.getInstance(),
            (prefs) => MobileCustomRepeat(
                onScheduled: (cfg) =>
                    ReplayTaskManager.instance.start(request: request, action: () => onRepeat(request), config: cfg),
                prefs: prefs)));

    Navigator.push(getContext(), pageRoute);
  }

  void onRepeat(HttpRequest request) {
    var httpRequest = request.copy(uri: request.requestUrl);
    var proxyInfo = widget.proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", widget.proxyServer.port) : null;
    HttpClients.proxyRequest(httpRequest, proxyInfo: proxyInfo);

    if (mounted) {
      FlutterToastr.show(localizations.reSendRequest, context);
    }
  }

  Widget itemButton(
      {required String label, required IconData icon, required Function() onPressed, double iconSize = 20}) {
    var theme = Theme.of(context);
    var style = theme.textTheme.bodyMedium;
    return TextButton.icon(
        onPressed: onPressed,
        label: Text(label, style: style),
        icon: Icon(icon, size: iconSize, color: theme.colorScheme.primary.withValues(alpha: 0.65)));
  }

  Widget menuItem({required Widget left, required Widget right}) {
    return Row(
      children: [
        SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: left)),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: right))
      ],
    );
  }
}

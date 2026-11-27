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
import 'package:qanis/l10n/app_localizations.dart';
import 'package:qanis/network/bin/server.dart';
import 'package:qanis/network/channel/channel.dart';
import 'package:qanis/network/channel/channel_context.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/ui/component/multi_select_controller.dart';
import 'package:qanis/ui/component/utils.dart' show DarkPalette;
import 'package:qanis/ui/mobile/request/domians.dart';
import 'package:qanis/ui/mobile/request/request.dart';
import 'package:qanis/ui/mobile/request/request_sequence.dart';
import 'package:qanis/utils/export_request.dart';
import 'package:qanis/utils/listenable_list.dart';

import '../../component/model/search_model.dart';

/// 请求列表
/// @author wanghongen
class RequestListWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest>? list;
  final MultiSelectController selectionController;

  const RequestListWidget({super.key, required this.proxyServer, this.list, required this.selectionController});

  @override
  State<StatefulWidget> createState() {
    return RequestListState();
  }
}

class RequestListState extends State<RequestListWidget> {
  final GlobalKey<RequestSequenceState> requestSequenceKey = GlobalKey<RequestSequenceState>();
  final GlobalKey<DomainListState> domainListKey = GlobalKey<DomainListState>();

  //请求列表容器
  ListenableList<HttpRequest> container = ListenableList();

  //当前搜索模型
  SearchModel? _currentSearchModel;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.list != null) {
      container = widget.list!;
    }
  }

  @override
  void dispose() {
    RequestRowState.removeAutoReadByIds(container.map((request) => request.requestId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> tabs = [Tab(child: Text(localizations.sequence))];

    //double click scroll to top
    var tabClickHandles = [DoubleClickHandle(handle: () => requestSequenceKey.currentState?.scrollToTop())];

    return DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          backgroundColor: _listBackground(context),
          appBar: AppBar(
              title: TabBar(
                  tabs: tabs,
                  onTap: (index) => tabClickHandles[index].call(),
                  // Reqable 琥珀下划线标签：选中主色指示条 + 发丝分隔线
                  indicatorColor: DarkPalette.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorWeight: 2,
                  dividerColor: DarkPalette.divider,
                  dividerHeight: 0.5,
                  labelColor: DarkPalette.text1,
                  unselectedLabelColor: DarkPalette.text3,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                  overlayColor: WidgetStateProperty.all(DarkPalette.hover),
                  splashFactory: InkRipple.splashFactory),
              automaticallyImplyLeading: false,
              backgroundColor: DarkPalette.panel,
              foregroundColor: DarkPalette.text1,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0),
          body: _reqableRowTheme(
            context,
            TabBarView(
              children: [
                RequestSequence(
                    key: requestSequenceKey,
                    container: container,
                    proxyServer: widget.proxyServer,
                    onRemove: sequenceRemove,
                    selectionController: widget.selectionController),
              ],
            ),
          ),
        ));
  }

  /// Reqable 炭灰底（AMOLED 纯黑主题下沿用纯黑）
  Color _listBackground(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor == Colors.black ? Colors.black : DarkPalette.bg;

  /// 把 Reqable 令牌下推给行组件。
  ///
  /// 行本身由 [RequestSequence] / `RequestRow`（request.dart、request_sequence.dart）
  /// 构建，本文件不复制它们的交互逻辑，只用主题继承统一外观：
  /// 扁平炭灰底、发丝分隔线、选中 hoverWeak、按压/涟漪 hover、三级文字层级，
  /// 以及暗色主色（琥珀）——这样所有既有回调（点击、长按菜单、多选、过滤）保持不变。
  Widget _reqableRowTheme(BuildContext context, Widget child) {
    var theme = Theme.of(context);
    var background = _listBackground(context);
    var scheme = theme.colorScheme;
    return Theme(
        data: theme.copyWith(
            splashColor: DarkPalette.hover,
            highlightColor: DarkPalette.hover,
            hoverColor: DarkPalette.hover,
            dividerColor: DarkPalette.divider,
            scaffoldBackgroundColor: background,
            colorScheme: scheme.copyWith(
                primary: DarkPalette.primary,
                onPrimary: DarkPalette.bg,
                surface: background,
                onSurface: DarkPalette.text1,
                onSurfaceVariant: DarkPalette.text2,
                outlineVariant: DarkPalette.border,
                error: DarkPalette.err),
            textTheme: theme.textTheme.apply(bodyColor: DarkPalette.text1, displayColor: DarkPalette.text1)),
        child: ListTileTheme(
            data: ListTileThemeData(
                // 无卡片、无阴影：整行平铺在炭灰底上
                tileColor: background,
                selectedTileColor: DarkPalette.hoverWeak,
                textColor: DarkPalette.text1,
                selectedColor: DarkPalette.text1,
                iconColor: DarkPalette.text2,
                // Reqable 行高约 72dp，左右 16dp
                minTileHeight: 78,
                minVerticalPadding: 10,
                horizontalTitleGap: 12,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                titleTextStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: DarkPalette.text1, height: 1.25),
                subtitleTextStyle: const TextStyle(fontSize: 12, color: DarkPalette.text2, height: 1.25)),
            child: child));
  }

  ///添加请求
  void add(Channel channel, HttpRequest request) {
    container.add(request);
    requestSequenceKey.currentState?.add(request);
    domainListKey.currentState?.add(request);
  }

  ///添加响应
  void addResponse(ChannelContext channelContext, HttpResponse response) {
    requestSequenceKey.currentState?.addResponse(response);
    domainListKey.currentState?.addResponse(response);
  }

  ///移除
  void domainListRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    requestSequenceKey.currentState?.remove(list);
    RequestRowState.removeAutoReadByIds(list.map((request) => request.requestId));
  }

  ///全部请求删除
  void sequenceRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    domainListKey.currentState?.remove(list);
    RequestRowState.removeAutoReadByIds(list.map((request) => request.requestId));
  }

  void search(SearchModel searchModel) {
    _currentSearchModel = searchModel; // 保存当前搜索状态
    requestSequenceKey.currentState?.search(searchModel);
    domainListKey.currentState?.search(searchModel);
  }

  Iterable<HttpRequest>? currentView() {
    return requestSequenceKey.currentState?.currentView();
  }

  ///清理
  void clean() {
    setState(() {
      RequestRowState.removeAutoReadByIds(container.map((request) => request.requestId));
      container.clear();
      domainListKey.currentState?.clean();
      requestSequenceKey.currentState?.clean();
    });
  }

  ///清理早期数据
  void cleanupEarlyData(int retain) {
    var list = container.source;
    if (list.length <= retain) {
      return;
    }

    var removeRange = container.removeRange(0, list.length - retain);

    domainListKey.currentState?.clean();
    requestSequenceKey.currentState?.clean();
    RequestRowState.removeAutoReadByIds(removeRange.map((request) => request.requestId));
  }

  //导出har或文件夹
  Future<void> export(BuildContext context, String title) async {
    var view = currentView()!;
    var folderName = '${title.contains("QANIS") ? '' : 'QANIS'}$title'.replaceAll(" ", "_").replaceAll(":", "_");

    showExportDialog(context, view.toList(), folderName);
  }

  void sort(bool sortDesc) {
    requestSequenceKey.currentState?.sort(sortDesc);
    domainListKey.currentState?.sort(sortDesc);
  }
}

class DoubleClickHandle {
  int tabClickTime = 0;
  final Function()? handle;

  DoubleClickHandle({this.handle});

  void call() {
    if (handle == null) {
      return;
    }

    if (DateTime.now().millisecondsSinceEpoch - tabClickTime < 500) {
      handle?.call();
    }
    tabClickTime = DateTime.now().millisecondsSinceEpoch;
  }
}

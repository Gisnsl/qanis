/*
 * Copyright 2023 Hongen Wang
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
import 'package:qanis/l10n/app_localizations.dart';
import 'package:qanis/native/pip.dart';
import 'package:qanis/network/bin/server.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/ui/configuration.dart';
import 'package:qanis/utils/ip.dart';
import 'package:qanis/utils/lang.dart';
import 'package:qanis/utils/listenable_list.dart';

/// Reqable 风格浮窗尺寸令牌（颜色全部走 DarkPalette，禁止裸色值）
const double _bubbleSize = 56; // 气泡直径
const double _cardWidth = 260; // 展开卡片宽度
const double _edgeGap = 8; // 贴边留白
const double _cardRadius = 12; // 卡片/胶囊圆角
const double _cardHeightEstimate = 172; // 卡片高度估算，仅用于展开时的纵向边界

double _clamp(double value, double lower, double upper) {
  if (upper < lower) return lower;
  if (value < lower) return lower;
  if (value > upper) return upper;
  return value;
}

/// 方法颜色：GET 绿 / POST 琥珀 / PUT·PATCH 蓝 / DELETE 红 / 其余次要文字色
Color _methodColor(HttpMethod method) {
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
    default:
      return DarkPalette.text2;
  }
}

/// 取域名用于展示；解析失败时回退整条 url
String _hostOf(HttpRequest request) {
  final host = request.requestUri?.host ?? '';
  return host.isEmpty ? request.requestUrl : host;
}

/// Picture in Picture Window
class PictureInPictureWindow extends StatefulWidget {
  final ListenableList<HttpRequest> container;

  const PictureInPictureWindow(this.container, {super.key});

  @override
  State<PictureInPictureWindow> createState() => _PictureInPictureWindowState();
}

class _PictureInPictureWindowState extends State<PictureInPictureWindow> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  OnchangeListEvent<HttpRequest>? changeEvent;

  @override
  void initState() {
    super.initState();
    changeEvent = OnchangeListEvent(() {
      setState(() {});
    });
    widget.container.addListener(changeEvent!);
  }

  @override
  void dispose() {
    widget.container.removeListener(changeEvent!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flows = widget.container;

    return Material(
      color: DarkPalette.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行：抓包点 + 标题 + 流计数
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: DarkPalette.primary),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'QANIS capture',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DarkPalette.text1),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: DarkPalette.border),
            Expanded(
              child: flows.isEmpty
                  ? Center(
                      child: Text(
                        localizations.emptyData,
                        style: const TextStyle(fontSize: 12, color: DarkPalette.text3),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: flows.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, thickness: 1, color: DarkPalette.divider),
                      itemBuilder: (context, index) {
                        // 倒序：最新请求在最上面
                        final request = flows.elementAt(flows.length - index - 1);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Text(
                                  request.method.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _methodColor(request.method),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _hostOf(request),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: DarkPalette.text2),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// pip Icon
/// Reqable 风格悬浮气泡：56dp 圆、抓包中琥珀 / 空闲计数灰、白色抓包图标，
/// 可拖拽并在松手时吸附到最近的水平边缘；点击展开 260dp 状态卡片。
class PictureInPictureIcon extends StatefulWidget {
  final ProxyServer proxyServer;

  /// 可选的请求列表数据源（用于流计数与最近三条请求），由调用方注入。
  /// 未注入时气泡仍可拖拽/展开，卡片显示 0 flows 与 "No flows yet"。
  final ListenableList<HttpRequest>? container;

  /// 可选的启停回调；为空时回退为 proxyServer.start() / proxyServer.stop()
  final VoidCallback? onToggleCapture;

  /// 可选的“打开”回调；为空时沿用原有的进入画中画逻辑
  final VoidCallback? onOpen;

  const PictureInPictureIcon(this.proxyServer, {super.key, this.container, this.onToggleCapture, this.onOpen});

  @override
  State<PictureInPictureIcon> createState() => _PictureInPictureState();
}

class _PictureInPictureState extends State<PictureInPictureIcon> {
  static double xPosition = -1;
  static double yPosition = -1;
  static Size? size;

  /// 卡片是否展开
  bool _expanded = false;

  /// 拖拽中：位置不做动画，松手吸附时才过渡
  bool _dragging = false;

  /// 启停请求进行中，避免重复触发
  bool _busy = false;

  ValueNotifier<bool>? _pipIcon;
  ListenableList<HttpRequest>? _container;
  OnchangeListEvent<HttpRequest>? _changeEvent;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();

    _pipIcon = AppConfiguration.current?.pipIcon;
    _pipIcon?.addListener(_onChanged);
    _bindContainer(widget.container);
  }

  @override
  void didUpdateWidget(covariant PictureInPictureIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.container != widget.container) {
      _bindContainer(widget.container);
    }
  }

  @override
  void dispose() {
    _pipIcon?.removeListener(_onChanged);
    if (_changeEvent != null) {
      _container?.removeListener(_changeEvent!);
      _changeEvent = null;
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _bindContainer(ListenableList<HttpRequest>? container) {
    if (_changeEvent != null) {
      _container?.removeListener(_changeEvent!);
      _changeEvent = null;
    }
    _container = container;
    if (container != null) {
      _changeEvent = OnchangeListEvent(_onChanged);
      container.addListener(_changeEvent!);
    }
  }

  int get _flowCount => _container?.length ?? 0;

  /// 最近三条请求，最新的在前
  List<HttpRequest> get _recentFlows {
    final container = _container;
    if (container == null || container.isEmpty) return const [];
    final length = container.length;
    final count = length < 3 ? length : 3;
    return List.generate(count, (index) => container.elementAt(length - 1 - index));
  }

  Size get _screen => size ?? MediaQuery.sizeOf(context);

  double get _topLimit => MediaQuery.of(context).padding.top;

  double _bottomLimit(Size screen) =>
      screen.height - _bubbleSize - (AppConfiguration.current?.bottomNavigation == false ? 0 : 56);

  @override
  Widget build(BuildContext context) {
    if (AppConfiguration.current?.pipIcon.value != true) return const SizedBox();

    final screen = _screen;
    size = screen;
    if (screen.isEmpty) {
      size = null;
      return const SizedBox();
    }

    if (xPosition == -1) {
      xPosition = screen.width - _bubbleSize - _edgeGap;
      yPosition = screen.height * 0.35;
    }

    // 位置持久化在静态字段上（跨重建保留），每次构建都夹到当前边界内
    xPosition = _clamp(xPosition, 0, screen.width - _bubbleSize);
    yPosition = _clamp(yPosition, _topLimit, _bottomLimit(screen));

    final capturing = widget.proxyServer.isRunning;
    final rightSide = xPosition + _bubbleSize / 2 > screen.width / 2;

    double left;
    double top = yPosition;
    if (_expanded) {
      // 卡片贴在同一侧的边缘，从气泡位置滑出
      left = rightSide ? screen.width - _cardWidth - _edgeGap : _edgeGap;
      left = _clamp(left, _edgeGap, screen.width - _cardWidth - _edgeGap);
      top = _clamp(top, _topLimit, screen.height - _cardHeightEstimate - 24);
    } else {
      left = xPosition;
    }

    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      top: top,
      left: left,
      child: _expanded ? _statusCard(capturing) : _bubble(capturing, rightSide),
    );
  }

  /// 气泡 + 附着在气泡内侧的 “N flows” 胶囊（仅抓包中显示）
  Widget _bubble(bool capturing, bool rightSide) {
    final screen = _screen;

    return SizedBox(
      width: _bubbleSize,
      height: _bubbleSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (capturing)
            Positioned(
              top: 19,
              right: rightSide ? _bubbleSize + 6 : null,
              left: rightSide ? null : _bubbleSize + 6,
              child: IgnorePointer(child: _countPill()),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = true),
            onPanStart: (d) => setState(() => _dragging = true),
            onPanUpdate: (d) => setState(() {
              xPosition = _clamp(xPosition + d.delta.dx, 0, screen.width - _bubbleSize);
              yPosition = _clamp(yPosition + d.delta.dy, _topLimit, _bottomLimit(screen));
            }),
            onPanEnd: (d) => setState(() {
              _dragging = false;
              // 松手吸附到最近的水平边缘
              xPosition = (xPosition + _bubbleSize / 2) < screen.width / 2
                  ? _edgeGap
                  : screen.width - _bubbleSize - _edgeGap;
            }),
            child: Tooltip(message: localizations.windowMode, child: _circle(capturing)),
          ),
        ],
      ),
    );
  }

  /// 56dp 正圆气泡：抓包中琥珀，空闲 countBg，白色图标 + 柔和投影
  Widget _circle(bool capturing) {
    return Container(
      width: _bubbleSize,
      height: _bubbleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: capturing ? DarkPalette.primary : DarkPalette.countBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Center(child: Icon(Icons.radar, size: 26, color: Colors.white)),
    );
  }

  /// 流计数胶囊：11sp、panel 90% 底、12 圆角
  Widget _countPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DarkPalette.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Text(
        '$_flowCount flows',
        style: const TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w500, color: DarkPalette.text1),
      ),
    );
  }

  /// 展开的状态卡片：260dp、panel 底、12 圆角、1px border
  Widget _statusCard(bool capturing) {
    final flows = _recentFlows;
    final port = widget.proxyServer.port;

    return Container(
      width: _cardWidth,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: DarkPalette.panel,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: DarkPalette.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: capturing ? DarkPalette.primary : DarkPalette.text3,
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'QANIS capture',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DarkPalette.text1),
                ),
              ),
              Text('$_flowCount flows', style: const TextStyle(fontSize: 12, color: DarkPalette.text2)),
            ],
          ),
          const SizedBox(height: 3),
          // 状态行
          Text(
            capturing ? 'Capturing · :$port' : 'Stopped · :$port',
            style: const TextStyle(fontSize: 12, color: DarkPalette.text2),
          ),
          const SizedBox(height: 6),
          // 最近三条流
          if (flows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('No flows yet', style: TextStyle(fontSize: 12, color: DarkPalette.text3)),
            )
          else
            ...flows.map(_flowLine),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 1, color: DarkPalette.divider),
          Row(
            children: [
              _actionButton(capturing ? 'Stop' : 'Start', DarkPalette.primary, () => _toggleCapture(capturing)),
              _actionButton('Open', DarkPalette.text1, _open),
              _actionButton('Hide', DarkPalette.text2, _hide),
            ],
          ),
        ],
      ),
    );
  }

  /// 单条流：方法色 + 域名（text2），12sp
  Widget _flowLine(HttpRequest request) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              request.method.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _methodColor(request.method)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _hostOf(request),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: DarkPalette.text2),
            ),
          ),
        ],
      ),
    );
  }

  /// 12sp 文本按钮
  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  /// 开始 / 停止抓包
  Future<void> _toggleCapture(bool capturing) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final toggle = widget.onToggleCapture;
      if (toggle != null) {
        toggle();
      } else if (capturing) {
        await widget.proxyServer.stop();
      } else {
        await widget.proxyServer.start();
      }
    } catch (_) {
      // 启停失败：保持原状态，下一帧刷新状态行
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 打开：收起卡片并进入画中画（或交给注入的 onOpen）
  void _open() {
    setState(() => _expanded = false);
    final open = widget.onOpen;
    if (open != null) {
      open();
      return;
    }
    _enterPictureInPictureMode();
  }

  /// 收起卡片，回到气泡
  void _hide() {
    setState(() => _expanded = false);
  }

  Future<void> _enterPictureInPictureMode() async {
    var configuration = widget.proxyServer.configuration;
    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];
    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }

    await PictureInPicture.enterPictureInPictureMode(
      Platform.isAndroid ? await localIp() : "127.0.0.1",
      widget.proxyServer.port,
      appList: appList,
      disallowApps: disallowApps,
      setSystemProxy: configuration.enableSystemProxy,
    );
  }
}

/*
 * Copyright 2026 Hongen Wang All rights reserved.
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
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qanis/l10n/app_localizations.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/utils/code_gen.dart';
import 'package:qanis/utils/platform.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 上次选择的代码目标（语言）在 SharedPreferences 中的键。
/// 与项目其它配置一致，直接通过 SharedPreferences.getInstance() 读写。
const String _targetPrefsKey = 'code_snippet_target';

/// 构造参数 [CodeSnippetPage.initialTarget] 的默认值，用于区分“调用方显式指定”与“未指定”。
const String _defaultTarget = 'python-requests';

/// 代码片段查看/复制/保存页：把一条请求渲染成 22 种语言/工具的调用代码。
/// 外观与 fork 里其它 Reqable 风格页面一致（charcoal + amber，令牌取自 [DarkPalette]）。
class CodeSnippetPage extends StatefulWidget {
  const CodeSnippetPage({super.key, required this.request, this.initialTarget = 'python-requests'});

  final HttpRequest request;

  /// 打开时选中的目标 id；等于默认值 'curl' 时视为“未显式指定”，改用上次记住的目标。
  final String initialTarget;

  @override
  State<CodeSnippetPage> createState() => _CodeSnippetPageState();
}

class _CodeSnippetPageState extends State<CodeSnippetPage> {
  late String _targetId;
  String _code = '';

  CodeTarget get _target =>
      kCodeTargets.firstWhere((it) => it.id == _targetId, orElse: () => kCodeTargets.first);

  @override
  void initState() {
    super.initState();
    _targetId = widget.initialTarget;
    _code = generateCode(_targetId, widget.request);
    _restoreRememberedTarget();
  }

  @override
  void didUpdateWidget(covariant CodeSnippetPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request, widget.request)) {
      _code = generateCode(_targetId, widget.request);
    }
  }

  /// 记住的目标只作为“未显式指定目标”时的默认值：调用方传了别的 target 时以调用方为准。
  Future<void> _restoreRememberedTarget() async {
    if (widget.initialTarget != _defaultTarget) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_targetPrefsKey);
      if (!mounted || saved == null || saved == _targetId) return;
      if (!kCodeTargets.any((it) => it.id == saved)) return;
      setState(() {
        _targetId = saved;
        _code = generateCode(saved, widget.request);
      });
    } catch (_) {
      // 读取失败时保持默认目标，不打断页面。
    }
  }

  Future<void> _selectTarget(String id) async {
    if (id == _targetId) return;
    setState(() {
      _targetId = id;
      _code = generateCode(id, widget.request);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_targetPrefsKey, id);
    } catch (_) {
      // 记住失败不影响本次使用。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DarkPalette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            _buildTargetSelector(context),
            Expanded(child: _buildCodeBody(context)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- top bar

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: const BoxDecoration(
        color: DarkPalette.panel,
        border: Border(bottom: BorderSide(color: DarkPalette.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          _barIcon(
            icon: Icons.arrow_back_ios_new,
            tooltip: 'Back',
            size: 18,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 2),
          const Expanded(
            child: Text(
              'Code Snippet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: DarkPalette.text1, fontWeight: FontWeight.w500),
            ),
          ),
          _barIcon(icon: Icons.copy_rounded, tooltip: 'Copy', onTap: _copy),
          _barIcon(icon: Icons.save_alt_rounded, tooltip: 'Save', onTap: _save),
          _barIcon(icon: Icons.share_rounded, tooltip: 'Share', onTap: _share),
        ],
      ),
    );
  }

  Widget _barIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double size = 20,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      icon: Icon(icon, size: size, color: DarkPalette.text1),
    );
  }

  // ------------------------------------------------------- language selector

  Widget _buildTargetSelector(BuildContext context) {
    return InkWell(
      onTap: _showTargetSheet,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          color: DarkPalette.panel,
          border: Border(bottom: BorderSide(color: DarkPalette.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.translate_rounded, size: 16, color: DarkPalette.text3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _target.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, color: DarkPalette.text1),
              ),
            ),
            Text(
              _target.language,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: DarkPalette.text3),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more_rounded, size: 18, color: DarkPalette.text3),
          ],
        ),
      ),
    );
  }

  Future<void> _showTargetSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DarkPalette.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (sheetContext) {
        // 22 个目标，必须可滚动：固定最大高度 + Flexible 列表。
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Code target',
                          style: TextStyle(fontSize: 14, color: DarkPalette.text1, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '${kCodeTargets.length}',
                        style: const TextStyle(fontSize: 12, color: DarkPalette.text3),
                      ),
                    ],
                  ),
                ),
                Container(height: 0.5, color: DarkPalette.divider),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: kCodeTargets.length,
                    itemBuilder: (context, index) {
                      final target = kCodeTargets[index];
                      final active = target.id == _targetId;
                      return InkWell(
                        onTap: () => Navigator.of(sheetContext).pop(target.id),
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          color: active ? DarkPalette.hoverWeak : Colors.transparent,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      target.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: active ? DarkPalette.primary : DarkPalette.text1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      target.language,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: DarkPalette.text3),
                                    ),
                                  ],
                                ),
                              ),
                              if (active) const Icon(Icons.check_rounded, size: 18, color: DarkPalette.primary),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      await _selectTarget(selected);
    }
  }

  // ------------------------------------------------------------- code body

  /// 行号与代码必须共用同一套字号/行高，否则逐行错位；末尾换行符先去掉，
  /// 免得代码多出一行而行号没有。
  static const TextStyle _monoStyle = TextStyle(
    fontSize: 12.5,
    height: 1.5,
    color: DarkPalette.text1,
    fontFamily: 'monospace',
    fontFamilyFallback: ['Menlo', 'Consolas', 'DejaVu Sans Mono', 'Courier New', 'monospace'],
  );

  static const TextStyle _gutterStyle = TextStyle(
    fontSize: 12.5,
    height: 1.5,
    color: DarkPalette.text3,
    fontFamily: 'monospace',
    fontFamilyFallback: ['Menlo', 'Consolas', 'DejaVu Sans Mono', 'Courier New', 'monospace'],
  );

  Widget _buildCodeBody(BuildContext context) {
    final display = _stripTrailingNewlines(_code);
    if (display.isEmpty) {
      return const Center(
        child: Text('No snippet available', style: TextStyle(fontSize: 13, color: DarkPalette.text3)),
      );
    }

    final lineCount = '\n'.allMatches(display).length + 1;
    final gutter = List<String>.generate(lineCount, (i) => '${i + 1}').join('\n');
    // 行号栏基准 40dp；超过 4 位数时略微加宽，避免行号换行破坏与代码的对齐。
    final gutterWidth = lineCount > 9999 ? 56.0 : (lineCount > 999 ? 46.0 : 40.0);

    return Container(
      margin: const EdgeInsets.all(10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DarkPalette.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DarkPalette.divider, width: 0.5),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 40dp 行号栏：一次渲染整列，与代码同一行高，右侧对齐并带 0.5px 分隔线。
            Container(
              width: gutterWidth,
              padding: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: DarkPalette.divider, width: 0.5)),
              ),
              child: Text(gutter, textAlign: TextAlign.right, style: _gutterStyle),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 10, right: 12),
                child: SelectableText.rich(
                  _highlighted(display),
                  style: _monoStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 语法高亮：用 re_highlight 生成带颜色的 span，未知语言回退为纯文本
  TextSpan _highlighted(String code) {
    try {
      final language = _target.language == 'http' ? 'shell' : _target.language;
      final result = _highlighter.highlight(code: code, language: language);
      final renderer = TextSpanRenderer(_monoStyle, atomOneDarkTheme);
      result.render(renderer);
      return renderer.span ?? TextSpan(text: code, style: _monoStyle);
    } catch (_) {
      return TextSpan(text: code, style: _monoStyle);
    }
  }

  /// 一次性注册 re_highlight 内置的全部语言，任何目标都能上色
  static final Highlight _highlighter = () {
    final h = Highlight();
    for (final entry in builtinAllLanguages.entries) {
      h.registerLanguage(entry.key, entry.value);
    }
    return h;
  }();

  String _stripTrailingNewlines(String text) {
    var end = text.length;
    while (end > 0 && (text[end - 1] == '\n' || text[end - 1] == '\r')) {
      end--;
    }
    return text.substring(0, end);
  }

  // ---------------------------------------------------------------- actions

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    FlutterToastr.show(AppLocalizations.of(context)!.copied, context);
  }

  /// 导出目录：桌面端优先系统下载目录（用户可见），其余平台回退到应用文档目录。
  /// 导出请求的辅助函数（utils/export_request.dart）只处理请求/响应报文，不适用于任意文本。
  Future<Directory?> _exportDirectory() async {
    try {
      if (Platforms.isDesktop()) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) return downloads;
      }
    } catch (_) {
      // getDownloadsDirectory 在部分平台未实现，回退到文档目录。
    }
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final dir = await _exportDirectory();
      if (dir == null) {
        if (mounted) FlutterToastr.show('${localizations.save}${localizations.fail}', context);
        return;
      }
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File('${dir.path}${Platform.pathSeparator}${_fileName()}');
      await file.writeAsString(_code);
      if (!mounted) return;
      FlutterToastr.show('${localizations.save}: ${file.path}', context);
    } catch (_) {
      if (!mounted) return;
      FlutterToastr.show('${localizations.save}${localizations.fail}', context);
    }
  }

  String _fileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'code_snippet_${_target.id}_$stamp.txt';
  }

  Future<void> _share() async {
    final code = _code;
    if (code.isEmpty) return;
    try {
      await SharePlus.instance.share(ShareParams(
        text: code,
        subject: 'Code Snippet (${_target.label})',
        sharePositionOrigin: await _sharePositionOrigin(context),
      ));
    } catch (_) {
      // 用户取消或平台不支持时静默返回。
    }
  }

  /// iPad 上 share sheet 需要锚点矩形，否则会崩；其它平台返回 null。
  Future<Rect?> _sharePositionOrigin(BuildContext context) async {
    if (!await Platforms.isIpad() || !context.mounted) return null;
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }
}

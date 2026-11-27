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

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:qanis/l10n/app_localizations.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:qanis/network/bin/server.dart';
import 'package:qanis/ui/content/code_snippet.dart';
import 'package:qanis/ui/mobile/request/composer_auth_tab.dart';
import 'package:qanis/ui/mobile/mobile.dart';
import 'package:qanis/ui/mobile/request/cookie_jar.dart';
import 'package:qanis/ui/mobile/request/composer_docs_tab.dart';
import 'package:qanis/ui/mobile/request/composer_settings_tab.dart';
import 'package:qanis/ui/mobile/setting/environment.dart';
import 'package:qanis/network/channel/host_port.dart';
import 'package:qanis/network/components/manager/environment_manager.dart';
import 'package:qanis/network/http/content_type.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/network/http/http_headers.dart';
import 'package:qanis/network/http/http_client.dart';
import 'package:qanis/ui/component/env_var_highlight.dart';
import 'package:qanis/ui/component/form_body_editor.dart';
import 'package:qanis/ui/component/search/finder.dart';
import 'package:qanis/ui/component/state_component.dart';
import 'package:qanis/ui/configuration.dart';
import 'package:qanis/ui/content/body.dart';
import 'package:qanis/utils/curl.dart';
import 'package:qanis/utils/highlight_languages.dart';
import 'package:qanis/utils/form_url.dart';
import 'package:qanis/utils/multipart.dart';
import 'package:qanis/utils/lang.dart';
import 'package:qanis/utils/xml_formatter.dart';

import 'package:qanis/ui/mobile/request/request_editor_source.dart';

import '../../component/http_method_popup.dart';

/// @author wanghongen
class MobileRequestEditor extends StatefulWidget {
  final HttpRequest? request;
  final ProxyServer? proxyServer;
  final RequestEditorSource source;
  final Function(HttpRequest? request)? onExecuteRequest;
  final Function(HttpResponse? response)? onExecuteResponse;
  final HttpResponse? response;

  const MobileRequestEditor({
    super.key,
    this.request,
    this.response,
    required this.proxyServer,
    this.source = RequestEditorSource.editor,
    this.onExecuteRequest,
    this.onExecuteResponse,
  });

  @override
  State<StatefulWidget> createState() {
    return RequestEditorState();
  }
}

class RequestEditorState extends State<MobileRequestEditor> with SingleTickerProviderStateMixin {
  final UrlQueryNotifier _queryNotifier = UrlQueryNotifier();
  final requestLineKey = GlobalKey<_RequestLineState>();
  final requestKey = GlobalKey<_HttpState>();
  final responseKey = GlobalKey<_HttpState>();

  ValueNotifier<int> responseChange = ValueNotifier<int>(-1);

  late TabController tabController;

  HttpRequest? request;
  HttpResponse? response;

  bool executed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  var tabs = const [
    Tab(text: "请求"),
    Tab(text: "响应"),
  ];

  @override
  void dispose() {
    if ((widget.source == RequestEditorSource.breakpointRequest ||
            widget.source == RequestEditorSource.breakpointResponse) &&
        !executed) {
      if (widget.source == RequestEditorSource.breakpointRequest) {
        widget.onExecuteRequest?.call(null);
      } else {
        widget.onExecuteResponse?.call(null);
      }
    }

    tabController.dispose();
    responseChange.dispose();
    _expanded.clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    tabController = TabController(
        length: tabs.length,
        vsync: this,
        initialIndex: widget.source == RequestEditorSource.breakpointResponse ? 1 : 0);
    request = widget.request;
    response = widget.response;
    // 用当前配置初始化 Composer Settings，避免默认值覆盖用户的全局设置
    ComposerSettings.http2 = widget.proxyServer?.configuration.enabledHttp2 ?? ComposerSettings.http2;
    ComposerSettings.followRedirects = true;
    ComposerSettings.sendCookies = true;
    if (widget.request == null) {
      curlParse();
    }
  }

  /// Composer ⋮ menu: every entry maps to a feature that already exists.
  Future<void> _composerMenuAction(String value) async {
    switch (value) {
      case 'rename':
        await _renameRequest();
        break;
      case 'reset':
        requestLineKey.currentState?.requestUrl.clear();
        requestLineKey.currentState?.requestMethod = HttpMethod.get;
        setState(() {});
        FlutterToastr.show('Request reset', context);
        break;
      case 'clear':
        requestLineKey.currentState?.requestUrl.clear();
        requestLineKey.currentState?.requestMethod = HttpMethod.get;
        requestKey.currentState?.headerKey.currentState?.clearAll();
        setState(() {});
        FlutterToastr.show('Cleared', context);
        break;
      case 'import_http':
        await _importRawHttp();
        break;
      case 'import_curl':
        await curlParse();
        break;
      case 'export_curl':
        final req = request;
        if (req == null) {
          FlutterToastr.show('Nothing to export yet', context);
          return;
        }
        await Clipboard.setData(ClipboardData(text: curlRequest(req)));
        if (mounted) FlutterToastr.show('cURL copied', context);
        break;
      case 'snippet':
        final req = request;
        if (req == null) {
          FlutterToastr.show('Nothing to export yet', context);
          return;
        }
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => CodeSnippetPage(request: req)));
        break;
      case 'environment':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MobileEnvironmentPage()));
        break;
      case 'cookie_jar':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CookieJarPage(container: MobileApp.container)));
        break;
      case 'download':
        await _downloadRequest();
        break;
    }
  }

  /// Sends the request and, when "Follow redirects" is on, follows up to five
  /// 3xx hops (301/302/303/307/308) before handing the final response back.
  Future<HttpResponse> _sendWithRedirects(ProxyInfo? proxyInfo, HttpRequest request) async {
    final timeout = Duration(milliseconds: ComposerSettings.timeoutMs);
    var current = request;
    var response = await HttpClients.proxyRequest(proxyInfo: proxyInfo, current, timeout: timeout);

    if (!ComposerSettings.followRedirects) {
      return response;
    }

    var hops = 0;
    while (hops < 5) {
      final status = response.status.code;
      if (status != 301 && status != 302 && status != 303 && status != 307 && status != 308) {
        break;
      }
      final location = response.headers.get('location');
      if (location == null || location.isEmpty) break;

      final next = Uri.parse(current.requestUrl).resolve(location).toString();
      final followUp = HttpRequest(current.method, next, protocolVersion: current.protocolVersion);
      for (final entry in current.headers.entries) {
        for (final value in entry.value) {
          followUp.headers.add(entry.key, value);
        }
      }
      followUp.headers.remove(HttpHeaders.HOST);
      if (status != 307 && status != 308) {
        followUp.body = null;
        followUp.headers.remove('Content-Length');
        followUp.headers.remove('Content-Type');
      } else {
        followUp.body = current.body;
      }

      current = followUp;
      response = await HttpClients.proxyRequest(proxyInfo: proxyInfo, current, timeout: timeout);
      hops++;
    }
    return response;
  }

  /// Rename: a display name for this request, shown in the composer title
  Future<void> _renameRequest() async {
    final controller = TextEditingController(text: request?.name ?? '');
    final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Rename', style: TextStyle(fontSize: 17)),
              content: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(hintText: 'Request name', border: OutlineInputBorder()),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Save')),
              ],
            ));
    controller.dispose();
    if (name == null || !mounted) return;
    setState(() {
      request?.name = name.trim().isEmpty ? null : name.trim();
    });
    FlutterToastr.show('Renamed', context);
  }

  /// Download: hand the request to the system share sheet as a .http file
  Future<void> _downloadRequest() async {
    final req = request;
    if (req == null) {
      FlutterToastr.show('Nothing to download yet', context);
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('${req.method.name} ${req.requestUrl}');
    for (final entry in req.headers.entries) {
      for (final value in entry.value) {
        buffer.writeln('${entry.key}: $value');
      }
    }
    final body = req.bodyAsString;
    if (body.isNotEmpty) {
      buffer.writeln();
      buffer.write(body);
    }
    final name = 'QANIS-request-${DateTime.now().millisecondsSinceEpoch}.http';
    final file = XFile.fromData(utf8.encode(buffer.toString()), mimeType: 'text/plain');
    await SharePlus.instance.share(ShareParams(files: [file], fileNameOverrides: [name]));
  }

  /// Import HTTP: paste a raw request (METHOD url, headers, blank line, body)
  Future<void> _importRawHttp() async {
    final controller = TextEditingController(text: (await Clipboard.getData('text/plain'))?.text ?? '');
    if (!mounted) return;
    final raw = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Import HTTP', style: TextStyle(fontSize: 17)),
              content: SizedBox(
                width: double.maxFinite,
                child: TextField(
                  controller: controller,
                  maxLines: 10,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                      hintText: 'POST https://example.com/api\nContent-Type: application/json\n\n{"a":1}',
                      border: OutlineInputBorder()),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Import')),
              ],
            ));
    controller.dispose();
    if (raw == null || raw.trim().isEmpty || !mounted) return;

    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    if (lines.isEmpty) return;
    final first = lines.first.trim().split(' ');
    if (first.length < 2) {
      FlutterToastr.show('Could not read the request line', context);
      return;
    }
    requestLineKey.currentState?.requestMethod = HttpMethod.valueOf(first[0].toUpperCase());
    requestLineKey.currentState?.requestUrl.text = first.sublist(1).join(' ');
    setState(() {});
    FlutterToastr.show('Imported', context);
  }

  Future<void> curlParse() async {
    //获取剪切板内容
    var data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null) {
      return;
    }
    var text = data.text;
    if (text?.startsWith("http://") == true || text?.startsWith("https://") == true) {
      requestLineKey.currentState?.requestUrl.text = text!;
      return;
    }
    if (text?.trimLeft().startsWith('curl') == true && mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
              title: Text(localizations.prompt),
              content: Text(localizations.curlSchemeRequest),
              actions: [
                TextButton(child: Text(localizations.cancel), onPressed: () => Navigator.of(context).pop()),
                TextButton(
                    child: Text(localizations.confirm),
                    onPressed: () {
                      try {
                        setState(() {
                          request = Curl.parse(text!);
                          requestKey.currentState?.change(request!);
                          requestLineKey.currentState?.change(request?.requestUrl, request?.method);
                        });
                      } catch (e) {
                        FlutterToastr.show(localizations.fail, context);
                      }
                      Navigator.of(context).pop();
                    }),
              ]);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    if (!isCN) {
      tabs = [
        Tab(text: localizations.request),
        Tab(text: localizations.response),
      ];
    }

    var buttonText = localizations.send;
    IconData icon = Icons.send;
    if (widget.source == RequestEditorSource.breakpointRequest ||
        widget.source == RequestEditorSource.breakpointResponse) {
      buttonText = localizations.execute;
      icon = Icons.play_arrow;
    }

    return Scaffold(
        appBar: AppBar(
            title: Text((request?.name?.isNotEmpty == true) ? request!.name! : localizations.httpRequest,
                style: const TextStyle(fontSize: 16)),
            centerTitle: true,
            leadingWidth: 72,
            leading: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(localizations.cancel, style: Theme.of(context).textTheme.bodyMedium)),
            actions: [
              PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  tooltip: 'More',
                  onSelected: (value) => _composerMenuAction(value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'reset', child: Text('Reset')),
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'clear', child: Text('Clear')),
                    PopupMenuItem(value: 'import_http', child: Text('Import HTTP')),
                    PopupMenuItem(value: 'import_curl', child: Text('Import cURL')),
                    PopupMenuItem(value: 'export_curl', child: Text('Export cURL')),
                    PopupMenuItem(value: 'snippet', child: Text('Code Snippet')),
                    PopupMenuItem(value: 'environment', child: Text('Environment')),
                    PopupMenuItem(value: 'cookie_jar', child: Text('Cookie Jar')),
                    PopupMenuItem(value: 'download', child: Text('Download')),
                  ]),
              TextButton.icon(
                  icon: Icon(icon),
                  label: Text(buttonText),
                  onPressed: () {
                    if (widget.source == RequestEditorSource.editor) {
                      sendRequest();
                    } else {
                      executeBreakpoint();
                    }
                  })
            ],
            bottom: TabBar(controller: tabController, tabs: tabs)),
        body: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: TabBarView(
              controller: tabController,
              children: [
                _HttpWidget(
                  title: _RequestLine(request: request, key: requestLineKey, urlQueryNotifier: _queryNotifier),
                  message: request,
                  key: requestKey,
                  urlQueryNotifier: _queryNotifier,
                  readOnly: widget.source == RequestEditorSource.breakpointResponse,
                ),
                ValueListenableBuilder(
                    valueListenable: responseChange,
                    builder: (_, value, __) {
                      if (value == 0) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return _HttpWidget(
                          key: responseKey,
                          title: Row(children: [
                            Text(response?.protocolVersion ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blue)),
                            const SizedBox(width: 10),
                            Text("${localizations.statusCode}: ", style: const TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(width: 10),
                            Text(response?.status.toString() ?? "",
                                style: TextStyle(
                                    color: response?.status.isSuccessful() == true ? Colors.blue : Colors.red))
                          ]),
                          readOnly: widget.source != RequestEditorSource.breakpointResponse,
                          message: response);
                    }),
              ],
            )));
  }

  ///发送请求
  Future<void> sendRequest() async {
    var currentState = requestLineKey.currentState!;
    // 先取 body：multipart 构建时会把带 boundary 的 Content-Type 写回 header 行
    var bodyBytes = requestKey.currentState?.getBodyBytes();
    var headers = requestKey.currentState?.getHeaders();
    String url = _renderEnv(currentState.requestUrl.text);
    _renderHeadersInPlace(headers);

    HttpRequest request = HttpRequest(currentState.requestMethod, Uri.parse(url).toString(),
        protocolVersion: this.request?.protocolVersion ?? "HTTP/1.1");

    request.headers.addAll(headers);
    request.body = bodyBytes;

    // Composer Settings → the real send path
    if (!ComposerSettings.sendCookies) {
      request.headers.remove('Cookie');
    }
    widget.proxyServer?.configuration.enabledHttp2 = ComposerSettings.http2;
    if (!ComposerSettings.http2) {
      request.protocolVersion = 'HTTP/1.1';
    }

    var proxyInfo = widget.proxyServer?.isRunning == true ? ProxyInfo.of("127.0.0.1", widget.proxyServer?.port) : null;

    responseKey.currentState?.change(null);
    responseChange.value = 0;

    _sendWithRedirects(proxyInfo, request).then((response) {
      this.response = response;
      this.response?.request = request;
      responseKey.currentState?.change(response);
      responseChange.value = 1;

      // FlutterToastr.show(localizations.requestSuccess, context);
    }).catchError((e) {
      responseChange.value = -1;
      FlutterToastr.show('${localizations.fail}$e', context);
    });

    tabController.animateTo(1);
  }

  void executeBreakpoint() {
    executed = true;
    if (widget.source == RequestEditorSource.breakpointRequest) {
      var currentState = requestLineKey.currentState!;
      var bodyBytes = requestKey.currentState?.getBodyBytes();
      var headers = requestKey.currentState?.getHeaders();
      String url = _renderEnv(currentState.requestUrl.text);
      _renderHeadersInPlace(headers);

      HttpRequest newRequest = request!.copy(uri: url);
      newRequest.method = currentState.requestMethod;
      newRequest.headers.clear();
      newRequest.headers.addAll(headers);
      newRequest.body = bodyBytes;
      widget.onExecuteRequest?.call(newRequest);
    } else if (widget.source == RequestEditorSource.breakpointResponse) {
      var bodyBytes = responseKey.currentState?.getBodyBytes();
      var headers = responseKey.currentState?.getHeaders();
      _renderHeadersInPlace(headers);

      if (response == null) return;
      HttpResponse newResponse = response!.copy();
      newResponse.headers.clear();
      newResponse.headers.addAll(headers);
      newResponse.body = bodyBytes;
      widget.onExecuteResponse?.call(newResponse);
    }
  }

  /// 用当前激活的环境变量渲染 `{{name}}`。EnvironmentManager 未加载或未启用时返回原值。
  static String _renderEnv(String input) => EnvironmentManager.tryRender(input) ?? input;

  /// 就地渲染 headers 每一项的 value。
  static void _renderHeadersInPlace(HttpHeaders? headers) {
    headers?.forEach((_, values) {
      for (int i = 0; i < values.length; i++) {
        values[i] = _renderEnv(values[i]);
      }
    });
  }
}

typedef ParamCallback = void Function(String param);

class UrlQueryNotifier {
  ParamCallback? _urlNotifier;
  ParamCallback? _paramNotifier;

  ParamCallback urlListener(ParamCallback listener) => _urlNotifier = listener;

  ParamCallback paramListener(ParamCallback listener) => _paramNotifier = listener;

  void onUrlChange(String url) => _urlNotifier?.call(url);

  void onParamChange(String param) => _paramNotifier?.call(param);
}

class _HttpWidget extends StatefulWidget {
  final HttpMessage? message;
  final bool readOnly;
  final Widget title;
  final UrlQueryNotifier? urlQueryNotifier;

  const _HttpWidget({this.message, this.readOnly = false, super.key, required this.title, this.urlQueryNotifier});

  @override
  State<StatefulWidget> createState() {
    return _HttpState();
  }
}

/// 请求 Body 编辑器的数据类型选项。
/// - NONE 表示请求不带 body（编辑器隐藏，发送时 body=null，并删除 Content-Type 头）。
/// - RAW 表示无高亮且不修改 Content-Type；
/// - 其余项对应一个 [ContentType]，用户手动切换时会写入 Content-Type 请求头。
enum _BodyLanguage {
  none,
  raw,
  text,
  json,
  xml,
  formUrl,
  formData,
}

class _HttpState extends State<_HttpWidget> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  /// 数据类型下拉显示的标签
  static const Map<_BodyLanguage, String> _bodyLanguageLabels = {
    _BodyLanguage.none: 'NONE',
    _BodyLanguage.raw: 'RAW',
    _BodyLanguage.text: 'TEXT',
    _BodyLanguage.json: 'JSON',
    _BodyLanguage.xml: 'XML',
    _BodyLanguage.formUrl: 'FORM-URL',
    _BodyLanguage.formData: 'FORM-DATA',
  };

  /// _BodyLanguage 与 ContentType 的对应关系；RAW/NONE 没有对应项
  static const Map<_BodyLanguage, ContentType> _bodyLanguageToContentType = {
    _BodyLanguage.text: ContentType.text,
    _BodyLanguage.json: ContentType.json,
    _BodyLanguage.xml: ContentType.xml,
    _BodyLanguage.formUrl: ContentType.formUrl,
    _BodyLanguage.formData: ContentType.formData,
  };

  /// 用户手动切换数据类型时，写入 Content-Type 请求头使用的 MIME。
  static const Map<_BodyLanguage, String> _bodyLanguageMime = {
    _BodyLanguage.text: 'text/plain',
    _BodyLanguage.json: 'application/json',
    _BodyLanguage.xml: 'application/xml',
    _BodyLanguage.formUrl: 'application/x-www-form-urlencoded',
    _BodyLanguage.formData: 'multipart/form-data',
  };

  final headerKey = GlobalKey<KeyValState>();
  Map<String, List<String>> initHeader = {};
  HttpMessage? message;
  CodeForgeController? body;

  /// FORM-DATA / FORM-URL 表单数据与 multipart boundary
  FormBody formData = FormBody();
  String _boundary = Multipart.newBoundary();
  final formEditorKey = GlobalKey<FormBodyEditorState>();

  /// 内层 Tab 控制器：Params(请求才有) / Headers / Body
  TabController? _innerTab;

  /// 当前编辑器使用的语言；初始化时按 Content-Type 推导
  _BodyLanguage _bodyLanguage = _BodyLanguage.none;
  bool _bodyWrap = true;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  bool get wantKeepAlive => true;

  /// 是否显示 URL Params 子 tab：仅请求消息且外层传了 query notifier 时
  bool get _hasParamsTab => widget.urlQueryNotifier != null;

  /// 可直接发送的 body 字节；NONE 返回 null。
  /// multipart 文本值在此渲染环境变量，同时把带 boundary 的 Content-Type 写回 header 行；
  /// 其余类型也在此渲染环境变量，调用方不再转换 body。
  List<int>? getBodyBytes() {
    switch (_bodyLanguage) {
      case _BodyLanguage.none:
        return null;
      case _BodyLanguage.formUrl:
        return FormUrl.buildBytes(formData);
      case _BodyLanguage.formData:
        headerKey.currentState
            ?.setParam('Content-Type', 'multipart/form-data; boundary=$_boundary');
        return Multipart.buildBytes(formData, boundary: _boundary);
      default:
        final text = body?.text ?? '';
        return utf8.encode(EnvironmentManager.tryRender(text) ?? text);
    }
  }

  @override
  void initState() {
    super.initState();
    message = widget.message;
    body = CodeForgeController()..text = widget.message?.bodyAsString ?? '';
    _bodyLanguage = _resolveLanguage(widget.message);
    _loadFormData(widget.message);
    _innerTab = TabController(length: _hasParamsTab ? 6 : 5, vsync: this, initialIndex: _hasParamsTab ? 1 : 0);
    if (widget.message?.headers == null && !widget.readOnly) {
      initHeader["User-Agent"] = ["QANIS/${AppConfiguration.version}"];
      initHeader["Accept"] = ["*/*"];
      return;
    }
  }

  @override
  void dispose() {
    body?.dispose();
    _innerTab?.dispose();
    super.dispose();
  }

  void change(HttpMessage? message) {
    this.message = message;
    body?.text = message?.bodyAsString ?? '';
    _bodyLanguage = _resolveLanguage(message);
    _loadFormData(message);
    headerKey.currentState?.refreshParam(message?.headers.getHeaders());
    setState(() {});
  }

  /// form-url / multipart 请求：解析已有 body 回填表单（multipart 保留原 boundary）；否则重置
  void _loadFormData(HttpMessage? msg) {
    final ct = msg?.headers.contentType.toLowerCase() ?? '';
    final msgBody = msg?.body;
    if (msgBody != null && msgBody.isNotEmpty) {
      if (ct.contains('multipart/form-data')) {
        formData = Multipart.parse(msgBody, ct);
        _boundary = Multipart.boundaryFromContentType(ct) ?? Multipart.newBoundary();
        return;
      }
      if (ct.contains('application/x-www-form-urlencoded')) {
        formData = FormUrl.parse(msgBody);
        return;
      }
    }
    formData = FormBody();
    _boundary = Multipart.newBoundary();
  }

  HttpHeaders? getHeaders() {
    return HttpHeaders.fromJson(headerKey.currentState?.getParams() ?? {});
  }

  /// 根据消息推断编辑器初始语言；初始化推断不会回写 header。
  /// - body 为空且方法是 GET/HEAD/DELETE/OPTIONS 或没有 Content-Type 头 → NONE
  /// - 其他情况按 Content-Type 头匹配，匹配不到归 TEXT
  _BodyLanguage _resolveLanguage(HttpMessage? message) {
    if (message == null) return _BodyLanguage.none;

    final bodyEmpty = message.bodyAsString.isEmpty;
    final hasContentType = message.headers.contentType.isNotEmpty;
    if (bodyEmpty && message is HttpRequest) {
      const noBodyMethods = {HttpMethod.get, HttpMethod.head, HttpMethod.delete, HttpMethod.options};
      if (noBodyMethods.contains(message.method) || !hasContentType) {
        return _BodyLanguage.none;
      }
    } else if (bodyEmpty && !hasContentType) {
      return _BodyLanguage.none;
    }

    final ct = message.contentType;
    for (final entry in _bodyLanguageToContentType.entries) {
      if (entry.value == ct) return entry.key;
    }
    return _BodyLanguage.json;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (message == null && widget.readOnly) {
      return Center(child: Text(localizations.emptyData));
    }

    final theme = Theme.of(context);

    final paramsTab = _hasParamsTab
        ? KeyValWidget(
            title: 'URL${localizations.param}',
            paramNotifier: widget.urlQueryNotifier,
            params: message is HttpRequest ? (message as HttpRequest).requestUri?.queryParametersAll : null,
            showTitle: false,
          )
        : null;

    final headersTab = KeyValWidget(
      title: "Headers",
      params: message?.headers.getHeaders() ?? initHeader,
      key: headerKey,
      suggestions: HttpHeaders.commonHeaderKeys,
      readOnly: widget.readOnly,
      showTitle: false,
    );

    return Padding(
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          widget.title,
          const SizedBox(height: 8),
          TabBar(
            controller: _innerTab,
            // 标签按文案自然宽度排布并左对齐；超出可用宽度时横向滚动，
            // 避免末尾标签（如 Body）被裁掉
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            // 收紧左右内边距，让三个标签在窄屏上一屏放下
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            labelColor: theme.colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              if (_hasParamsTab) Tab(text: 'Params', height: 36),
              const Tab(text: 'Headers', height: 36),
              const Tab(text: 'Body', height: 36),
              const Tab(text: 'Authorization', height: 36),
              const Tab(text: 'Docs', height: 36),
              const Tab(text: 'Settings', height: 36),
            ],
          ),
          const SizedBox(height: 6),
          // 这里用 IndexedStack 而非 TabBarView：
          // TabBarView 是惰性构建的，没访问过的 tab 不会 mount，
          // 用户直接发送时 headerKey.currentState 会是 null，导致 header 全丢。
          // IndexedStack 同时挂载所有子树（只显示一个），保证 GlobalKey 始终可达。
          Expanded(
            child: AnimatedBuilder(
              animation: _innerTab!,
              builder: (_, __) => IndexedStack(
                index: _innerTab!.index,
                children: [
                  if (paramsTab != null) SingleChildScrollView(child: paramsTab),
                  SingleChildScrollView(child: headersTab),
                  _body(),
                  SingleChildScrollView(child: _composerTab((req) => ComposerAuthTab(request: req))),
                  SingleChildScrollView(child: _composerTab((req) => ComposerDocsTab(request: req))),
                  SingleChildScrollView(child: _composerTab((req) => ComposerSettingsTab(request: req))),
                ],
              ),
            ),
          ),
        ]));
  }

  /// 新增的三个 tab 只对「请求」有意义；响应侧显示占位说明
  Widget _composerTab(Widget Function(HttpRequest request) builder) {
    final req = message;
    if (req is HttpRequest) {
      return builder(req);
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('Only available for a request',
          style: TextStyle(fontSize: 13, color: DarkPalette.text3)),
    );
  }

  Widget _body() {
    if (widget.readOnly) {
      return KeepAliveWrapper(child: SingleChildScrollView(child: HttpBodyWidget(httpMessage: message)));
    }

    if (_bodyLanguage == _BodyLanguage.formData || _bodyLanguage == _BodyLanguage.formUrl) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _bodyToolbar(),
        const SizedBox(height: 4),
        Expanded(child: FormBodyEditor(
          key: formEditorKey,
          form: formData,
          allowFiles: _bodyLanguage == _BodyLanguage.formData,
        )),
      ]);
    }

    final isCN = localizations.localeName == 'zh';
    final isNone = _bodyLanguage == _BodyLanguage.none;
    final ct = _bodyLanguageToContentType[_bodyLanguage];
    final language = ct == null ? null : HighlightLanguages.getLanguage(ct);
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final pageBg = Theme.of(context).colorScheme.surface;
    final editorTheme = isDark
        ? {
            ...baseTheme,
            'root': const TextStyle(color: Color(0xffabb2bf)).copyWith(backgroundColor: pageBg),
          }
        : baseTheme;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bodyToolbar(),
      const SizedBox(height: 4),
      Expanded(
        child: isNone
            ? Center(
                child: Text(
                  isCN ? '此请求无消息体' : 'This request has no body',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              )
            : Container(
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
                child: CodeForge(
                  // CodeForge 把 language 当作 late final 在 initState 里固定，
                  // 切换数据类型/换行后必须靠新的 key 重建组件才能生效；
                  // controller 由本 State 持有，重建不会丢文本。
                  key: ValueKey('body-editor-${_bodyLanguage.name}-$_bodyWrap'),
                  controller: body!,
                  lineWrap: _bodyWrap,
                  language: language,
                  enableGuideLines: false,
                  selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
                  editorTheme: editorTheme,
                  textStyle: const TextStyle(fontSize: 13),
                  finderBuilder: (c, controller) => FindPanelView(controller: controller),
                ),
              ),
      ),
    ]);
  }

  Widget _bodyToolbar() {
    final isCN = localizations.localeName == 'zh';
    final color = Theme.of(context).colorScheme.primary;
    // 窄屏（小屏手机）按钮只显示图标，避免工具栏溢出
    final narrow = MediaQuery.of(context).size.width < 380;
    // NONE 无 body；FORM-DATA/FORM-URL 由表单构建器管理，纯文本工具均不适用
    final textToolsDisabled = _bodyLanguage == _BodyLanguage.none ||
        _bodyLanguage == _BodyLanguage.formData ||
        _bodyLanguage == _BodyLanguage.formUrl;

    return SizedBox(
        height: 36,
        child: Row(children: [
          Text(isCN ? '数据类型' : 'Type', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<_BodyLanguage>(
              value: _bodyLanguage,
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              items: _BodyLanguage.values
                  .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(_bodyLanguageLabels[e] ?? e.name.toUpperCase(),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500))))
                  .toList(),
              onChanged: (val) {
                if (val == null || val == _bodyLanguage) return;
                setState(() => _bodyLanguage = val);
                _syncContentTypeHeader(val);
              },
            ),
          ),
          // FORM-DATA/FORM-URL：添加入口放工具栏（添加文本；multipart 另有选择文件）
          if (_bodyLanguage == _BodyLanguage.formData || _bodyLanguage == _BodyLanguage.formUrl) ...[
            const Spacer(),
            // 中文"添加文本"不空格，英文"Add Text"需空格
            () {
              final addTextLabel = isCN ? '${localizations.add}${localizations.text}'
                  : '${localizations.add} ${localizations.text}';
              return narrow
                  ? IconButton(
                      onPressed: () => formEditorKey.currentState?.addTextField(),
                      tooltip: addTextLabel,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.text_fields),
                    )
                  : TextButton.icon(
                      onPressed: () => formEditorKey.currentState?.addTextField(),
                      icon: const Icon(Icons.text_fields, size: 16),
                      label: Text(addTextLabel, style: const TextStyle(fontSize: 12.5)),
                    );
            }(),
            if (_bodyLanguage == _BodyLanguage.formData)
              narrow
                  ? IconButton(
                      onPressed: () => formEditorKey.currentState?.addFiles(),
                      tooltip: localizations.selectFile,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.upload_file),
                    )
                  : TextButton.icon(
                      onPressed: () => formEditorKey.currentState?.addFiles(),
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: Text(localizations.selectFile, style: const TextStyle(fontSize: 12.5)),
                    ),
          ],
          // 其他文本类型：换行/美化/复制
          if (!textToolsDisabled) ...[
            const Spacer(),
            IconButton(
              tooltip: localizations.wordWrap,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.wrap_text, color: _bodyWrap ? color : null),
              onPressed: () => setState(() => _bodyWrap = !_bodyWrap),
            ),
            IconButton(
              tooltip: localizations.format,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.auto_fix_high),
              onPressed: _beautifyBody,
            ),
            IconButton(
              tooltip: localizations.copy,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy),
              onPressed: () {
                final text = body?.text ?? '';
                if (text.isEmpty) return;
                Clipboard.setData(ClipboardData(text: text));
                FlutterToastr.show(localizations.copied, context);
              },
            ),
          ],
        ]));
  }

  /// 用户主动切换数据类型时，把 Content-Type 请求头改成对应 MIME。
  /// - NONE：删除 Content-Type；body 不发。
  /// - RAW：保持原 header 不动。
  /// - 其他：写入对应 MIME。
  void _syncContentTypeHeader(_BodyLanguage lang) {
    if (lang == _BodyLanguage.raw) return;
    final headerState = headerKey.currentState;
    if (headerState == null) return;

    // FORM-DATA 需要带上 boundary 才是合法的 Content-Type
    if (lang == _BodyLanguage.formData) {
      headerState.setParam('Content-Type', 'multipart/form-data; boundary=$_boundary');
      return;
    }

    if (lang == _BodyLanguage.none) {
      headerState.removeParam('Content-Type');
      return;
    }

    String mime = _bodyLanguageMime[lang] ?? 'text/plain';
    headerState.setParam('Content-Type', mime);
  }

  /// 根据当前数据类型对 body 文本做格式化
  void _beautifyBody() {
    final controller = body;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;
    String formatted;
    switch (_bodyLanguage) {
      case _BodyLanguage.json:
        formatted = JSON.pretty(text);
        break;
      case _BodyLanguage.xml:
        formatted = XML.pretty(text);
        break;
      default:
        FlutterToastr.show(
            localizations.localeName == 'zh' ? '当前数据类型不支持美化' : 'Beautify is not supported for this type', context);
        return;
    }
    if (formatted != text) {
      controller.text = formatted;
    }
  }
}

class _RequestLine extends StatefulWidget {
  final HttpRequest? request;
  final UrlQueryNotifier? urlQueryNotifier;

  const _RequestLine({this.request, super.key, this.urlQueryNotifier});

  @override
  State<StatefulWidget> createState() {
    return _RequestLineState();
  }
}

class _RequestLineState extends State<_RequestLine> {
  EnvHighlightTextEditingController requestUrl = EnvHighlightTextEditingController(text: "");
  HttpMethod requestMethod = HttpMethod.get;

  @override
  void initState() {
    super.initState();
    widget.urlQueryNotifier?.paramListener((param) => onQueryChange(param));
    if (widget.request == null) {
      requestUrl.text = 'https://';
      return;
    }
    var request = widget.request!;
    requestUrl.text = request.requestUrl;
    requestMethod = request.method;
  }

  @override
  dispose() {
    requestUrl.dispose();
    super.dispose();
  }

  void change(String? requestUrl, HttpMethod? requestMethod) {
    this.requestUrl.text = requestUrl ?? this.requestUrl.text;
    this.requestMethod = requestMethod ?? this.requestMethod;

    urlNotifier();
  }

  void urlNotifier() {
    var splitFirst = requestUrl.text.splitFirst("?".codeUnits.first);
    widget.urlQueryNotifier?.onUrlChange(splitFirst.length > 1 ? splitFirst.last : '');
  }

  void onQueryChange(String query) {
    var url = requestUrl.text;
    var indexOf = url.indexOf("?");
    if (indexOf == -1) {
      requestUrl.text = "$url?$query";
    } else {
      requestUrl.text = "${url.substring(0, indexOf)}?$query";
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    TextInput;
    return TextField(
        style: const TextStyle(fontSize: 14),
        minLines: 1,
        maxLines: 3,
        autofocus: false,
        controller: requestUrl,
        decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
              child: MethodPopupMenu(
                value: requestMethod,
                showSeparator: true,
                onChanged: (val) {
                  setState(() => requestMethod = val!);
                },
              ),
            ),
            isDense: true,
            border: const OutlineInputBorder(borderSide: BorderSide()),
            enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey, width: 0.3))),
        onChanged: (value) {
          urlNotifier();
        });
  }
}

class KeyVal {
  bool enabled = true;
  String key;
  String value;

  KeyVal(this.key, this.value);
}

///key value
class KeyValWidget extends StatefulWidget {
  final String title;
  final Map<String, List<String>>? params;
  final bool readOnly; //只读
  final UrlQueryNotifier? paramNotifier;
  final bool expanded;
  final List<String>? suggestions;

  /// 是否使用 ExpansionTile 包裹自带标题；
  /// 内层 Tab 模式下 tab 已经标了名字，传 false 直接渲染列表更干净。
  final bool showTitle;

  const KeyValWidget(
      {super.key,
      this.params,
      this.readOnly = false,
      this.paramNotifier,
      required this.title,
      this.expanded = true,
      this.suggestions,
      this.showTitle = true});

  @override
  State<StatefulWidget> createState() {
    return KeyValState();
  }
}

final Map<String, bool> _expanded = {};

class KeyValState extends State<KeyValWidget> with AutomaticKeepAliveClientMixin {
  final List<KeyVal> _params = [];

  /// 清空所有键值行（供「Clear」菜单使用）
  void clearAll() {
    setState(() => _params.clear());
  }

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.params?.forEach((name, values) {
      for (var val in values) {
        var keyVal = KeyVal(name, val);
        _params.add(keyVal);
      }
    });

    widget.paramNotifier?.urlListener((url) => onChange(url));
  }

  //监听url发生变化 更改表单
  void onChange(String value) {
    var query = value.split("&");
    int index = 0;
    while (index < query.length) {
      var splitFirst = query[index].splitFirst('='.codeUnits.first);
      String key = splitFirst.first;
      String? val = splitFirst.length == 1 ? null : splitFirst.last;
      if (_params.length <= index) {
        _params.add(KeyVal(key, val ?? ''));
        continue;
      }

      var keyVal = _params[index++];
      keyVal.key = key;
      keyVal.value = val ?? '';
    }

    _params.length = index;
    setState(() {});
  }

  void notifierChange() {
    if (widget.paramNotifier == null) return;
    String query = _params
        .where((e) => e.enabled && e.key.isNotEmpty)
        .map((e) => "${e.key}=${e.value}".replaceAll("&", "%26"))
        .join("&");
    widget.paramNotifier?.onParamChange(query);
  }

  ///获取所有请求头
  Map<String, List<String>> getParams() {
    Map<String, List<String>> map = {};
    for (var keVal in _params) {
      if (keVal.key.isEmpty || !keVal.enabled) {
        continue;
      }
      map[keVal.key] ??= [];
      map[keVal.key]!.add(keVal.value);
    }

    return map;
  }

  Future<void> _copyParam(KeyVal keyVal) async {
    final text = '${keyVal.key}: ${keyVal.value}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    FlutterToastr.show(localizations.copied, context);
  }

  //刷新param
  void refreshParam(Map<String, List<String>>? headers) {
    _params.clear();
    setState(() {
      headers?.forEach((name, values) {
        for (var val in values) {
          _params.add(KeyVal(name, val));
        }
      });
    });
  }

  /// 设置或更新单条 header（不区分大小写匹配 key）。已存在则原地改 value，不存在则追加。
  void setParam(String name, String value) {
    KeyVal? matched;
    for (var kv in _params) {
      if (kv.key.toLowerCase() == name.toLowerCase()) {
        matched = kv;
        break;
      }
    }
    setState(() {
      if (matched != null) {
        matched.enabled = true;
        matched.key = name;
        matched.value = value;
      } else {
        _params.add(KeyVal(name, value));
      }
    });
    notifierChange();
  }

  /// 删除指定 header（不区分大小写匹配 key）。
  void removeParam(String name) {
    final before = _params.length;
    setState(() => _params.removeWhere((kv) => kv.key.toLowerCase() == name.toLowerCase()));
    if (_params.length != before) notifierChange();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final addBtn = widget.readOnly
        ? const SizedBox()
        : Container(
            alignment: Alignment.center,
            child: TextButton(
                onPressed: () {
                  var keyVal = KeyVal("", "");
                  _params.add(keyVal);
                  modifyParam(keyVal);
                },
                child: Text(localizations.add, textAlign: TextAlign.center))); //添加按钮

    if (!widget.showTitle) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [..._buildRows(), addBtn],
      );
    }

    return ExpansionTile(
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blue)),
      tilePadding: const EdgeInsets.only(left: 0, top: 10, bottom: 10),
      initiallyExpanded: _expanded[widget.title] ?? widget.expanded,
      onExpansionChanged: (value) => _expanded[widget.title] = value,
      shape: const Border(),
      children: [..._buildRows(), addBtn],
    );
  }

  List<Widget> _buildRows() {
    List<Widget> list = [];

    for (var element in _params) {
      Widget headerWidget = Padding(padding: const EdgeInsets.only(top: 5, bottom: 5), child: row(element));
      headerWidget = InkWell(
        onTap: () => modifyParam(element),
        onLongPress: widget.readOnly ? () => _copyParam(element) : () => deleteHeader(element),
        child: headerWidget,
      );

      list.add(headerWidget);
      list.add(const Divider(thickness: 0.2));
    }

    return list;
  }

  //隐藏输入框焦点
  void hideKeyword(BuildContext context) {
    FocusScopeNode currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.focusedChild?.unfocus();
    }
  }

  /// 修改请求头
  void modifyParam(KeyVal keyVal) {
    //隐藏输入框焦点
    hideKeyword(context);
    String headerName = keyVal.key;
    String val = keyVal.value;
    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              titlePadding: const EdgeInsets.only(left: 25, top: 10),
              actionsPadding: const EdgeInsets.only(right: 10, bottom: 10),
              title: Text(widget.readOnly ? localizations.responseHeader : localizations.modifyRequestHeader,
                  style: const TextStyle(fontSize: 16)),
              content: Wrap(
                children: [
                  if (widget.suggestions != null && !widget.readOnly)
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        return widget.suggestions!.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        setState(() {
                          headerName = selection;
                        });
                      },
                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController,
                          FocusNode focusNode, VoidCallback onFieldSubmitted) {
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 3,
                          decoration: InputDecoration(labelText: localizations.headerName),
                          onChanged: (value) {
                            headerName = value;
                            setState(() {});
                          },
                        );
                      },
                      initialValue: TextEditingValue(text: headerName),
                      optionsViewBuilder:
                          (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () {
                                      onSelected(option);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(10.0),
                                      child: _buildHighlightText(option, headerName),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  else
                    TextFormField(
                      minLines: 1,
                      maxLines: 3,
                      initialValue: headerName,
                      readOnly: widget.readOnly,
                      decoration: InputDecoration(labelText: localizations.headerName),
                      onChanged: (value) {
                        headerName = value;
                        setState(() {});
                      },
                    ),
                  if (HttpHeaders.commonHeaderValues.containsKey(headerName) && !widget.readOnly)
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        return HttpHeaders.commonHeaderValues[headerName]!.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        val = selection;
                      },
                      fieldViewBuilder: (BuildContext context, TextEditingController textEditingController,
                          FocusNode focusNode, VoidCallback onFieldSubmitted) {
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 8,
                          decoration: InputDecoration(labelText: localizations.value),
                          onChanged: (value) => val = value,
                        );
                      },
                      initialValue: TextEditingValue(text: val),
                      optionsViewBuilder:
                          (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () {
                                      onSelected(option);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(10.0),
                                      child: _buildHighlightText(option, val),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  else
                    TextFormField(
                      minLines: 1,
                      maxLines: 8,
                      initialValue: val,
                      readOnly: widget.readOnly,
                      decoration: InputDecoration(labelText: localizations.value),
                      onChanged: (value) => val = value,
                    )
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(widget.readOnly ? localizations.close : localizations.cancel)),
                if (!widget.readOnly)
                  TextButton(
                      onPressed: () {
                        this.setState(() {
                          keyVal.key = headerName;
                          keyVal.value = val;
                        });
                        notifierChange();
                        Navigator.pop(ctx);
                      },
                      child: Text(localizations.modify)),
              ],
            );
          });
        });
  }

  //删除
  void deleteHeader(KeyVal keyVal) {
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(localizations.deleteHeaderConfirm, style: const TextStyle(fontSize: 18)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
              TextButton(
                  onPressed: () {
                    setState(() => _params.remove(keyVal));
                    notifierChange();
                    Navigator.pop(ctx);
                  },
                  child: Text(localizations.delete)),
            ],
          );
        });
  }

  Widget row(KeyVal keyVal) {
    return Row(children: [
      if (!widget.readOnly)
        Checkbox(
            value: keyVal.enabled,
            onChanged: (val) {
              setState(() {
                keyVal.enabled = val!;
              });
              notifierChange();
            }),
      Expanded(flex: 4, child: Text(keyVal.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      const Text(":", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Expanded(
        flex: 6,
        child: buildEnvHighlightText(context, keyVal.value,
            style: const TextStyle(fontSize: 13), maxLines: 5, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }

  Widget _buildHighlightText(String text, String query) {
    if (query.isEmpty) {
      return Text(text);
    }

    int index = text.toLowerCase().indexOf(query.toLowerCase());
    if (index < 0) {
      return Text(text);
    }

    return Text.rich(TextSpan(children: [
      TextSpan(text: text.substring(0, index)),
      TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
      TextSpan(text: text.substring(index + query.length))
    ]));
  }
}

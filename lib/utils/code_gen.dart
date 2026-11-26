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

/// 把捕获到的 [HttpRequest] 转换成各语言可直接粘贴运行的客户端代码。
///
/// 约定：
/// * 头部按 RFC 9110 合并同名多值（`, `），`Cookie` 用 `; ` 合并成一条；
///   `Content-Length` / `Host` / `Connection` / `Transfer-Encoding` /
///   `Expect` / `Upgrade` / `Proxy-*` 由客户端自动生成或只与代理链路有关，
///   一律丢弃。
/// * JSON body 解析成功时输出真正的对象/字典/结构体，否则输出原始文本；
///   `application/x-www-form-urlencoded` 在支持的语言里输出表单字典。
/// * 二进制 body（multipart 文件等）无法还原成文本，输出 `<binary body: N bytes>`
///   占位（cURL 输出 `--data-binary '@body.bin'`），需要用户自行补上文件。
/// * 所有目标都带超时，并在结尾打印状态码与响应体。
///
/// 语言版本假设：Java 15+（文本块）、OkHttp 4+、Kotlin 1.5+、
/// C# 11（原始字符串）、Rust reqwest 0.11 + tokio、ureq 2.x、
/// PowerShell 7+（`-StatusCodeVariable` / `-CustomMethod`）、Go 1.18+（`any`）。
library;

import 'dart:convert';

import 'package:qanis/network/http/http.dart';

/// 代码生成目标：一种语言 + 一个 HTTP 客户端库。
///
/// @author wanghongen
class CodeTarget {
  /// 唯一标识，例如 `python-requests`。
  final String id;

  /// 选择器中显示的名字，例如 `Python · requests`。
  final String label;

  /// 语法高亮提示：`python`、`rust`、`go`、`java`、`kotlin`、`csharp`、
  /// `php`、`ruby`、`swift`、`dart`、`js`、`shell`、`http`。
  final String language;

  const CodeTarget(this.id, this.label, this.language);
}

/// 代码生成目标列表，顺序即选择器中的展示顺序。
const List<CodeTarget> kCodeTargets = <CodeTarget>[
  CodeTarget('curl', 'Shell · cURL', 'shell'),
  CodeTarget('httpie', 'Shell · HTTPie', 'shell'),
  CodeTarget('python-requests', 'Python · requests', 'python'),
  CodeTarget('python-httpclient', 'Python · http.client', 'python'),
  CodeTarget('python-httpx', 'Python · httpx', 'python'),
  CodeTarget('python-aiohttp', 'Python · aiohttp', 'python'),
  CodeTarget('node-fetch', 'Node · fetch', 'js'),
  CodeTarget('node-axios', 'Node · axios', 'js'),
  CodeTarget('node-native', 'Node · http/https', 'js'),
  CodeTarget('rust-reqwest', 'Rust · reqwest (async, tokio)', 'rust'),
  CodeTarget('rust-ureq', 'Rust · ureq (blocking)', 'rust'),
  CodeTarget('go-nethttp', 'Go · net/http', 'go'),
  CodeTarget('java-okhttp', 'Java · OkHttp', 'java'),
  CodeTarget('java-httpclient', 'Java · HttpClient (java.net.http)', 'java'),
  CodeTarget('kotlin-okhttp', 'Kotlin · OkHttp', 'kotlin'),
  CodeTarget('csharp-httpclient', 'C# · HttpClient', 'csharp'),
  CodeTarget('php-curl', 'PHP · cURL', 'php'),
  CodeTarget('ruby-nethttp', 'Ruby · Net::HTTP', 'ruby'),
  CodeTarget('swift-urlsession', 'Swift · URLSession', 'swift'),
  CodeTarget('dart-http', 'Dart · http', 'dart'),
  CodeTarget('powershell', 'PowerShell · Invoke-RestMethod', 'powershell'),
  CodeTarget('raw-http', 'Raw HTTP/1.1', 'http'),
];

/// 生成 [request] 在语言 [id] 下的客户端代码；未知的 id 回退到 cURL。
String generateCode(String id, HttpRequest request) {
  final ctx = _Ctx(request);
  switch (id) {
    case 'httpie':
      return _httpie(ctx);
    case 'python-requests':
      return _pythonRequests(ctx);
    case 'python-httpclient':
      return _pythonHttpClient(ctx);
    case 'python-httpx':
      return _pythonHttpx(ctx);
    case 'python-aiohttp':
      return _pythonAiohttp(ctx);
    case 'node-fetch':
      return _nodeFetch(ctx);
    case 'node-axios':
      return _nodeAxios(ctx);
    case 'node-native':
      return _nodeNative(ctx);
    case 'rust-reqwest':
      return _rustReqwest(ctx);
    case 'rust-ureq':
      return _rustUreq(ctx);
    case 'go-nethttp':
      return _goNetHttp(ctx);
    case 'java-okhttp':
      return _javaOkHttp(ctx);
    case 'java-httpclient':
      return _javaHttpClient(ctx);
    case 'kotlin-okhttp':
      return _kotlinOkHttp(ctx);
    case 'csharp-httpclient':
      return _csharpHttpClient(ctx);
    case 'php-curl':
      return _phpCurl(ctx);
    case 'ruby-nethttp':
      return _rubyNetHttp(ctx);
    case 'swift-urlsession':
      return _swiftUrlSession(ctx);
    case 'dart-http':
      return _dartHttp(ctx);
    case 'powershell':
      return _powershell(ctx);
    case 'raw-http':
      return _rawHttp(ctx);
    case 'curl':
    default:
      return _curl(ctx);
  }
}

// ---------------------------------------------------------------------------
// 生成上下文
// ---------------------------------------------------------------------------

/// 一条 HTTP 头。同名多值已在 [_Ctx] 中按 RFC 9110 合并（Cookie 除外）。
class _Header {
  final String name;
  final String value;

  const _Header(this.name, this.value);
}

/// 这些头由客户端自动生成，或者只对代理链路有意义，生成代码时一律丢弃。
const Set<String> _kDroppedHeaders = {
  'content-length',
  'host',
  'connection',
  'transfer-encoding',
  'expect',
  'upgrade',
  'proxy-authorization',
  'proxy-connection',
};

/// 被捕获的请求在生成代码时所需的全部信息。
class _Ctx {
  /// 大写方法名，如 `POST`。
  final String method;

  /// 完整 URL。
  final String url;

  /// 解析后的 URL，解析失败时为空 Uri。
  final Uri uri;

  /// 已过滤、已合并的头（Cookie 合并为一条）。
  final List<_Header> headers;

  /// 原始请求体文本；无 body 时为 null；二进制 body 时为占位说明。
  final String? body;

  /// body 是否为不可读的二进制（此时 [body] 只是占位文本）。
  final bool binary;

  /// JSON body 解析后的对象；不是 JSON 或解析失败时为 null。
  final Object? json;

  /// `application/x-www-form-urlencoded` body 解析后的字段；否则为 null。
  final Map<String, String>? form;

  final bool isJson;

  _Ctx._({
    required this.method,
    required this.url,
    required this.uri,
    required this.headers,
    required this.body,
    required this.binary,
    required this.json,
    required this.form,
    required this.isJson,
  });

  factory _Ctx(HttpRequest request) {
    final String url = request.requestUrl;
    final method = request.method.name.toUpperCase();

    // 头：跳过自动生成的头，同名多值用 ", " 合并，Cookie 用 "; " 合并成一条。
    final merged = <_Header>[];
    final cookies = <String>[];
    request.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (_kDroppedHeaders.contains(lower)) return;
      if (lower == 'cookie') {
        for (final value in values) {
          if (value.trim().isNotEmpty) cookies.add(value.trim());
        }
        return;
      }
      merged.add(_Header(name, values.join(', ')));
    });
    if (cookies.isNotEmpty) {
      merged.add(_Header('Cookie', cookies.join('; ')));
    }

    final contentType = request.headers.contentType.toLowerCase();
    final isJson = contentType.contains('application/json') ||
        contentType.contains('+json');
    final isForm = contentType.contains('application/x-www-form-urlencoded');

    final rawBytes = request.body;
    String? text;
    var binary = false;
    if (rawBytes != null && rawBytes.isNotEmpty) {
      final decoded = request.bodyAsString;
      if (_isTextual(decoded)) {
        text = decoded;
      } else {
        binary = true;
      }
    }

    Object? json;
    Map<String, String>? form;
    if (text != null && text.isNotEmpty) {
      if (isJson) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map || decoded is List) json = decoded;
        } catch (_) {
          // 非法 JSON：按原始文本处理
        }
      } else if (isForm) {
        form = _parseForm(text);
      }
    }

    return _Ctx._(
      method: method,
      url: url,
      uri: Uri.tryParse(url) ?? Uri(),
      headers: merged,
      body: rawBytes == null || rawBytes.isEmpty
          ? null
          : (binary ? '<binary body: ${rawBytes.length} bytes>' : text),
      binary: binary,
      json: json,
      form: form,
      isJson: isJson,
    );
  }

  /// 去掉 `content-type` 后的头（由客户端库自行设置时使用）。
  List<_Header> get headersWithoutContentType =>
      headers.where((h) => h.name.toLowerCase() != 'content-type').toList();

  /// 去掉 `cookie` 后的头。
  List<_Header> get headersWithoutCookie =>
      headers.where((h) => h.name.toLowerCase() != 'cookie').toList();

  /// 请求体文本：JSON 时输出格式化后的 JSON，其余情况输出原始文本。
  String get jsonText {
    if (json == null) return body ?? '';
    return _prettyJson(json);
  }

  /// 解析出的 cookie 键值对。
  Map<String, String> get cookiePairs => _parseCookies(headers);
}

/// body 是否是可直接按文本输出的内容。
bool _isTextual(String value) {
  for (final code in value.codeUnits) {
    if (code == 0xFFFD) return false;
    if (code < 0x20 && code != 0x09 && code != 0x0A && code != 0x0D)
      return false;
  }
  return true;
}

Map<String, String>? _parseForm(String text) {
  final result = <String, String>{};
  try {
    for (final pair in text.split('&')) {
      if (pair.isEmpty) continue;
      final index = pair.indexOf('=');
      final name =
          Uri.decodeQueryComponent(index < 0 ? pair : pair.substring(0, index));
      final value =
          Uri.decodeQueryComponent(index < 0 ? '' : pair.substring(index + 1));
      result[name] = value;
    }
  } catch (_) {
    return null;
  }
  return result.isEmpty ? null : result;
}

Map<String, String> _parseCookies(List<_Header> headers) {
  final result = <String, String>{};
  for (final header in headers) {
    if (header.name.toLowerCase() != 'cookie') continue;
    for (final pair in header.value.split(';')) {
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      if (name.isEmpty) continue;
      result[name] = pair.substring(index + 1).trim();
    }
  }
  return result;
}

/// 取第一个同名头的值（已合并），不存在时返回 null。
String? _headerValue(_Ctx ctx, String name) {
  for (final header in ctx.headers) {
    if (header.name.toLowerCase() == name) return header.value;
  }
  return null;
}

/// 请求路径 + 查询串，至少是 `/`。
String _pathAndQuery(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}

/// 端口：URL 显式指定时用它，否则按 scheme 取默认值。
int _portOf(Uri uri) {
  if (uri.hasPort) return uri.port;
  return uri.scheme == 'https' ? 443 : 80;
}

bool _isStandardMethod(String method) {
  return const {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'}
      .contains(method);
}

/// 给多行文本的每一行加上缩进。
String _indent(String text, String pad) {
  return text
      .split('\n')
      .map((line) => line.isEmpty ? line : '$pad$line')
      .join('\n');
}

/// 给多行文本除首行外的每一行加上缩进（用于 `x = {...}` 这种内联场景）。
String _indentRest(String text, String pad) {
  final lines = text.split('\n');
  if (lines.length < 2) return text;
  return [
    lines.first,
    ...lines.skip(1).map((line) => line.isEmpty ? line : '$pad$line')
  ].join('\n');
}

String _prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

// ---------------------------------------------------------------------------
// 字符串转义
// ---------------------------------------------------------------------------

/// C 系语言的双引号转义（JS / Go / Java / C# / Dart / Python / Kotlin 通用形式）。
String _escDq(String input) {
  final sb = StringBuffer();
  for (final code in input.runes) {
    switch (code) {
      case 0x5C:
        sb.write(r'\\');
      case 0x22:
        sb.write(r'\"');
      case 0x0A:
        sb.write(r'\n');
      case 0x0D:
        sb.write(r'\r');
      case 0x09:
        sb.write(r'\t');
      default:
        if (code < 0x20) {
          sb.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
        } else {
          sb.writeCharCode(code);
        }
    }
  }
  return sb.toString();
}

/// Rust / Swift 的双引号转义：非打印字符用 `\u{..}`。
String _escBrace(String input) {
  final sb = StringBuffer();
  for (final code in input.runes) {
    switch (code) {
      case 0x5C:
        sb.write(r'\\');
      case 0x22:
        sb.write(r'\"');
      case 0x0A:
        sb.write(r'\n');
      case 0x0D:
        sb.write(r'\r');
      case 0x09:
        sb.write(r'\t');
      default:
        if (code < 0x20) {
          sb.write('\\u{${code.toRadixString(16)}}');
        } else {
          sb.writeCharCode(code);
        }
    }
  }
  return sb.toString();
}

/// Python / Dart 单引号字符串内容。
String _escSq(String input) {
  final sb = StringBuffer();
  for (final code in input.runes) {
    switch (code) {
      case 0x5C:
        sb.write(r'\\');
      case 0x27:
        sb.write(r"\'");
      case 0x0A:
        sb.write(r'\n');
      case 0x0D:
        sb.write(r'\r');
      case 0x09:
        sb.write(r'\t');
      default:
        if (code < 0x20) {
          sb.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
        } else {
          sb.writeCharCode(code);
        }
    }
  }
  return sb.toString();
}

/// Ruby 双引号字符串内容（顺带转义 `#`，避免 `#{}` 插值）。
String _escRuby(String input) {
  final sb = StringBuffer();
  for (final code in input.runes) {
    switch (code) {
      case 0x5C:
        sb.write(r'\\');
      case 0x22:
        sb.write(r'\"');
      case 0x23:
        sb.write(r'\#');
      case 0x0A:
        sb.write(r'\n');
      case 0x0D:
        sb.write(r'\r');
      case 0x09:
        sb.write(r'\t');
      default:
        if (code < 0x20) {
          sb.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
        } else {
          sb.writeCharCode(code);
        }
    }
  }
  return sb.toString();
}

/// PHP 双引号字符串内容（`$` 必须转义，否则会被插值）。
String _escPhp(String input) {
  final sb = StringBuffer();
  for (final code in input.runes) {
    switch (code) {
      case 0x5C:
        sb.write(r'\\');
      case 0x22:
        sb.write(r'\"');
      case 0x24:
        sb.write(r'\$');
      case 0x0A:
        sb.write(r'\n');
      case 0x0D:
        sb.write(r'\r');
      case 0x09:
        sb.write(r'\t');
      default:
        if (code < 0x20) {
          sb.write('\\x${code.toRadixString(16).padLeft(2, '0')}');
        } else {
          sb.writeCharCode(code);
        }
    }
  }
  return sb.toString();
}

/// Shell 单引号字符串：内部单引号写成 `'\''`。
String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

/// PowerShell 单引号字符串：内部单引号写成 `''`，可跨行。
String _psStr(String value) => "'${value.replaceAll("'", "''")}'";

String _q(String value) => '"${_escDq(value)}"';

String _sq(String value) => "'${_escSq(value)}'";

/// Dart 单引号字符串：除 [_escSq] 外还需转义 `$`，否则会变成插值。
String _dartStr(String value) => "'${_escSq(value).replaceAll(r'$', r'\$')}'";

String _phpStr(String value) => '"${_escPhp(value)}"';

String _rbStr(String value) => '"${_escRuby(value)}"';

String _rustStr(String value) => '"${_escBrace(value)}"';

String _swiftStr(String value) => '"${_escBrace(value)}"';

/// Rust 原始字符串，body 里含 `"#` 时退回普通转义字符串。
String _rustRaw(String text) {
  if (text.contains('"#')) return _rustStr(text);
  return 'r#"$text"#';
}

// ---------------------------------------------------------------------------
// 字面量格式化
// ---------------------------------------------------------------------------

/// 一种语言里"结构化字面量"的写法差异。
class _Syntax {
  /// 字符串：输入内容，输出完整字面量（含引号）。
  final String Function(String) quote;
  final String trueLit;
  final String falseLit;
  final String nullLit;
  final String mapOpen;
  final String mapClose;
  final String mapSep;
  final String listOpen;
  final String listClose;
  final String unit;

  const _Syntax({
    required this.quote,
    required this.trueLit,
    required this.falseLit,
    required this.nullLit,
    required this.mapOpen,
    required this.mapClose,
    required this.mapSep,
    required this.listOpen,
    required this.listClose,
    required this.unit,
  });
}

final _Syntax _pythonSyntax = _Syntax(
  quote: _sq,
  trueLit: 'True',
  falseLit: 'False',
  nullLit: 'None',
  mapOpen: '{',
  mapClose: '}',
  mapSep: ': ',
  listOpen: '[',
  listClose: ']',
  unit: '    ',
);

final _Syntax _dartSyntax = _Syntax(
  quote: _dartStr,
  trueLit: 'true',
  falseLit: 'false',
  nullLit: 'null',
  mapOpen: '{',
  mapClose: '}',
  mapSep: ': ',
  listOpen: '[',
  listClose: ']',
  unit: '  ',
);

final _Syntax _phpSyntax = _Syntax(
  quote: _phpStr,
  trueLit: 'true',
  falseLit: 'false',
  nullLit: 'null',
  mapOpen: '[',
  mapClose: ']',
  mapSep: ' => ',
  listOpen: '[',
  listClose: ']',
  unit: '    ',
);

final _Syntax _rubySyntax = _Syntax(
  quote: _rbStr,
  trueLit: 'true',
  falseLit: 'false',
  nullLit: 'nil',
  mapOpen: '{',
  mapClose: '}',
  mapSep: ' => ',
  listOpen: '[',
  listClose: ']',
  unit: '  ',
);

final _Syntax _goSyntax = _Syntax(
  quote: _q,
  trueLit: 'true',
  falseLit: 'false',
  nullLit: 'nil',
  mapOpen: 'map[string]any{',
  mapClose: '}',
  mapSep: ': ',
  listOpen: '[]any{',
  listClose: '}',
  unit: '    ',
);

final _Syntax _swiftSyntax = _Syntax(
  quote: _swiftStr,
  trueLit: 'true',
  falseLit: 'false',
  nullLit: 'NSNull()',
  mapOpen: '[',
  mapClose: ']',
  mapSep: ': ',
  listOpen: '[',
  listClose: ']',
  unit: '    ',
);

String _formatLiteral(Object? value, _Syntax syntax, [int depth = 0]) {
  final pad = syntax.unit * depth;
  final childPad = syntax.unit * (depth + 1);
  const comma = ',';

  if (value == null) return syntax.nullLit;
  if (value is bool) return value ? syntax.trueLit : syntax.falseLit;
  if (value is num) return value.toString();
  if (value is String) return syntax.quote(value);

  if (value is List) {
    if (value.isEmpty) return '${syntax.listOpen}${syntax.listClose}';
    final items = value
        .map((item) =>
            '$childPad${_formatLiteral(item, syntax, depth + 1)}$comma')
        .join('\n');
    return '${syntax.listOpen}\n$items\n$pad${syntax.listClose}';
  }

  if (value is Map) {
    if (value.isEmpty) return '${syntax.mapOpen}${syntax.mapClose}';
    final entries = value.entries
        .map((entry) =>
            '$childPad${syntax.quote(entry.key.toString())}${syntax.mapSep}'
            '${_formatLiteral(entry.value, syntax, depth + 1)}$comma')
        .join('\n');
    return '${syntax.mapOpen}\n$entries\n$pad${syntax.mapClose}';
  }

  return syntax.quote(value.toString());
}

// ---------------------------------------------------------------------------
// 文本块（Java / Kotlin / C# / Swift 的多行字符串）
// ---------------------------------------------------------------------------

/// Java 文本块：`\` 与 `"""` 需要转义。
String _javaBlock(String text, String pad) {
  final safe = text.replaceAll('\\', '\\\\').replaceAll('"""', '\\"\\"\\"');
  return '"""\n${_indent(safe, pad)}\n$pad"""';
}

/// Kotlin 原始字符串：只有 `$` 与 `"""` 需要处理。
String _kotlinBlock(String text, String pad) {
  final safe = text
      .replaceAll(r'$', r"${'$'}")
      .replaceAll('"""', '""' + "\${'\"'}" + '"');
  return '"""\n${_indent(safe, pad)}\n$pad""".trimIndent()';
}

/// C# 原始字符串字面量：不做转义；body 含 `"""` 时退回普通转义字符串。
String _csharpBlock(String text, String pad) {
  if (text.contains('"""')) {
    return _q(text);
  }
  return '"""\n${_indent(text, pad)}\n$pad"""';
}

/// Swift 多行字符串：`\` 与 `"""` 需要转义。
String _swiftBlock(String text, String pad) {
  final safe = text.replaceAll('\\', '\\\\').replaceAll('"""', '\\"\\"\\"');
  return '"""\n${_indent(safe, pad)}\n$pad"""';
}

// ---------------------------------------------------------------------------
// 1. Shell · cURL
// ---------------------------------------------------------------------------

String _curl(_Ctx ctx) {
  final lines = <String>['curl -X ${ctx.method} ${_shellQuote(ctx.url)}'];

  for (final header in ctx.headers) {
    lines.add('  -H ${_shellQuote('${header.name}: ${header.value}')}');
  }

  if (ctx.body != null) {
    if (ctx.binary) {
      lines.add("  --data-binary '@body.bin'");
    } else {
      lines.add('  --data-raw ${_shellQuote(ctx.jsonText)}');
    }
  }

  lines.add('  --max-time 30');

  return '${lines.join(' \\\n')}\n';
}

// ---------------------------------------------------------------------------
// 2. Shell · HTTPie
// ---------------------------------------------------------------------------

String _httpie(_Ctx ctx) {
  final lines = <String>[
    'http --timeout=30 ${ctx.method} ${_shellQuote(ctx.url)}'
  ];

  for (final header in ctx.headers) {
    lines.add('  ${_shellQuote('${header.name}: ${header.value}')}');
  }

  if (ctx.body == null || ctx.binary) {
    return '${lines.join(' \\\n')}\n';
  }

  lines[lines.length - 1] = "${lines.last} <<'BODY'";
  return '${lines.join(' \\\n')}\n${ctx.jsonText}\nBODY\n';
}

// ---------------------------------------------------------------------------
// 3. Python · requests
// ---------------------------------------------------------------------------

String _pythonRequests(_Ctx ctx) {
  final sb = StringBuffer();
  final cookies = ctx.cookiePairs;
  final structured = ctx.json != null || ctx.form != null;

  final headers = ctx.headersWithoutCookie.where((h) {
    if (!structured) return true;
    return h.name.toLowerCase() != 'content-type';
  }).toList();

  sb.writeln('import requests');
  sb.writeln();
  sb.writeln('url = ${_sq(ctx.url)}');
  sb.writeln();

  if (cookies.isNotEmpty) {
    sb.writeln('cookies = {');
    cookies.forEach(
        (name, value) => sb.writeln('    ${_sq(name)}: ${_sq(value)},'));
    sb.writeln('}');
    sb.writeln();
  }

  if (headers.isNotEmpty) {
    sb.writeln('headers = {');
    for (final header in headers) {
      sb.writeln('    ${_sq(header.name)}: ${_sq(header.value)},');
    }
    sb.writeln('}');
    sb.writeln();
  }

  String? bodyArg;
  if (ctx.json != null) {
    sb.writeln('payload = ${_formatLiteral(ctx.json, _pythonSyntax)}');
    sb.writeln();
    bodyArg = 'json=payload';
  } else if (ctx.form != null) {
    sb.writeln('payload = ${_formatLiteral(ctx.form, _pythonSyntax)}');
    sb.writeln();
    bodyArg = 'data=payload';
  } else if (ctx.body != null) {
    sb.writeln('payload = ${_sq(ctx.body!)}');
    sb.writeln();
    bodyArg = 'data=payload';
  }

  final args = <String>['url'];
  if (headers.isNotEmpty) args.add('headers=headers');
  if (cookies.isNotEmpty) args.add('cookies=cookies');
  if (bodyArg != null) args.add(bodyArg);
  args.add('timeout=30');

  if (_isStandardMethod(ctx.method)) {
    sb.writeln(
        'response = requests.${ctx.method.toLowerCase()}(${args.join(', ')})');
  } else {
    sb.writeln(
        "response = requests.request('${ctx.method}', ${args.join(', ')})");
  }
  sb.writeln();
  sb.writeln('print(response.status_code)');
  sb.writeln('print(response.text)');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 4. Python · http.client
// ---------------------------------------------------------------------------

String _pythonHttpClient(_Ctx ctx) {
  final sb = StringBuffer();
  final uri = ctx.uri;
  final https = uri.scheme != 'http';
  final host = uri.host.isEmpty ? 'example.com' : uri.host;
  final connection = https ? 'HTTPSConnection' : 'HTTPConnection';

  sb.writeln('import http.client');
  if (ctx.json != null) sb.writeln('import json');
  if (ctx.form != null) sb.writeln('import urllib.parse');
  sb.writeln();
  sb.writeln(
      'conn = http.client.$connection(${_sq(host)}, ${_portOf(uri)}, timeout=30)');
  sb.writeln();

  if (ctx.headers.isNotEmpty) {
    sb.writeln('headers = {');
    for (final header in ctx.headers) {
      sb.writeln('    ${_sq(header.name)}: ${_sq(header.value)},');
    }
    sb.writeln('}');
    sb.writeln();
  }

  if (ctx.json != null) {
    sb.writeln(
        'payload = json.dumps(${_formatLiteral(ctx.json, _pythonSyntax)})');
    sb.writeln();
  } else if (ctx.form != null) {
    sb.writeln(
        'payload = urllib.parse.urlencode(${_formatLiteral(ctx.form, _pythonSyntax)})');
    sb.writeln();
  } else if (ctx.body != null) {
    sb.writeln('payload = ${_sq(ctx.body!)}');
    sb.writeln();
  }

  final args = <String>[_sq(ctx.method), _sq(_pathAndQuery(uri))];
  if (ctx.body != null) args.add('body=payload');
  if (ctx.headers.isNotEmpty) args.add('headers=headers');
  sb.writeln('conn.request(${args.join(', ')})');
  sb.writeln('response = conn.getresponse()');
  sb.writeln();
  sb.writeln('print(response.status)');
  sb.writeln("print(response.read().decode('utf-8'))");
  sb.writeln();
  sb.writeln('conn.close()');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 5. Python · httpx
// ---------------------------------------------------------------------------

String _pythonHttpx(_Ctx ctx) {
  final sb = StringBuffer();
  final structured = ctx.json != null || ctx.form != null;
  final headers = structured
      ? ctx.headers
          .where((h) => h.name.toLowerCase() != 'content-type')
          .toList()
      : ctx.headers;

  sb.writeln('import httpx');
  sb.writeln();
  sb.writeln('url = ${_sq(ctx.url)}');
  sb.writeln();

  if (headers.isNotEmpty) {
    sb.writeln('headers = {');
    for (final header in headers) {
      sb.writeln('    ${_sq(header.name)}: ${_sq(header.value)},');
    }
    sb.writeln('}');
    sb.writeln();
  }

  String? bodyArg;
  if (ctx.json != null) {
    sb.writeln('payload = ${_formatLiteral(ctx.json, _pythonSyntax)}');
    sb.writeln();
    bodyArg = 'json=payload';
  } else if (ctx.form != null) {
    sb.writeln('payload = ${_formatLiteral(ctx.form, _pythonSyntax)}');
    sb.writeln();
    bodyArg = 'data=payload';
  } else if (ctx.body != null) {
    sb.writeln('payload = ${_sq(ctx.body!)}');
    sb.writeln();
    bodyArg = 'content=payload';
  }

  final args = <String>['url'];
  if (headers.isNotEmpty) args.add('headers=headers');
  if (bodyArg != null) args.add(bodyArg);

  sb.writeln('with httpx.Client(timeout=30.0) as client:');
  if (_isStandardMethod(ctx.method)) {
    sb.writeln(
        '    response = client.${ctx.method.toLowerCase()}(${args.join(', ')})');
  } else {
    sb.writeln(
        "    response = client.request('${ctx.method}', ${args.join(', ')})");
  }
  sb.writeln('    print(response.status_code)');
  sb.writeln('    print(response.text)');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 6. Python · aiohttp
// ---------------------------------------------------------------------------

String _pythonAiohttp(_Ctx ctx) {
  final sb = StringBuffer();
  final structured = ctx.json != null || ctx.form != null;
  final headers = structured
      ? ctx.headers
          .where((h) => h.name.toLowerCase() != 'content-type')
          .toList()
      : ctx.headers;

  sb.writeln('import asyncio');
  sb.writeln();
  sb.writeln('import aiohttp');
  sb.writeln();
  sb.writeln();
  sb.writeln('async def main():');
  sb.writeln('    url = ${_sq(ctx.url)}');
  sb.writeln();

  if (headers.isNotEmpty) {
    sb.writeln('    headers = {');
    for (final header in headers) {
      sb.writeln('        ${_sq(header.name)}: ${_sq(header.value)},');
    }
    sb.writeln('    }');
    sb.writeln();
  }

  String? bodyArg;
  if (ctx.json != null) {
    sb.writeln(
        '    payload = ${_indentRest(_formatLiteral(ctx.json, _pythonSyntax), '    ')}');
    sb.writeln();
    bodyArg = 'json=payload';
  } else if (ctx.form != null) {
    sb.writeln(
        '    payload = ${_indentRest(_formatLiteral(ctx.form, _pythonSyntax), '    ')}');
    sb.writeln();
    bodyArg = 'data=payload';
  } else if (ctx.body != null) {
    sb.writeln('    payload = ${_sq(ctx.body!)}');
    sb.writeln();
    bodyArg = 'data=payload';
  }

  final args = <String>['url'];
  if (headers.isNotEmpty) args.add('headers=headers');
  if (bodyArg != null) args.add(bodyArg);

  sb.writeln('    timeout = aiohttp.ClientTimeout(total=30)');
  sb.writeln(
      '    async with aiohttp.ClientSession(timeout=timeout) as session:');
  final call = _isStandardMethod(ctx.method)
      ? 'session.${ctx.method.toLowerCase()}(${args.join(', ')})'
      : "session.request('${ctx.method}', ${args.join(', ')})";
  sb.writeln('        async with $call as response:');
  sb.writeln('            print(response.status)');
  sb.writeln('            print(await response.text())');
  sb.writeln();
  sb.writeln();
  sb.writeln('asyncio.run(main())');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 7. Node · fetch
// ---------------------------------------------------------------------------

String _nodeFetch(_Ctx ctx) {
  final sb = StringBuffer();
  final structured = ctx.json != null || ctx.form != null;
  final headers = structured
      ? ctx.headers
          .where((h) => h.name.toLowerCase() != 'content-type')
          .toList()
      : ctx.headers;

  sb.writeln("import fetch from 'node-fetch';");
  sb.writeln();
  sb.writeln('const url = ${_q(ctx.url)};');
  sb.writeln();

  if (headers.isNotEmpty) {
    sb.writeln('const headers = {');
    for (final header in headers) {
      sb.writeln('  ${_q(header.name)}: ${_q(header.value)},');
    }
    sb.writeln('};');
    sb.writeln();
  }

  String? bodyLine;
  if (ctx.json != null) {
    sb.writeln('const payload = ${_prettyJson(ctx.json)};');
    sb.writeln();
    bodyLine = 'body: JSON.stringify(payload),';
  } else if (ctx.form != null) {
    sb.writeln('const body = new URLSearchParams({');
    ctx.form!
        .forEach((name, value) => sb.writeln('  ${_q(name)}: ${_q(value)},'));
    sb.writeln('});');
    sb.writeln();
    bodyLine = 'body,';
  } else if (ctx.body != null) {
    sb.writeln('const body = ${_q(ctx.body!)};');
    sb.writeln();
    bodyLine = 'body,';
  }

  sb.writeln('const response = await fetch(url, {');
  sb.writeln('  method: ${_q(ctx.method)},');
  if (headers.isNotEmpty) sb.writeln('  headers,');
  if (bodyLine != null) sb.writeln('  $bodyLine');
  sb.writeln('  signal: AbortSignal.timeout(30000),');
  sb.writeln('});');
  sb.writeln();
  sb.writeln('console.log(response.status);');
  sb.writeln('console.log(await response.text());');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 8. Node · axios
// ---------------------------------------------------------------------------

String _nodeAxios(_Ctx ctx) {
  final sb = StringBuffer();
  final structured = ctx.json != null || ctx.form != null;
  final headers = structured
      ? ctx.headers
          .where((h) => h.name.toLowerCase() != 'content-type')
          .toList()
      : ctx.headers;

  sb.writeln("import axios from 'axios';");
  sb.writeln();
  sb.writeln('const url = ${_q(ctx.url)};');
  sb.writeln();

  if (headers.isNotEmpty) {
    sb.writeln('const headers = {');
    for (final header in headers) {
      sb.writeln('  ${_q(header.name)}: ${_q(header.value)},');
    }
    sb.writeln('};');
    sb.writeln();
  }

  String? dataLine;
  if (ctx.json != null) {
    sb.writeln('const payload = ${_prettyJson(ctx.json)};');
    sb.writeln();
    dataLine = 'data: payload,';
  } else if (ctx.form != null) {
    sb.writeln('const payload = new URLSearchParams({');
    ctx.form!
        .forEach((name, value) => sb.writeln('  ${_q(name)}: ${_q(value)},'));
    sb.writeln('});');
    sb.writeln();
    dataLine = 'data: payload,';
  } else if (ctx.body != null) {
    sb.writeln('const payload = ${_q(ctx.body!)};');
    sb.writeln();
    dataLine = 'data: payload,';
  }

  sb.writeln('const response = await axios.request({');
  sb.writeln('  method: ${_q(ctx.method.toLowerCase())},');
  sb.writeln('  url,');
  if (headers.isNotEmpty) sb.writeln('  headers,');
  if (dataLine != null) sb.writeln('  $dataLine');
  sb.writeln('  timeout: 30000,');
  sb.writeln('});');
  sb.writeln();
  sb.writeln('console.log(response.status);');
  sb.writeln('console.log(response.data);');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 9. Node · http / https
// ---------------------------------------------------------------------------

String _nodeNative(_Ctx ctx) {
  final sb = StringBuffer();
  final uri = ctx.uri;
  final secure = uri.scheme != 'http';
  final module = secure ? 'https' : 'http';
  final hasBody = ctx.body != null && !ctx.binary;

  sb.writeln("const $module = require('$module');");
  sb.writeln();
  sb.writeln('const url = new URL(${_q(ctx.url)});');

  if (hasBody) {
    sb.writeln();
    if (ctx.json != null) {
      sb.writeln('const payload = ${_prettyJson(ctx.json)};');
      sb.writeln('const body = JSON.stringify(payload);');
    } else {
      sb.writeln('const body = ${_q(ctx.body!)};');
    }
  }
  sb.writeln();

  sb.writeln('const options = {');
  sb.writeln('  method: ${_q(ctx.method)},');
  sb.writeln('  hostname: url.hostname,');
  sb.writeln('  port: url.port || ${secure ? 443 : 80},');
  sb.writeln('  path: url.pathname + url.search,');
  if (ctx.headers.isNotEmpty || hasBody) {
    sb.writeln('  headers: {');
    for (final header in ctx.headers) {
      sb.writeln('    ${_q(header.name)}: ${_q(header.value)},');
    }
    if (hasBody) {
      sb.writeln('    ${_q('Content-Length')}: Buffer.byteLength(body),');
    }
    sb.writeln('  },');
  }
  sb.writeln('  timeout: 30000,');
  sb.writeln('};');
  sb.writeln();
  sb.writeln('const req = $module.request(options, (res) => {');
  sb.writeln('  let data = \'\';');
  sb.writeln('  res.setEncoding(\'utf8\');');
  sb.writeln('  res.on(\'data\', (chunk) => {');
  sb.writeln('    data += chunk;');
  sb.writeln('  });');
  sb.writeln('  res.on(\'end\', () => {');
  sb.writeln('    console.log(res.statusCode);');
  sb.writeln('    console.log(data);');
  sb.writeln('  });');
  sb.writeln('});');
  sb.writeln();
  sb.writeln(
      "req.on('timeout', () => req.destroy(new Error('Request timed out')));");
  sb.writeln("req.on('error', (err) => console.error(err));");
  if (hasBody) {
    sb.writeln('req.write(body);');
  }
  sb.writeln('req.end();');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 10. Rust · reqwest（async + tokio）
// ---------------------------------------------------------------------------

String _rustReqwest(_Ctx ctx) {
  final sb = StringBuffer();
  final structured = ctx.json != null || ctx.form != null;
  final headers = structured
      ? ctx.headers
          .where((h) => h.name.toLowerCase() != 'content-type')
          .toList()
      : ctx.headers;

  sb.writeln('use reqwest::header::{HeaderMap, HeaderValue};');
  if (ctx.json != null) sb.writeln('use serde_json::json;');
  sb.writeln('use std::time::Duration;');
  sb.writeln();
  sb.writeln('#[tokio::main]');
  sb.writeln('async fn main() -> Result<(), Box<dyn std::error::Error>> {');
  sb.writeln('    let mut headers = HeaderMap::new();');
  for (final header in headers) {
    sb.writeln('    headers.insert('
        '${_rustStr(header.name.toLowerCase())}, '
        'HeaderValue::from_static(${_rustStr(header.value)}));');
  }
  sb.writeln();

  if (ctx.json != null) {
    sb.writeln(
        '    let payload = json!(${_indentRest(_prettyJson(ctx.json), '    ')});');
    sb.writeln();
  } else if (ctx.form != null) {
    sb.writeln(
        '    let payload = json!(${_indentRest(_prettyJson(ctx.form), '    ')});');
    sb.writeln();
  } else if (ctx.body != null) {
    sb.writeln('    let payload = ${_rustStr(ctx.body!)};');
    sb.writeln();
  }

  sb.writeln('    let client = reqwest::Client::builder()');
  sb.writeln('        .timeout(Duration::from_secs(30))');
  sb.writeln('        .build()?;');
  sb.writeln();
  sb.writeln('    let response = client');
  if (_isStandardMethod(ctx.method)) {
    sb.writeln('        .${ctx.method.toLowerCase()}(${_rustStr(ctx.url)})');
  } else {
    sb.writeln('        .request(');
    sb.writeln('            reqwest::Method::from_bytes(b"${ctx.method}")?,');
    sb.writeln('            ${_rustStr(ctx.url)},');
    sb.writeln('        )');
  }
  sb.writeln('        .headers(headers)');
  if (ctx.json != null) {
    sb.writeln('        .json(&payload)');
  } else if (ctx.form != null) {
    sb.writeln('        .form(&payload)');
  } else if (ctx.body != null) {
    sb.writeln('        .body(payload)');
  }
  sb.writeln('        .send()');
  sb.writeln('        .await?;');
  sb.writeln();
  sb.writeln('    println!("{}", response.status());');
  sb.writeln('    println!("{}", response.text().await?);');
  sb.writeln();
  sb.writeln('    Ok(())');
  sb.writeln('}');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 11. Rust · ureq（阻塞）
// ---------------------------------------------------------------------------

String _rustUreq(_Ctx ctx) {
  final sb = StringBuffer();
  final hasBody = ctx.body != null && !ctx.binary;

  sb.writeln('use std::time::Duration;');
  sb.writeln();
  sb.writeln('fn main() -> Result<(), Box<dyn std::error::Error>> {');
  sb.writeln('    let agent = ureq::AgentBuilder::new()');
  sb.writeln('        .timeout(Duration::from_secs(30))');
  sb.writeln('        .build();');
  sb.writeln();
  // 链式调用：分号挂在最后一行末尾。
  final chain = <String>['    let request = agent'];
  if (_isStandardMethod(ctx.method)) {
    chain.add('        .${ctx.method.toLowerCase()}(${_rustStr(ctx.url)})');
  } else {
    chain
        .add('        .request(${_rustStr(ctx.method)}, ${_rustStr(ctx.url)})');
  }
  for (final header in ctx.headers) {
    chain.add('        .set('
        '${_rustStr(header.name.toLowerCase())}, '
        '${_rustStr(header.value)})');
  }
  chain[chain.length - 1] = '${chain.last};';
  for (final line in chain) {
    sb.writeln(line);
  }
  sb.writeln();

  if (hasBody) {
    sb.writeln(
        '    let result = request.send_string(${_rustRaw(ctx.jsonText)});');
  } else {
    sb.writeln('    let result = request.call();');
  }
  sb.writeln();
  sb.writeln('    match result {');
  sb.writeln('        Ok(response) => {');
  sb.writeln('            println!("{}", response.status());');
  sb.writeln('            println!("{}", response.into_string()?);');
  sb.writeln('        }');
  sb.writeln('        Err(ureq::Error::Status(code, response)) => {');
  sb.writeln('            println!("{}", code);');
  sb.writeln('            println!("{}", response.into_string()?);');
  sb.writeln('        }');
  sb.writeln('        Err(error) => return Err(error.into()),');
  sb.writeln('    }');
  sb.writeln();
  sb.writeln('    Ok(())');
  sb.writeln('}');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 12. Go · net/http
// ---------------------------------------------------------------------------

String _goNetHttp(_Ctx ctx) {
  final sb = StringBuffer();
  final hasBody = ctx.body != null && !ctx.binary;
  final hasJson = ctx.json != null;
  final hasForm = ctx.form != null;

  sb.writeln('package main');
  sb.writeln();
  sb.writeln('import (');
  if (hasBody) sb.writeln('    "bytes"');
  if (hasJson) sb.writeln('    "encoding/json"');
  sb.writeln('    "fmt"');
  sb.writeln('    "io"');
  sb.writeln('    "net/http"');
  if (hasForm) sb.writeln('    "net/url"');
  sb.writeln('    "time"');
  sb.writeln(')');
  sb.writeln();
  sb.writeln('func main() {');

  if (hasJson) {
    sb.writeln(
        '    payload := ${_indentRest(_formatLiteral(ctx.json, _goSyntax), '    ')}');
    sb.writeln();
    sb.writeln('    body, err := json.Marshal(payload)');
    sb.writeln('    if err != nil {');
    sb.writeln('        panic(err)');
    sb.writeln('    }');
    sb.writeln();
  } else if (hasForm) {
    sb.writeln('    payload := url.Values{');
    ctx.form!.forEach((name, value) {
      sb.writeln('        ${_q(name)}: {${_q(value)}},');
    });
    sb.writeln('    }');
    sb.writeln();
    sb.writeln('    body := []byte(payload.Encode())');
    sb.writeln();
  } else if (hasBody) {
    if (ctx.body!.contains('`')) {
      sb.writeln('    body := []byte(${_q(ctx.body!)})');
    } else {
      sb.writeln('    body := []byte(`${ctx.body}`)');
    }
    sb.writeln();
  }

  final bodyExpr = hasBody ? 'bytes.NewReader(body)' : 'nil';
  sb.writeln(
      '    req, err := http.NewRequest(${_q(ctx.method)}, ${_q(ctx.url)}, $bodyExpr)');
  sb.writeln('    if err != nil {');
  sb.writeln('        panic(err)');
  sb.writeln('    }');
  sb.writeln();

  if (ctx.headers.isNotEmpty) {
    for (final header in ctx.headers) {
      sb.writeln('    req.Header.Set(${_q(header.name)}, ${_q(header.value)})');
    }
    sb.writeln();
  }

  sb.writeln('    client := &http.Client{Timeout: 30 * time.Second}');
  sb.writeln('    resp, err := client.Do(req)');
  sb.writeln('    if err != nil {');
  sb.writeln('        panic(err)');
  sb.writeln('    }');
  sb.writeln('    defer resp.Body.Close()');
  sb.writeln();
  sb.writeln('    respBody, err := io.ReadAll(resp.Body)');
  sb.writeln('    if err != nil {');
  sb.writeln('        panic(err)');
  sb.writeln('    }');
  sb.writeln();
  sb.writeln('    fmt.Println(resp.Status)');
  sb.writeln('    fmt.Println(string(respBody))');
  sb.writeln('}');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 13. Java · OkHttp
// ---------------------------------------------------------------------------

String _javaOkHttp(_Ctx ctx) {
  final sb = StringBuffer();
  final contentType = _headerValue(ctx, 'content-type');
  final headers = ctx.headersWithoutContentType;

  sb.writeln('import java.io.IOException;');
  sb.writeln('import java.util.concurrent.TimeUnit;');
  sb.writeln('import okhttp3.MediaType;');
  sb.writeln('import okhttp3.OkHttpClient;');
  sb.writeln('import okhttp3.Request;');
  sb.writeln('import okhttp3.RequestBody;');
  sb.writeln('import okhttp3.Response;');
  sb.writeln();
  sb.writeln('public class Main {');
  sb.writeln();
  sb.writeln('    public static void main(String[] args) throws IOException {');
  sb.writeln('        OkHttpClient client = new OkHttpClient.Builder()');
  sb.writeln('                .connectTimeout(30, TimeUnit.SECONDS)');
  sb.writeln('                .readTimeout(30, TimeUnit.SECONDS)');
  sb.writeln('                .build();');
  sb.writeln();

  final mediaType =
      contentType ?? (ctx.body != null ? 'text/plain; charset=utf-8' : null);
  String bodyExpr;
  if (ctx.body != null && !ctx.binary) {
    if (mediaType != null) {
      sb.writeln(
          '        MediaType mediaType = MediaType.parse(${_q(mediaType)});');
    }
    sb.writeln(
        '        String payload = ${_javaBlock(ctx.jsonText, '        ')};');
    sb.writeln();
    bodyExpr = mediaType != null
        ? 'RequestBody.create(payload, mediaType)'
        : 'RequestBody.create(payload, null)';
  } else {
    bodyExpr = 'null';
  }

  sb.writeln('        Request request = new Request.Builder()');
  sb.writeln('                .url(${_q(ctx.url)})');
  for (final header in headers) {
    sb.writeln(
        '                .header(${_q(header.name)}, ${_q(header.value)})');
  }
  sb.writeln('                .method(${_q(ctx.method)}, $bodyExpr)');
  sb.writeln('                .build();');
  sb.writeln();
  sb.writeln(
      '        try (Response response = client.newCall(request).execute()) {');
  sb.writeln('            System.out.println(response.code());');
  sb.writeln(
      '            System.out.println(response.body() != null ? response.body().string() : "");');
  sb.writeln('        }');
  sb.writeln('    }');
  sb.writeln('}');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 14. Java · HttpClient（java.net.http）
// ---------------------------------------------------------------------------

String _javaHttpClient(_Ctx ctx) {
  final sb = StringBuffer();
  final hasBody = ctx.body != null && !ctx.binary;

  sb.writeln('import java.net.URI;');
  sb.writeln('import java.net.http.HttpClient;');
  sb.writeln('import java.net.http.HttpRequest;');
  sb.writeln('import java.net.http.HttpResponse;');
  sb.writeln('import java.time.Duration;');
  sb.writeln();
  sb.writeln('public class Main {');
  sb.writeln();
  sb.writeln('    public static void main(String[] args) throws Exception {');
  sb.writeln('        HttpClient client = HttpClient.newBuilder()');
  sb.writeln('                .connectTimeout(Duration.ofSeconds(30))');
  sb.writeln('                .build();');
  sb.writeln();

  if (hasBody) {
    sb.writeln(
        '        String payload = ${_javaBlock(ctx.jsonText, '        ')};');
    sb.writeln();
  }

  sb.writeln('        HttpRequest request = HttpRequest.newBuilder()');
  sb.writeln('                .uri(URI.create(${_q(ctx.url)}))');
  sb.writeln('                .timeout(Duration.ofSeconds(30))');
  for (final header in ctx.headers) {
    sb.writeln(
        '                .header(${_q(header.name)}, ${_q(header.value)})');
  }
  final publisher = hasBody
      ? 'HttpRequest.BodyPublishers.ofString(payload)'
      : 'HttpRequest.BodyPublishers.noBody()';
  sb.writeln('                .method(${_q(ctx.method)}, $publisher)');
  sb.writeln('                .build();');
  sb.writeln();
  sb.writeln('        HttpResponse<String> response =');
  sb.writeln(
      '                client.send(request, HttpResponse.BodyHandlers.ofString());');
  sb.writeln();
  sb.writeln('        System.out.println(response.statusCode());');
  sb.writeln('        System.out.println(response.body());');
  sb.writeln('    }');
  sb.writeln('}');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 15. Kotlin · OkHttp
// ---------------------------------------------------------------------------

String _kotlinOkHttp(_Ctx ctx) {
  final sb = StringBuffer();
  final contentType = _headerValue(ctx, 'content-type');
  final headers = ctx.headersWithoutContentType;
  final hasBody = ctx.body != null && !ctx.binary;
  final mediaType = contentType ?? 'text/plain; charset=utf-8';

  sb.writeln('import java.util.concurrent.TimeUnit');
  sb.writeln('import okhttp3.MediaType.Companion.toMediaType');
  sb.writeln('import okhttp3.OkHttpClient');
  sb.writeln('import okhttp3.Request');
  sb.writeln('import okhttp3.RequestBody.Companion.toRequestBody');
  sb.writeln();
  sb.writeln('fun main() {');
  sb.writeln('    val client = OkHttpClient.Builder()');
  sb.writeln('        .connectTimeout(30, TimeUnit.SECONDS)');
  sb.writeln('        .readTimeout(30, TimeUnit.SECONDS)');
  sb.writeln('        .build()');
  sb.writeln();

  if (hasBody) {
    sb.writeln('    val payload = ${_kotlinBlock(ctx.jsonText, '    ')}');
    sb.writeln();
    sb.writeln(
        '    val body = payload.toRequestBody(${_q(mediaType)}.toMediaType())');
    sb.writeln();
  }

  sb.writeln('    val request = Request.Builder()');
  sb.writeln('        .url(${_q(ctx.url)})');
  for (final header in headers) {
    sb.writeln('        .header(${_q(header.name)}, ${_q(header.value)})');
  }
  sb.writeln(
      '        .method(${_q(ctx.method)}, ${hasBody ? 'body' : 'null'})');
  sb.writeln('        .build()');
  sb.writeln();
  sb.writeln('    client.newCall(request).execute().use { response ->');
  sb.writeln('        println(response.code)');
  sb.writeln('        println(response.body?.string())');
  sb.writeln('    }');
  sb.writeln('}');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 16. C# · HttpClient
// ---------------------------------------------------------------------------

String _csharpHttpClient(_Ctx ctx) {
  final sb = StringBuffer();
  final hasBody = ctx.body != null && !ctx.binary;
  final contentType = _headerValue(ctx, 'content-type') ?? 'text/plain';

  sb.writeln('using System;');
  sb.writeln('using System.Net.Http;');
  sb.writeln('using System.Text;');
  sb.writeln('using System.Threading.Tasks;');
  sb.writeln();
  sb.writeln('class Program');
  sb.writeln('{');
  sb.writeln('    static async Task Main()');
  sb.writeln('    {');
  sb.writeln(
      '        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };');
  sb.writeln();
  sb.writeln('        using var request = new HttpRequestMessage('
      '${_csharpMethod(ctx.method)}, ${_q(ctx.url)});');
  for (final header in ctx.headersWithoutContentType) {
    sb.writeln('        request.Headers.TryAddWithoutValidation('
        '${_q(header.name)}, ${_q(header.value)});');
  }
  if (hasBody) {
    sb.writeln();
    sb.writeln(
        '        var payload = ${_csharpBlock(ctx.jsonText, '        ')};');
    sb.writeln('        request.Content = new StringContent('
        'payload, Encoding.UTF8, ${_q(_mediaTypeOf(contentType))});');
  }
  sb.writeln();
  sb.writeln('        using var response = await client.SendAsync(request);');
  sb.writeln('        Console.WriteLine((int)response.StatusCode);');
  sb.writeln(
      '        Console.WriteLine(await response.Content.ReadAsStringAsync());');
  sb.writeln('    }');
  sb.writeln('}');

  return sb.toString();
}

/// C# 的 HttpMethod 表达式：常见动词用静态属性，其余用构造器。
String _csharpMethod(String method) {
  const known = {
    'GET': 'HttpMethod.Get',
    'POST': 'HttpMethod.Post',
    'PUT': 'HttpMethod.Put',
    'PATCH': 'HttpMethod.Patch',
    'DELETE': 'HttpMethod.Delete',
    'HEAD': 'HttpMethod.Head',
    'OPTIONS': 'HttpMethod.Options',
    'TRACE': 'HttpMethod.Trace',
  };
  return known[method] ?? 'new HttpMethod(${_q(method)})';
}

/// `application/json; charset=utf-8` → `application/json`。
String _mediaTypeOf(String contentType) {
  final index = contentType.indexOf(';');
  final value = index < 0 ? contentType : contentType.substring(0, index);
  return value.trim();
}

// ---------------------------------------------------------------------------
// 17. PHP · cURL
// ---------------------------------------------------------------------------

String _phpCurl(_Ctx ctx) {
  final sb = StringBuffer();

  sb.writeln('<?php');
  sb.writeln();
  sb.writeln('\$url = ${_phpStr(ctx.url)};');
  sb.writeln();

  if (ctx.headers.isNotEmpty) {
    sb.writeln('\$headers = [');
    for (final header in ctx.headers) {
      sb.writeln('    ${_phpStr('${header.name}: ${header.value}')},');
    }
    sb.writeln('];');
    sb.writeln();
  }

  String? payloadExpr;
  if (ctx.json != null) {
    sb.writeln('\$payload = ${_formatLiteral(ctx.json, _phpSyntax)};');
    sb.writeln();
    payloadExpr = 'json_encode(\$payload)';
  } else if (ctx.form != null) {
    sb.writeln('\$payload = ${_formatLiteral(ctx.form, _phpSyntax)};');
    sb.writeln();
    payloadExpr = 'http_build_query(\$payload)';
  } else if (ctx.body != null) {
    sb.writeln('\$payload = ${_phpStr(ctx.body!)};');
    sb.writeln();
    payloadExpr = '\$payload';
  }

  sb.writeln('\$ch = curl_init(\$url);');
  sb.writeln('curl_setopt_array(\$ch, [');
  sb.writeln('    CURLOPT_CUSTOMREQUEST => ${_phpStr(ctx.method)},');
  sb.writeln('    CURLOPT_RETURNTRANSFER => true,');
  sb.writeln('    CURLOPT_FOLLOWLOCATION => true,');
  sb.writeln('    CURLOPT_TIMEOUT => 30,');
  if (ctx.headers.isNotEmpty) {
    sb.writeln('    CURLOPT_HTTPHEADER => \$headers,');
  }
  if (payloadExpr != null) {
    sb.writeln('    CURLOPT_POSTFIELDS => $payloadExpr,');
  }
  sb.writeln(']);');
  sb.writeln();
  sb.writeln('\$response = curl_exec(\$ch);');
  sb.writeln('if (\$response === false) {');
  sb.writeln('    fwrite(STDERR, curl_error(\$ch) . PHP_EOL);');
  sb.writeln('    exit(1);');
  sb.writeln('}');
  sb.writeln();
  sb.writeln('\$status = curl_getinfo(\$ch, CURLINFO_RESPONSE_CODE);');
  sb.writeln('curl_close(\$ch);');
  sb.writeln();
  sb.writeln('echo \$status . PHP_EOL;');
  sb.writeln('echo \$response . PHP_EOL;');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 18. Ruby · Net::HTTP
// ---------------------------------------------------------------------------

String _rubyNetHttp(_Ctx ctx) {
  final sb = StringBuffer();

  sb.writeln("require 'net/http'");
  sb.writeln("require 'uri'");
  if (ctx.json != null) sb.writeln("require 'json'");
  sb.writeln();
  sb.writeln('uri = URI.parse(${_rbStr(ctx.url)})');
  sb.writeln();

  String? bodyExpr;
  if (ctx.json != null) {
    sb.writeln('payload = ${_formatLiteral(ctx.json, _rubySyntax)}');
    sb.writeln();
    bodyExpr = 'payload.to_json';
  } else if (ctx.form != null) {
    sb.writeln('payload = ${_formatLiteral(ctx.form, _rubySyntax)}');
    sb.writeln();
    bodyExpr = 'URI.encode_www_form(payload)';
  } else if (ctx.body != null) {
    sb.writeln('payload = ${_rbStr(ctx.body!)}');
    sb.writeln();
    bodyExpr = 'payload';
  }

  sb.writeln('http = Net::HTTP.new(uri.host, uri.port)');
  sb.writeln("http.use_ssl = uri.scheme == 'https'");
  sb.writeln('http.open_timeout = 30');
  sb.writeln('http.read_timeout = 30');
  sb.writeln();

  final requestClass = _rubyRequestClass(ctx.method);
  if (requestClass != null) {
    sb.writeln('request = Net::HTTP::$requestClass.new(uri.request_uri)');
  } else {
    sb.writeln('request = Net::HTTPGenericRequest.new('
        '${_rbStr(ctx.method)}, ${ctx.body != null}, true, uri.request_uri)');
  }
  for (final header in ctx.headers) {
    sb.writeln('request[${_rbStr(header.name)}] = ${_rbStr(header.value)}');
  }
  if (bodyExpr != null) {
    sb.writeln('request.body = $bodyExpr');
  }
  sb.writeln();
  sb.writeln('response = http.request(request)');
  sb.writeln();
  sb.writeln('puts response.code');
  sb.writeln('puts response.body');

  return sb.toString();
}

String? _rubyRequestClass(String method) {
  const known = {
    'GET': 'Get',
    'POST': 'Post',
    'PUT': 'Put',
    'PATCH': 'Patch',
    'DELETE': 'Delete',
    'HEAD': 'Head',
    'OPTIONS': 'Options',
  };
  return known[method];
}

// ---------------------------------------------------------------------------
// 19. Swift · URLSession
// ---------------------------------------------------------------------------

String _swiftUrlSession(_Ctx ctx) {
  final sb = StringBuffer();
  final hasBody = ctx.body != null && !ctx.binary;
  final json = ctx.json;

  sb.writeln('import Foundation');
  sb.writeln();
  sb.writeln('@main');
  sb.writeln('struct App {');
  sb.writeln('    static func main() async throws {');
  sb.writeln('        let url = URL(string: ${_swiftStr(ctx.url)})!');
  sb.writeln();
  sb.writeln('        var request = URLRequest(url: url)');
  sb.writeln('        request.httpMethod = ${_swiftStr(ctx.method)}');
  sb.writeln('        request.timeoutInterval = 30');
  for (final header in ctx.headers) {
    sb.writeln('        request.setValue('
        '${_swiftStr(header.value)}, forHTTPHeaderField: ${_swiftStr(header.name)})');
  }
  sb.writeln();

  if (hasBody) {
    if (json is Map) {
      sb.writeln('        let payload: [String: Any] = '
          '${_indentRest(_formatLiteral(json, _swiftSyntax), '        ')}');
      sb.writeln(
          '        request.httpBody = try JSONSerialization.data(withJSONObject: payload)');
    } else if (json is List) {
      sb.writeln(
          '        let payload: [Any] = ${_indentRest(_formatLiteral(json, _swiftSyntax), '        ')}');
      sb.writeln(
          '        request.httpBody = try JSONSerialization.data(withJSONObject: payload)');
    } else {
      sb.writeln('        let payload = ${_swiftBlock(ctx.body!, '        ')}');
      sb.writeln('        request.httpBody = payload.data(using: .utf8)');
    }
    sb.writeln();
  }

  sb.writeln(
      '        let (data, response) = try await URLSession.shared.data(for: request)');
  sb.writeln();
  sb.writeln('        if let httpResponse = response as? HTTPURLResponse {');
  sb.writeln('            print(httpResponse.statusCode)');
  sb.writeln('        }');
  sb.writeln('        print(String(data: data, encoding: .utf8) ?? "")');
  sb.writeln('    }');
  sb.writeln('}');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 20. Dart · http
// ---------------------------------------------------------------------------

String _dartHttp(_Ctx ctx) {
  final sb = StringBuffer();
  final structured = ctx.json != null || ctx.form != null;
  final headers = structured
      ? ctx.headers
          .where((h) => h.name.toLowerCase() != 'content-type')
          .toList()
      : ctx.headers;

  if (ctx.json != null) {
    // jsonEncode 需要 dart:convert
    sb.writeln("import 'dart:convert';");
    sb.writeln();
  }
  sb.writeln("import 'package:http/http.dart' as http;");
  sb.writeln();
  sb.writeln('Future<void> main() async {');
  sb.writeln('  final url = Uri.parse(${_dartStr(ctx.url)});');
  sb.writeln();

  if (headers.isNotEmpty) {
    sb.writeln('  final headers = <String, String>{');
    for (final header in headers) {
      sb.writeln('    ${_dartStr(header.name)}: ${_dartStr(header.value)},');
    }
    sb.writeln('  };');
    sb.writeln();
  }

  String? shortcutBody;
  String? requestBody;
  if (ctx.json != null) {
    sb.writeln(
        '  final payload = ${_indentRest(_formatLiteral(ctx.json, _dartSyntax), '  ')};');
    sb.writeln();
    shortcutBody = 'jsonEncode(payload)';
    requestBody = 'jsonEncode(payload)';
  } else if (ctx.form != null) {
    sb.writeln(
        '  final payload = ${_indentRest(_formatLiteral(ctx.form, _dartSyntax), '  ')};');
    sb.writeln();
    shortcutBody = 'payload';
    requestBody = 'Uri(queryParameters: payload).query';
  } else if (ctx.body != null) {
    sb.writeln('  const payload = ${_dartStr(ctx.body!)};');
    sb.writeln();
    shortcutBody = 'payload';
    requestBody = 'payload';
  }

  // http.get / http.head 不接受 body，带 body 时必须走通用 Request。
  final needsRequest = !_isStandardMethod(ctx.method) ||
      ((ctx.method == 'GET' || ctx.method == 'HEAD') && shortcutBody != null);

  if (!needsRequest) {
    final args = <String>['url'];
    if (headers.isNotEmpty) args.add('headers: headers');
    if (shortcutBody != null) args.add('body: $shortcutBody');
    sb.writeln('  final response = await http');
    sb.writeln('      .${ctx.method.toLowerCase()}(${args.join(', ')})');
    sb.writeln('      .timeout(const Duration(seconds: 30));');
  } else {
    sb.writeln('  final request = http.Request(${_dartStr(ctx.method)}, url);');
    if (headers.isNotEmpty) {
      sb.writeln('  request.headers.addAll(headers);');
    }
    if (requestBody != null) {
      sb.writeln('  request.body = $requestBody;');
    }
    sb.writeln();
    sb.writeln(
        '  final streamed = await request.send().timeout(const Duration(seconds: 30));');
    sb.writeln('  final response = await http.Response.fromStream(streamed);');
  }
  sb.writeln();
  sb.writeln('  print(response.statusCode);');
  sb.writeln('  print(response.body);');
  sb.writeln('}');

  return sb.toString();
}

// ---------------------------------------------------------------------------
// 21. PowerShell · Invoke-RestMethod
// ---------------------------------------------------------------------------

String _powershell(_Ctx ctx) {
  final sb = StringBuffer();
  final hasBody = ctx.body != null && !ctx.binary;

  if (ctx.headers.isNotEmpty) {
    sb.writeln('\$headers = @{');
    for (final header in ctx.headers) {
      sb.writeln('    ${_psStr(header.name)} = ${_psStr(header.value)}');
    }
    sb.writeln('}');
    sb.writeln();
  }

  if (hasBody) {
    if (ctx.json != null || ctx.isJson) {
      sb.writeln('\$body = @\'');
      sb.writeln(ctx.jsonText);
      sb.writeln("'@");
    } else {
      sb.writeln('\$body = ${_psStr(ctx.body!)}');
    }
    sb.writeln();
  }

  final methodArg = _isStandardMethod(ctx.method) || ctx.method == 'TRACE'
      ? "-Method '${_titleCase(ctx.method)}'"
      : "-CustomMethod ${_psStr(ctx.method)}";

  final parts = <String>[
    'Invoke-RestMethod',
    '-Uri ${_psStr(ctx.url)}',
    methodArg,
  ];
  if (ctx.headers.isNotEmpty) parts.add('-Headers \$headers');
  if (hasBody) parts.add('-Body \$body');
  parts.add('-TimeoutSec 30');
  parts.add('-StatusCodeVariable statusCode');

  sb.writeln('\$response = ${parts.join(' `\n    ')}');
  sb.writeln();
  sb.writeln('Write-Output \$statusCode');
  sb.writeln('\$response | ConvertTo-Json -Depth 10');

  return sb.toString();
}

String _titleCase(String method) {
  if (method.isEmpty) return method;
  return method[0].toUpperCase() + method.substring(1).toLowerCase();
}

// ---------------------------------------------------------------------------
// 22. Raw HTTP/1.1
// ---------------------------------------------------------------------------

String _rawHttp(_Ctx ctx) {
  final sb = StringBuffer();
  final uri = ctx.uri;
  final hasBody = ctx.body != null && !ctx.binary;

  sb.writeln('${ctx.method} ${_pathAndQuery(uri)} HTTP/1.1');

  final host = uri.host.isEmpty ? 'example.com' : uri.host;
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = _portOf(uri);
  sb.writeln('Host: ${port == defaultPort ? host : '$host:$port'}');

  for (final header in ctx.headers) {
    sb.writeln('${header.name}: ${header.value}');
  }

  if (hasBody) {
    // 输出的是重新格式化后的 body，长度必须按最终文本计算
    sb.writeln('Content-Length: ${utf8.encode(ctx.jsonText).length}');
  }

  sb.writeln();
  if (hasBody) {
    sb.writeln(ctx.jsonText);
  }

  return sb.toString();
}

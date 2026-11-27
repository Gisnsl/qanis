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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:qanis/network/channel/channel_context.dart';
import 'package:qanis/network/channel/host_port.dart';
import 'package:qanis/network/http/h2/h2_codec.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/network/http/http_headers.dart';
import 'package:qanis/network/channel/network.dart';
import 'package:qanis/network/util/byte_buf.dart';
import 'package:qanis/network/util/byte_utils.dart';
import 'package:qanis/network/util/logger.dart';
import 'package:qanis/network/util/system_proxy.dart';
import 'package:proxy_manager/proxy_manager.dart';

import '../channel/channel.dart';
import 'codec.dart';
import 'h2/frame.dart';
import 'h2/setting.dart';

class HttpClients {
  static Future<Channel> startConnect(HostAndPort hostAndPort, {Duration timeout = const Duration(seconds: 3)}) {
    String host = hostAndPort.host;
    //说明支持ipv6
    if (host.startsWith("[") && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }

    return Socket.connect(host, hostAndPort.port, timeout: timeout).then((socket) {
      if (socket.address.type != InternetAddressType.unix) {
        socket.setOption(SocketOption.tcpNoDelay, true);
      }
      return Channel(socket);
    });
  }

  ///代理建立连接
  static Future<Channel> proxyConnect(
      HttpRequest request, HostAndPort hostAndPort, ChannelHandler<HttpResponse> handler, ChannelContext channelContext,
      {ProxyInfo? proxyInfo}) async {
    var client = Client()..initChannel((channel) => channel.dispatcher.channelHandle(HttpClientCodec(), handler));

    if (proxyInfo == null) {
      var proxyTypes = hostAndPort.isSsl() ? ProxyTypes.https : ProxyTypes.http;
      proxyInfo = await SystemProxy.getSystemProxy(proxyTypes);
    }

    HostAndPort connectHost = proxyInfo == null ? hostAndPort : HostAndPort.host(proxyInfo.host, proxyInfo.port!);
    var channel = await client.connect(connectHost, channelContext);

    if (proxyInfo != null) {
      await connectRequest(channelContext, hostAndPort, channel, proxyInfo: proxyInfo);
    }

    if (hostAndPort.isSsl()) {
      await channel.startSecureSocket(channelContext,
          host: hostAndPort.host, supportedProtocols: request.protocolVersion == "HTTP/2" ? ["h2", "http/1.1"] : null);
      if (channelContext.serverChannel?.selectedProtocol == "h2") {
        await Http2ClientHandler(handler).listen(channel, channelContext);
      } else {
        request.protocolVersion = "HTTP/1.1";
        channel.dispatcher.listen(channel, channelContext);
      }
    }

    logger.d(
        "request ${hostAndPort.host}:${hostAndPort.port} ${request.protocolVersion} ${channelContext.serverChannel?.selectedProtocol ?? ''}");

    return channel;
  }

  ///发起代理连接请求
  static Future<Channel> connectRequest(ChannelContext channelContext, HostAndPort hostAndPort, Channel channel,
      {ProxyInfo? proxyInfo}) async {
    ChannelHandler handler = channel.dispatcher.handler;
    //代理 发送connect请求
    var httpResponseHandler = HttpResponseHandler();
    channel.dispatcher.handler = httpResponseHandler;

    HttpRequest proxyRequest = HttpRequest(HttpMethod.connect, '${hostAndPort.host}:${hostAndPort.port}');
    proxyRequest.headers.set(HttpHeaders.HOST, '${hostAndPort.host}:${hostAndPort.port}');

    //proxy Authorization
    if (proxyInfo?.isAuthenticated == true) {
      String auth = base64Encode(utf8.encode("${proxyInfo?.username}:${proxyInfo?.password}"));
      proxyRequest.headers.set(HttpHeaders.PROXY_AUTHORIZATION, 'Basic $auth');
    }

    // 编码 CONNECT 时 HttpClientCodec 会自行标记下一个响应无 body，无需在此设置上下文
    await channel.write(channelContext, proxyRequest);
    var response = await httpResponseHandler.getResponse(const Duration(seconds: 5));

    channel.dispatcher.handler = handler;

    if (!response.status.isSuccessful()) {
      throw Exception("$hostAndPort Proxy failed to establish tunnel "
          "(${response.status.code} ${response..status.reasonPhrase})");
    }

    return channel;
  }

  /// 建立连接
  static Future<Channel> connect(Uri uri, ChannelHandler handler, ChannelContext channelContext) async {
    Client client = Client()
      ..initChannel((channel) => channel.dispatcher.handle(HttpResponseCodec(), HttpRequestCodec(), handler));
    if (uri.scheme == "https" || uri.scheme == "wss") {
      return client.secureConnect(HostAndPort.of(uri.toString()), channelContext);
    }

    return client.connect(HostAndPort.of(uri.toString()), channelContext);
  }

  /// 发送get请求
  static Future<HttpResponse> get(String url, {Duration timeout = const Duration(seconds: 3)}) async {
    HttpRequest msg = HttpRequest(HttpMethod.get, url);
    return request(HostAndPort.of(url), msg, timeout: timeout);
  }

  /// 发送请求
  static Future<HttpResponse> request(HostAndPort hostAndPort, HttpRequest request,
      {Duration timeout = const Duration(seconds: 3)}) async {
    var httpResponseHandler = HttpResponseHandler();

    var client = Client()
      ..initChannel(
          (channel) => channel.dispatcher.handle(HttpResponseCodec(), HttpRequestCodec(), httpResponseHandler));

    ChannelContext channelContext = ChannelContext();
    Channel channel = await client.connect(hostAndPort, channelContext);
    await channel.write(channelContext, request);

    return httpResponseHandler.getResponse(timeout).whenComplete(() => channel.close());
  }

  /// 发送代理请求
  static Future<HttpResponse> proxyRequest(HttpRequest request,
      {ProxyInfo? proxyInfo, Duration timeout = const Duration(seconds: 30)}) async {
    if (request.headers.host == null || request.headers.host?.trim().isEmpty == true) {
      try {
        var uri = Uri.parse(request.requestUrl);
        request.headers.host = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      } catch (_) {}
    }

    ChannelContext channelContext = ChannelContext();
    var httpResponseHandler = HttpResponseHandler();
    request.hostAndPort ??= HostAndPort.of(request.requestUrl);

    Channel channel =
        await proxyConnect(request, proxyInfo: proxyInfo, request.hostAndPort!, httpResponseHandler, channelContext);

    if (!request.uri.startsWith("/")) {
      Uri? uri = request.requestUri;
      // 裸域名（如 https://example.com）的 uri.path 为空，需要补一个 "/"，
      final path = uri!.path.isEmpty ? '/' : uri.path;
      request = request.copy(uri: '$path${uri.hasQuery ? '?${uri.query}' : ''}');
    }

    if (channel.selectedProtocol == 'h2') {
      request.headers.remove(HttpHeaders.HOST);
      request.streamId = 1;
    }
    await channel.write(channelContext, request);
    final response = await httpResponseHandler.getResponse(timeout).whenComplete(() => channel.close());
    return _answerDigestChallenge(request, response, proxyInfo: proxyInfo, timeout: timeout);
  }

  // ---------------------------------------------------------------------------
  // Digest authentication (RFC 7616, backwards compatible with RFC 2617)
  //
  // A Digest header cannot be precomputed: it needs the server's realm/nonce
  // from a 401 challenge. The composer's Authorization tab therefore only
  // stashes credentials in `request.attributes` (see composer_auth_tab.dart);
  // everything below turns that stash into a header on exactly one retry.
  // ---------------------------------------------------------------------------

  /// Attribute keys written by the composer's Digest Auth mode.
  static const String digestUserAttr = 'qanis.auth.digest.username';
  static const String digestPassAttr = 'qanis.auth.digest.password';

  static const String _authorizationHeader = 'Authorization';
  static const String _wwwAuthenticateHeader = 'www-authenticate';

  static final Random _digestRandom = Random.secure();

  /// Answers a 401 Digest challenge with a single retry.
  ///
  /// Returns [response] untouched unless it is a 401 whose `WWW-Authenticate`
  /// header carries a Digest challenge this client can compute *and* the
  /// request carries Digest credentials. Never retries twice: the retry goes
  /// through [request.copy], which does not carry `attributes` over, so the
  /// second attempt cannot re-enter this method. Any failure (malformed
  /// challenge, unsupported algorithm, transport error on the retry) returns
  /// the original 401 instead of throwing, so requests that do not use Digest
  /// auth behave exactly as before.
  static Future<HttpResponse> _answerDigestChallenge(HttpRequest request, HttpResponse response,
      {ProxyInfo? proxyInfo, required Duration timeout}) async {
    try {
      if (response.status.code != 401) {
        return response;
      }

      final username = request.attributes[digestUserAttr];
      final password = request.attributes[digestPassAttr];
      if (username is! String || password is! String) {
        return response;
      }

      final challenge = _digestChallenge(response.headers);
      if (challenge == null) {
        return response;
      }

      final authorization = _digestAuthorization(challenge,
          username: username, password: password, method: request.method.name, uri: _digestUri(request));
      if (authorization == null) {
        return response;
      }

      final retry = request.copy();
      retry.headers.set(_authorizationHeader, authorization);
      return await proxyRequest(retry, proxyInfo: proxyInfo, timeout: timeout);
    } catch (e) {
      logger.w('digest auth: challenge not answered: $e');
      return response;
    }
  }

  /// First `WWW-Authenticate` value that is a Digest challenge, if any.
  static String? _digestChallenge(HttpHeaders headers) {
    final values = headers.getList(_wwwAuthenticateHeader);
    if (values == null) {
      return null;
    }
    for (final value in values) {
      if (RegExp(r'^\s*digest\b', caseSensitive: false).hasMatch(value)) {
        return value;
      }
    }
    return null;
  }

  /// Parses `Digest realm="r", qop="auth,auth-int", nonce="n", ...` into its
  /// parameters (names lower-cased, quoting and escapes removed). Commas inside
  /// quoted values are kept, so `qop="auth,auth-int"` stays one value.
  static Map<String, String> _digestParams(String challenge) {
    final params = <String, String>{};
    final text = challenge.trim();
    final schemeEnd = text.indexOf(' ');
    if (schemeEnd < 0) {
      return params;
    }

    final body = text.substring(schemeEnd + 1);
    var i = 0;
    while (i < body.length) {
      // Skip the separator run between parameters.
      while (i < body.length && (body[i] == ',' || body[i].trim().isEmpty)) {
        i++;
      }

      final nameStart = i;
      while (i < body.length && body[i] != '=' && body[i] != ',') {
        i++;
      }
      if (i >= body.length || body[i] == ',') {
        continue; // a token without a value; the skip loop above moves on
      }

      final name = body.substring(nameStart, i).trim().toLowerCase();
      i++; // '='
      while (i < body.length && body[i].trim().isEmpty) {
        i++;
      }

      String value;
      if (i < body.length && body[i] == '"') {
        i++;
        final buffer = StringBuffer();
        while (i < body.length && body[i] != '"') {
          if (body[i] == '\\' && i + 1 < body.length) {
            i++; // quoted-pair: keep the escaped character verbatim
          }
          buffer.write(body[i]);
          i++;
        }
        i++; // closing quote
        value = buffer.toString();
      } else {
        final valueStart = i;
        while (i < body.length && body[i] != ',') {
          i++;
        }
        value = body.substring(valueStart, i).trim();
      }

      if (name.isNotEmpty) {
        params[name] = value;
      }
    }
    return params;
  }

  /// Builds the `Authorization: Digest ...` value for [challenge], or null when
  /// the challenge cannot be answered (no nonce, unsupported algorithm, or only
  /// auth-int offered).
  static String? _digestAuthorization(String challenge,
      {required String username, required String password, required String method, required String uri}) {
    final params = _digestParams(challenge);

    final nonce = params['nonce'];
    if (nonce == null || nonce.isEmpty) {
      return null;
    }
    final realm = params['realm'] ?? '';

    final algorithmParam = (params['algorithm'] ?? '').trim();
    final algorithm = algorithmParam.isEmpty ? 'MD5' : algorithmParam.toUpperCase();
    final bool isSess;
    final String canonicalAlgorithm;
    if (algorithm == 'MD5' || algorithm == 'SHA-256') {
      isSess = false;
      canonicalAlgorithm = algorithm;
    } else if (algorithm == 'MD5-SESS') {
      isSess = true;
      canonicalAlgorithm = 'MD5-sess';
    } else if (algorithm == 'SHA-256-SESS') {
      isSess = true;
      canonicalAlgorithm = 'SHA-256-sess';
    } else {
      return null; // SHA-512-256 etc.: not computable here, leave the 401 alone
    }

    // qop is a list; only "auth" is computable (auth-int needs an entity-body
    // hash this client does not send).
    String? qop;
    final qopParam = params['qop'];
    if (qopParam != null && qopParam.trim().isNotEmpty) {
      final offered = qopParam.split(',').map((e) => e.trim().toLowerCase());
      if (!offered.contains('auth')) {
        return null;
      }
      qop = 'auth';
    }

    const nc = '00000001';
    final cnonce = _randomHex(16);
    final opaque = params['opaque'];

    final ha1Base = _digestHex(algorithm, '$username:$realm:$password');
    final ha1 = isSess ? _digestHex(algorithm, '$ha1Base:$nonce:$cnonce') : ha1Base;
    final ha2 = _digestHex(algorithm, '${method.toUpperCase()}:$uri');
    final responseHash = qop == null
        ? _digestHex(algorithm, '$ha1:$nonce:$ha2')
        : _digestHex(algorithm, '$ha1:$nonce:$nc:$cnonce:$qop:$ha2');

    final buffer = StringBuffer('Digest ')
      ..write('username="${_digestQuote(username)}"')
      ..write(', realm="${_digestQuote(realm)}"')
      ..write(', nonce="${_digestQuote(nonce)}"')
      ..write(', uri="${_digestQuote(uri)}"')
      ..write(', response="$responseHash"');
    if (qop != null) {
      buffer.write(', qop=$qop, nc=$nc, cnonce="$cnonce"');
    } else if (isSess) {
      buffer.write(', cnonce="$cnonce"'); // required by -sess even without qop
    }
    if (opaque != null) {
      buffer.write(', opaque="${_digestQuote(opaque)}"');
    }
    if (canonicalAlgorithm != 'MD5') {
      // MD5 is the default; the sess/SHA-256 variants must be declared.
      buffer.write(', algorithm=$canonicalAlgorithm');
    }
    return buffer.toString();
  }

  /// MD5 for MD5/MD5-sess, SHA-256 for SHA-256/SHA-256-sess (RFC 7616 §3.2).
  static String _digestHex(String algorithm, String data) {
    final bytes = Uint8List.fromList(utf8.encode(data));
    final digest = algorithm.startsWith('SHA-256') ? SHA256Digest() : MD5Digest();
    return _digestHexEncode(digest.process(bytes));
  }

  static String _digestHexEncode(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Random 16-hex-character client nonce (64 bits).
  static String _randomHex(int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_digestRandom.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// Escapes a quoted-string value (RFC 7230 §3.2.6).
  static String _digestQuote(String value) => value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  /// The `uri` the digest is computed over: path plus query, as sent.
  static String _digestUri(HttpRequest request) {
    final parsed = request.requestUri;
    if (parsed != null) {
      final path = parsed.path.isEmpty ? '/' : parsed.path;
      return parsed.hasQuery ? '$path?${parsed.query}' : path;
    }
    final raw = request.uri;
    return raw.startsWith('/') ? raw : '/';
  }
}

class Http2ClientHandler {
  static const int FLAG_ACK = 0x1;

  ByteBuf byteBuf = ByteBuf();
  Http2ResponseDecoder decoder = Http2ResponseDecoder();
  final ChannelHandler<HttpResponse> handler;

  Http2ClientHandler(this.handler);

  Future<void> listen(Channel channel, ChannelContext channelContext) async {
    channel.dispatcher.encoder = Http2RequestDecoder();
    channel.dispatcher.decoder = decoder;

    channel.socket.listen((data) => onData(channelContext, channel, data),
        onError: (error, trace) => handler.exceptionCaught(channelContext, channel, error, trace: trace),
        onDone: () => handler.channelInactive(channelContext, channel));

    await channel.writeBytes(Http2Codec.connectionPrefacePRI);

    //发送setting
    final streamSetting = StreamSetting();
    streamSetting.headTableSize = 65536;
    streamSetting.initialWindowSize = 1048896;
    streamSetting.maxHeaderListSize = 262144;

    var payload = Uint8List(6 * 3);
    int offset = 0;
    // SETTINGS_HEADER_TABLE_SIZE
    setInt16(payload, offset, 1);
    offset += 2;
    setInt32(payload, offset, streamSetting.headTableSize);
    offset += 4;

    // SETTINGS_INITIAL_WINDOW_SIZE
    setInt16(payload, offset, 4);
    offset += 2;
    setInt32(payload, offset, streamSetting.initialWindowSize);
    offset += 4;

    //SETTINGS_MAX_FRAME_SIZE
    setInt16(payload, offset, 6);
    offset += 2;
    setInt32(payload, offset, streamSetting.maxHeaderListSize!);
    offset += 4;

    var settingFrame = FrameHeader(payload.length, FrameType.settings, 0, 0);
    var buffer = settingFrame.encode()..addAll(payload);
    await channel.writeBytes(buffer);
  }

  void onData(ChannelContext channelContext, Channel channel, Uint8List data) {
    byteBuf.add(data);
    var decodeResult = decoder.decode(channelContext, byteBuf);

    if (!decodeResult.isDone) {
      return;
    }

    byteBuf.clearRead();

    if (decodeResult.forward != null) {
      ByteBuf buffer = ByteBuf(decodeResult.forward);

      FrameHeader? frameHeader = FrameReader.readFrameHeader(buffer);
      logger.d("Http2ClientHandler forward ${frameHeader?.type}");
      if (frameHeader?.type == FrameType.settings) {
        // 检查是否需要发送 ACK
        if (frameHeader!.hasAckFlag == false) {
          // 发送带有 ACK 标志的 SETTINGS 帧
          var ackFrame = FrameHeader(0, FrameType.settings, FLAG_ACK, 0);
          channel.writeBytes(ackFrame.encode());
        }
      }

      return;
    }

    handler.channelRead(channelContext, channel, decodeResult.data!);
  }
}

class HttpResponseHandler extends ChannelHandler<HttpResponse> {
  Completer<HttpResponse> _completer = Completer<HttpResponse>();

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, HttpResponse msg) async {
    // log.i("[${channel.id}] Response $msg");
    _completer.complete(msg);
  }

  Future<HttpResponse> getResponse(Duration duration) {
    return _completer.future.timeout(duration);
  }

  void resetResponse() {
    _completer = Completer<HttpResponse>();
  }
}

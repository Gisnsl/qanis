/*
 * QANIS — request composer: "Authorization" tab.
 *
 * Self-contained widget that edits `HttpRequest.headers` (and, for API-key-in-query,
 * the request URL) as the user types. No packages beyond flutter/material, dart:convert,
 * the QANIS utils (DarkPalette) and the http model.
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/ui/component/utils.dart';

/// Authorization schemes offered by the composer, in menu order.
enum _AuthType { inherit, none, basic, bearer, apiKey, digest }

extension on _AuthType {
  String get label => switch (this) {
        _AuthType.inherit => 'Inherit',
        _AuthType.none => 'None',
        _AuthType.basic => 'Basic Auth',
        _AuthType.bearer => 'Bearer Token',
        _AuthType.apiKey => 'API Key',
        _AuthType.digest => 'Digest Auth',
      };
}

/// Authorization tab of the request composer.
///
/// Every keystroke / toggle immediately rewrites the outgoing auth material on
/// [request]: the `Authorization` header, a custom API-key header, the URL query,
/// or nothing at all (Inherit / None / Digest).
class ComposerAuthTab extends StatefulWidget {
  final HttpRequest request;
  final VoidCallback? onChanged;

  const ComposerAuthTab({super.key, required this.request, this.onChanged});

  @override
  State<ComposerAuthTab> createState() => _ComposerAuthTabState();
}

class _ComposerAuthTabState extends State<ComposerAuthTab> {
  static const String _authorization = 'Authorization';
  static const String _defaultApiKeyName = 'X-API-Key';

  /// attribute keys the sender reads to answer a Digest challenge at runtime
  static const String _digestUserAttr = 'qanis.auth.digest.username';
  static const String _digestPassAttr = 'qanis.auth.digest.password';

  _AuthType _type = _AuthType.inherit;

  // Basic
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;

  // Bearer
  late final TextEditingController _tokenCtrl;

  // API Key
  late final TextEditingController _apiNameCtrl;
  late final TextEditingController _apiValueCtrl;
  bool _apiInHeader = true;

  // Digest
  late final TextEditingController _digestUserCtrl;
  late final TextEditingController _digestPassCtrl;

  /// Custom header this widget last wrote (so a renamed key does not linger).
  String? _appliedCustomHeader;

  /// Query parameter this widget last appended (so it can be withdrawn again).
  String? _appliedQueryKey;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _tokenCtrl = TextEditingController();
    _apiNameCtrl = TextEditingController(text: _defaultApiKeyName);
    _apiValueCtrl = TextEditingController();
    _digestUserCtrl = TextEditingController();
    _digestPassCtrl = TextEditingController();
    _syncFromRequest();
  }

  @override
  void didUpdateWidget(covariant ComposerAuthTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request, widget.request)) {
      _appliedCustomHeader = null;
      _appliedQueryKey = null;
      _syncFromRequest();
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _tokenCtrl.dispose();
    _apiNameCtrl.dispose();
    _apiValueCtrl.dispose();
    _digestUserCtrl.dispose();
    _digestPassCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // State <-> request
  // ---------------------------------------------------------------------------

  /// Reads whatever auth is already on the request so the tab opens in a
  /// truthful state. Never writes.
  void _syncFromRequest() {
    final headers = widget.request.headers;
    final raw = headers.get(_authorization);
    final auth = raw?.trim() ?? '';

    if (auth.isEmpty) {
      _type = _AuthType.inherit;
      return;
    }

    final lower = auth.toLowerCase();
    if (lower.startsWith('basic ')) {
      _type = _AuthType.basic;
      final decoded = _tryBase64(auth.substring(6).trim());
      if (decoded != null) {
        final i = decoded.indexOf(':');
        if (i >= 0) {
          _userCtrl.text = decoded.substring(0, i);
          _passCtrl.text = decoded.substring(i + 1);
        } else {
          _userCtrl.text = decoded;
        }
      }
      return;
    }

    if (lower.startsWith('bearer ')) {
      _type = _AuthType.bearer;
      _tokenCtrl.text = auth.substring(7).trim();
      return;
    }

    if (lower.startsWith('digest ')) {
      _type = _AuthType.digest;
      final user = widget.request.attributes[_digestUserAttr];
      if (user is String) _digestUserCtrl.text = user;
      final pass = widget.request.attributes[_digestPassAttr];
      if (pass is String) _digestPassCtrl.text = pass;
      return;
    }

    // Unknown scheme (or a bare API key on a custom header): edit it as an API key.
    _type = _AuthType.apiKey;
    _apiNameCtrl.text = headers.getOriginalName(_authorization);
    _apiValueCtrl.text = auth;
  }

  static String? _tryBase64(String value) {
    try {
      return utf8.decode(base64.decode(value));
    } catch (_) {
      return null;
    }
  }

  void _setType(_AuthType next) {
    setState(() => _type = next);
    _apply();
  }

  /// Rewrites the request's auth material to match the current form state.
  void _apply() {
    final headers = widget.request.headers;

    // Drop whatever a previous selection wrote before writing the new state.
    if (_appliedCustomHeader != null && _appliedCustomHeader!.toLowerCase() != 'authorization') {
      headers.remove(_appliedCustomHeader!);
    }
    _appliedCustomHeader = null;

    switch (_type) {
      case _AuthType.inherit:
      case _AuthType.none:
        headers.remove(_authorization);
        _withdrawQueryKey();
        _clearDigest();

      case _AuthType.basic:
        _withdrawQueryKey();
        _clearDigest();
        final user = _userCtrl.text;
        final pass = _passCtrl.text;
        if (user.isEmpty && pass.isEmpty) {
          headers.remove(_authorization);
        } else {
          headers.set(_authorization, 'Basic ${base64.encode(utf8.encode('$user:$pass'))}');
        }

      case _AuthType.bearer:
        _withdrawQueryKey();
        _clearDigest();
        final token = _tokenCtrl.text.trim();
        if (token.isEmpty) {
          headers.remove(_authorization);
        } else {
          headers.set(_authorization, 'Bearer $token');
        }

      case _AuthType.apiKey:
        headers.remove(_authorization);
        _clearDigest();
        final name = _apiNameCtrl.text.trim().isEmpty ? _defaultApiKeyName : _apiNameCtrl.text.trim();
        final value = _apiValueCtrl.text;
        if (_apiInHeader) {
          _withdrawQueryKey();
          if (name.toLowerCase() == 'authorization') {
            if (value.isEmpty) {
              headers.remove(_authorization);
            } else {
              headers.set(_authorization, value);
            }
          } else if (value.isEmpty) {
            headers.remove(name);
          } else {
            headers.set(name, value);
            _appliedCustomHeader = name;
          }
        } else {
          // Query mode: no header is emitted, the key rides on the URL.
          _appendQueryKey(name, value);
        }

      case _AuthType.digest:
        // A Digest response cannot be precomputed: it needs the server's nonce
        // and realm from a 401 challenge. Credentials are stashed for the
        // sender to use when it answers the challenge.
        headers.remove(_authorization);
        _withdrawQueryKey();
        final user = _digestUserCtrl.text;
        final pass = _digestPassCtrl.text;
        if (user.isEmpty && pass.isEmpty) {
          _clearDigest();
        } else {
          widget.request.attributes[_digestUserAttr] = user;
          widget.request.attributes[_digestPassAttr] = pass;
        }
    }

    widget.onChanged?.call();
  }

  void _clearDigest() {
    widget.request.attributes.remove(_digestUserAttr);
    widget.request.attributes.remove(_digestPassAttr);
  }

  // ---------------------------------------------------------------------------
  // Query-string handling (API key sent as a query parameter)
  // ---------------------------------------------------------------------------

  /// Appends (or replaces) `name=value` on [HttpRequest.uri] — which does have a
  /// setter, so the edit survives into the sent request.
  void _appendQueryKey(String name, String value) {
    if (name.isEmpty) return;
    // The key name itself may have been edited: drop the previous pair first.
    if (_appliedQueryKey != null && _appliedQueryKey != name) {
      _withdrawQueryKey();
    }
    final current = widget.request.uri;
    if (current.isEmpty) return; // nothing to append to

    final updated = _rewriteQuery(current, name: name, value: value);
    if (updated == null || updated == current) return;

    widget.request.uri = updated; // invalidates the cached requestUri
    _appliedQueryKey = name;
  }

  void _withdrawQueryKey() {
    final key = _appliedQueryKey;
    if (key == null) return;
    _appliedQueryKey = null;
    final current = widget.request.uri;
    if (current.isEmpty) return;
    final updated = _rewriteQuery(current, name: key, value: null);
    if (updated != null && updated != current) {
      widget.request.uri = updated;
    }
  }

  /// Rebuilds [raw] keeping every other query pair byte-for-byte and setting
  /// (or removing, when [value] is null/empty) the [name] pair.
  /// Works for both absolute URLs and bare `path?query` values.
  static String? _rewriteQuery(String raw, {required String name, required String? value}) {
    try {
      final hashAt = raw.indexOf('#');
      final fragment = hashAt >= 0 ? raw.substring(hashAt) : '';
      final body = hashAt >= 0 ? raw.substring(0, hashAt) : raw;

      final qAt = body.indexOf('?');
      final pathPart = qAt >= 0 ? body.substring(0, qAt) : body;
      final queryPart = qAt >= 0 ? body.substring(qAt + 1) : '';

      final kept = <String>[];
      if (queryPart.isNotEmpty) {
        for (final pair in queryPart.split('&')) {
          if (pair.isEmpty) continue;
          final eq = pair.indexOf('=');
          final rawKey = eq >= 0 ? pair.substring(0, eq) : pair;
          String decodedKey;
          try {
            decodedKey = Uri.decodeQueryComponent(rawKey);
          } catch (_) {
            decodedKey = rawKey;
          }
          if (decodedKey == name) continue;
          kept.add(pair);
        }
      }

      if (value != null && value.isNotEmpty) {
        kept.add('${Uri.encodeQueryComponent(name)}=${Uri.encodeQueryComponent(value)}');
      }

      final query = kept.isEmpty ? '' : '?${kept.join('&')}';
      return '$pathPart$query$fragment';
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _typeRow(),
          const SizedBox(height: 10),
          ..._body(),
        ],
      ),
    );
  }

  Widget _typeRow() {
    return Row(
      children: [
        const Text('Authorization', style: TextStyle(fontSize: 13, color: DarkPalette.text2)),
        const Spacer(),
        PopupMenuButton<_AuthType>(
          tooltip: '',
          color: DarkPalette.panel,
          elevation: 6,
          position: PopupMenuPosition.under,
          offset: const Offset(0, 4),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: DarkPalette.divider, width: 0.5),
          ),
          onSelected: _setType,
          itemBuilder: (context) => [
            for (final type in _AuthType.values)
              PopupMenuItem<_AuthType>(
                value: type,
                height: 36,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // fixed-width check slot keeps every label on the same x
                    SizedBox(
                      width: 16,
                      child: type == _type
                          ? const Icon(Icons.check, size: 14, color: DarkPalette.primary)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: type == _type ? DarkPalette.primary : DarkPalette.text1,
                        fontWeight: type == _type ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_type.label, style: const TextStyle(fontSize: 13, color: DarkPalette.primary)),
                const Icon(Icons.arrow_drop_down, size: 18, color: DarkPalette.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _body() {
    switch (_type) {
      case _AuthType.inherit:
        return [_hint("Uses the collection's authorization")];

      case _AuthType.none:
        return [_hint('No authorization header is sent')];

      case _AuthType.basic:
        return [
          _field(controller: _userCtrl, hint: 'Username'),
          const SizedBox(height: 10),
          _field(controller: _passCtrl, hint: 'Password', obscure: true),
        ];

      case _AuthType.bearer:
        return [_field(controller: _tokenCtrl, hint: 'Token')];

      case _AuthType.apiKey:
        return [
          _field(controller: _apiNameCtrl, hint: 'Key name'),
          const SizedBox(height: 10),
          _field(controller: _apiValueCtrl, hint: 'Value'),
          const SizedBox(height: 10),
          _addToRow(),
        ];

      case _AuthType.digest:
        return [
          _field(controller: _digestUserCtrl, hint: 'Username'),
          const SizedBox(height: 10),
          _field(controller: _digestPassCtrl, hint: 'Password', obscure: true),
          const SizedBox(height: 10),
          _hint('The challenge is answered at runtime'),
        ];
    }
    // ignore: dead_code
    return const <Widget>[];
  }

  Widget _hint(String text) {
    return Text(text, style: const TextStyle(fontSize: 13, color: DarkPalette.text3));
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: DarkPalette.divider, width: 0.5),
    );

    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 13, color: DarkPalette.text1),
      cursorColor: DarkPalette.primary,
      cursorHeight: 14,
      onChanged: (_) => _apply(),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: DarkPalette.bg,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: DarkPalette.text3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DarkPalette.primary, width: 1),
        ),
      ),
    );
  }

  Widget _addToRow() {
    return Row(
      children: [
        const Text('Add to', style: TextStyle(fontSize: 13, color: DarkPalette.text2)),
        const Spacer(),
        _segment('Header', _apiInHeader, () {
          if (_apiInHeader) return;
          setState(() => _apiInHeader = true);
          _apply();
        }),
        const SizedBox(width: 6),
        _segment('Query', !_apiInHeader, () {
          if (!_apiInHeader) return;
          setState(() => _apiInHeader = false);
          _apply();
        }),
      ],
    );
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? DarkPalette.primary.withValues(alpha: 0.16) : DarkPalette.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? DarkPalette.primary : DarkPalette.divider,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? DarkPalette.primary : DarkPalette.text2,
          ),
        ),
      ),
    );
  }
}

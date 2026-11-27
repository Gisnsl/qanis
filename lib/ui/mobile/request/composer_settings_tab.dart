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
import 'package:flutter/services.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/ui/component/utils.dart';

/// Composer option rows share one geometry.
const double _kRowHeight = 48;
const double _kHairline = 0.5;
const double _kHPadding = 16;

const _kFieldBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(6)),
  borderSide: BorderSide(color: DarkPalette.divider, width: 0.5),
);

const _kTimeoutDecoration = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: DarkPalette.bg,
  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  border: _kFieldBorder,
  enabledBorder: _kFieldBorder,
  focusedBorder: _kFieldBorder,
  disabledBorder: _kFieldBorder,
  errorBorder: _kFieldBorder,
  focusedErrorBorder: _kFieldBorder,
);

/// Process-wide composer options.
///
/// These live outside [HttpRequest] on purpose: they describe how the outgoing
/// request should be *sent* (redirects, cookies, HTTP/2, timeout) rather than
/// the request payload itself, and they stay put while the user composes one
/// request after another.
class ComposerSettings {
  ComposerSettings._();

  /// Default timeout used when nothing else was chosen.
  static const int defaultTimeoutMs = 30000;

  /// Follow 3xx redirects automatically.
  static bool followRedirects = true;

  /// Per-request timeout in milliseconds.
  static int timeoutMs = defaultTimeoutMs;

  /// Attach the cookie jar's cookies to the outgoing request.
  static bool sendCookies = true;

  /// Prefer HTTP/2 when the server supports it.
  static bool http2 = false;

  /// Restore every option to its default value.
  static void reset() {
    followRedirects = true;
    timeoutMs = defaultTimeoutMs;
    sendCookies = true;
    http2 = false;
  }
}

/// Composer tab: per-request send options (redirects, timeout, cookies, HTTP/2).
class ComposerSettingsTab extends StatefulWidget {
  final HttpRequest request;
  final VoidCallback? onChanged;

  const ComposerSettingsTab({super.key, required this.request, this.onChanged});

  @override
  State<ComposerSettingsTab> createState() => _ComposerSettingsTabState();
}

class _ComposerSettingsTabState extends State<ComposerSettingsTab> {
  late bool _followRedirects;
  late bool _sendCookies;
  late bool _http2;

  late final TextEditingController _timeoutController;
  final FocusNode _timeoutFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _followRedirects = ComposerSettings.followRedirects;
    _sendCookies = ComposerSettings.sendCookies;
    _http2 = ComposerSettings.http2;

    _timeoutController = TextEditingController(text: ComposerSettings.timeoutMs.toString());
    _timeoutFocus.addListener(_handleTimeoutFocus);
  }

  @override
  void dispose() {
    _timeoutFocus.removeListener(_handleTimeoutFocus);
    _timeoutFocus.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  /// On blur, never leave the field empty or unparsable — snap back to the
  /// value that is actually in effect.
  void _handleTimeoutFocus() {
    if (_timeoutFocus.hasFocus) {
      return;
    }
    final text = ComposerSettings.timeoutMs.toString();
    if (_timeoutController.text != text) {
      _timeoutController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _handleTimeoutChanged(String value) {
    final ms = int.tryParse(value);
    if (ms == null || ms <= 0) {
      // Empty or partial input: keep the previous value, the blur handler
      // restores the field text once the user is done.
      return;
    }
    if (ComposerSettings.timeoutMs == ms) {
      return;
    }
    ComposerSettings.timeoutMs = ms;
    widget.onChanged?.call();
  }

  void _setFollowRedirects(bool value) {
    if (_followRedirects == value) return;
    setState(() => _followRedirects = value);
    ComposerSettings.followRedirects = value;
    widget.onChanged?.call();
  }

  void _setSendCookies(bool value) {
    if (_sendCookies == value) return;
    setState(() => _sendCookies = value);
    ComposerSettings.sendCookies = value;
    widget.onChanged?.call();
  }

  void _setHttp2(bool value) {
    if (_http2 == value) return;
    setState(() => _http2 = value);
    ComposerSettings.http2 = value;
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _switchRow(
          label: 'Follow redirects',
          value: _followRedirects,
          onChanged: _setFollowRedirects,
        ),
        const _Hairline(),
        _numberRow(
          label: 'Timeout (ms)',
          controller: _timeoutController,
          focusNode: _timeoutFocus,
          onChanged: _handleTimeoutChanged,
        ),
        const _Hairline(),
        _switchRow(
          label: 'Send cookies',
          value: _sendCookies,
          onChanged: _setSendCookies,
        ),
        const _Hairline(),
        _switchRow(
          label: 'HTTP/2',
          value: _http2,
          onChanged: _setHttp2,
        ),
      ],
    );
  }

  /// Fixed-height row: label left, control right. Built by hand (no ListTile)
  /// so the surrounding Material theme cannot change paddings or heights.
  Widget _row({required String label, required Widget control}) {
    return SizedBox(
      height: _kRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kHPadding),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: DarkPalette.text1),
              ),
            ),
            const SizedBox(width: 12),
            control,
          ],
        ),
      ),
    );
  }

  Widget _switchRow({required String label, required bool value, required ValueChanged<bool> onChanged}) {
    return _row(
      label: label,
      control: SizedBox(
        // The switch lays out at its intrinsic 52x32 even when scaled down, so
        // the slot must be at least that wide.
        width: 52,
        height: _kRowHeight,
        child: Center(
          child: Transform.scale(
            scale: 0.85,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected) ? Colors.white : DarkPalette.text2;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? DarkPalette.primary
                    : DarkPalette.border;
              }),
              trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected) ? DarkPalette.primary : DarkPalette.divider;
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberRow({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
  }) {
    return _row(
      label: label,
      control: SizedBox(
        width: 96,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          textAlignVertical: TextAlignVertical.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          cursorColor: DarkPalette.primary,
          style: const TextStyle(fontSize: 13, color: DarkPalette.text1),
          decoration: _kTimeoutDecoration,
        ),
      ),
    );
  }
}

/// 0.5dp hairline between rows.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHPadding),
      child: Container(height: _kHairline, color: DarkPalette.divider),
    );
  }
}

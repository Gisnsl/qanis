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
import 'package:qanis/network/http/http.dart';
import 'package:qanis/ui/component/utils.dart';

const _kNotesBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
  borderSide: BorderSide(color: DarkPalette.divider, width: 0.5),
);

const _kNotesDecoration = InputDecoration(
  hintText: 'Describe this request…',
  hintStyle: TextStyle(fontSize: 13, color: DarkPalette.text3),
  filled: true,
  fillColor: DarkPalette.bg,
  isDense: true,
  contentPadding: EdgeInsets.all(16),
  border: _kNotesBorder,
  enabledBorder: _kNotesBorder,
  disabledBorder: _kNotesBorder,
  focusedBorder: _kNotesBorder,
  errorBorder: _kNotesBorder,
  focusedErrorBorder: _kNotesBorder,
);

/// Composer tab: free-form notes for the request being composed.
///
/// The text is written straight into [HttpRequest.comment] on every change so
/// that switching tabs (or rebuilding the composer) never loses it, and
/// [onChanged] lets the host screen mark itself dirty.
class ComposerDocsTab extends StatefulWidget {
  final HttpRequest request;
  final VoidCallback? onChanged;

  const ComposerDocsTab({super.key, required this.request, this.onChanged});

  @override
  State<ComposerDocsTab> createState() => _ComposerDocsTabState();
}

class _ComposerDocsTabState extends State<ComposerDocsTab> {
  /// Minimum height of the notes area, in lines of 13sp text.
  static const int _minLines = 8;

  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.request.comment ?? '');
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant ComposerDocsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The composer may hand us a different request (e.g. after "load request
    // from response"): mirror its comment without disturbing the cursor while
    // the user is typing in the same request.
    if (!identical(oldWidget.request, widget.request)) {
      final text = widget.request.comment ?? '';
      if (_controller.text != text) {
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  void _handleTextChanged() {
    // The listener also fires for selection/composing changes; only react to
    // actual text edits.
    final text = _controller.text;
    if (widget.request.comment == text) {
      return;
    }
    widget.request.comment = text;
    widget.onChanged?.call();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final field = TextField(
            controller: _controller,
            focusNode: _focusNode,
            minLines: _minLines,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            cursorColor: DarkPalette.primary,
            style: const TextStyle(fontSize: 13, height: 1.45, color: DarkPalette.text1),
            decoration: _kNotesDecoration,
          );

          // Fill the tab when the composer gives us a bounded height, but fall
          // back to the 8-line minimum when the tab sits in a scroll view.
          final fillsHeight = constraints.hasBoundedHeight;

          return Column(
            mainAxisSize: fillsHeight ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fillsHeight) Expanded(child: field) else field,
              const SizedBox(height: 10),
              const Text(
                'Saved with the request',
                style: TextStyle(fontSize: 11, color: DarkPalette.text3),
              ),
            ],
          );
        },
      ),
    );
  }
}

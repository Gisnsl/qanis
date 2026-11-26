/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'package:flutter/material.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/ui/toolbox/encoder.dart';

/// Encode / Decode hub: one flat list that opens each codec directly from the
/// side menu, so the tools no longer require the toolbox tab.
class CodecHubPage extends StatelessWidget {
  const CodecHubPage({super.key});

  static const _entries = <_CodecEntry>[
    _CodecEntry(EncoderType.url, 'URL Encode / Decode', 'Percent-encode a URL or decode %XX back to text', Icons.link),
    _CodecEntry(EncoderType.base64, 'Base64 Encode / Decode', 'Encode text to Base64 or decode it back', Icons.code),
    _CodecEntry(EncoderType.unicode, 'Unicode Encode / Decode', 'Convert text to \\uXXXX escapes and back',
        Icons.translate),
    _CodecEntry(EncoderType.md5, 'MD5 Hash', '32-character MD5 digest of any text', Icons.tag),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DarkPalette.bg,
      appBar: AppBar(
        toolbarHeight: 52,
        backgroundColor: DarkPalette.panel,
        foregroundColor: DarkPalette.text1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: DarkPalette.text2, size: 21),
        shape: const Border(bottom: BorderSide(color: DarkPalette.divider, width: 0.5)),
        title: const Text('Encode / Decode',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: DarkPalette.text1)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const Divider(
            height: 0.5, thickness: 0.5, indent: 16, endIndent: 16, color: DarkPalette.divider),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                      backgroundColor: DarkPalette.bg,
                      appBar: AppBar(
                        toolbarHeight: 52,
                        backgroundColor: DarkPalette.panel,
                        foregroundColor: DarkPalette.text1,
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        iconTheme: const IconThemeData(color: DarkPalette.text2, size: 21),
                        shape: const Border(bottom: BorderSide(color: DarkPalette.divider, width: 0.5)),
                        title: Text(entry.title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600, color: DarkPalette.text1)),
                      ),
                      body: EncoderWidget(type: entry.type),
                    ))),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.transparent,
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: DarkPalette.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(entry.icon, size: 19, color: DarkPalette.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.title,
                          style: const TextStyle(fontSize: 14, color: DarkPalette.text1)),
                      const SizedBox(height: 2),
                      Text(entry.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: DarkPalette.text2)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: DarkPalette.text3),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _CodecEntry {
  final EncoderType type;
  final String title;
  final String subtitle;
  final IconData icon;

  const _CodecEntry(this.type, this.title, this.subtitle, this.icon);
}

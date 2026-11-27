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
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:qanis/ui/component/utils.dart';

/// 捐赠 / Donate
///
/// Flat charcoal cards on the QANIS dark palette; every value is copyable
/// (copy button on the right, or tap the whole row).
class DonatePage extends StatelessWidget {
  const DonatePage({super.key});

  /// One copyable payment entry: caption + value.
  static const List<_DonateEntry> _entries = [
    _DonateEntry('Optimism Network:', '0x1bc2ff931ac23107da7abc0a3826edd8da00a7b5'),
    _DonateEntry('Trc(20) Network:', 'TD2sCysnKPi1q4GbQhR3bVZUknamk74A5e'),
    _DonateEntry('Binnace ID 💸 :', '746947043'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DarkPalette.bg,
      appBar: AppBar(
        toolbarHeight: 52,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: DarkPalette.panel,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        shape: const Border(bottom: BorderSide(color: DarkPalette.divider, width: 0.5)),
        title: const Text('Donate', style: TextStyle(fontSize: 16, color: DarkPalette.text1)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('USDT 💸',
              style: TextStyle(fontSize: 15, color: DarkPalette.text1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (var i = 0; i < _entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _DonateCard(entry: _entries[i]),
          ],
        ],
      ),
    );
  }
}

class _DonateEntry {
  final String label;
  final String value;

  const _DonateEntry(this.label, this.value);
}

class _DonateCard extends StatelessWidget {
  final _DonateEntry entry;

  const _DonateCard({required this.entry});

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: entry.value));
    FlutterToastr.show('Copied', context);
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(12));

    return Material(
      color: DarkPalette.panel,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => _copy(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: DarkPalette.divider, width: 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.label, style: const TextStyle(fontSize: 12, color: DarkPalette.text2)),
                    const SizedBox(height: 6),
                    SelectableText(
                      entry.value,
                      // Tap the text itself to copy; long-press / drag still selects.
                      onTap: () => _copy(context),
                      style: const TextStyle(
                        fontSize: 13,
                        color: DarkPalette.text1,
                        fontFamily: 'monospace',
                        letterSpacing: 0.2,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18, color: DarkPalette.text2),
                onPressed: () => _copy(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

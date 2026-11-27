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
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:qanis/network/http/http.dart';
import 'package:qanis/ui/component/utils.dart';
import 'package:qanis/utils/listenable_list.dart';

/// Cookie Jar: every cookie seen in the captured traffic, grouped by host.
/// Read-only view over the live capture list — nothing is stored separately.
class CookieJarPage extends StatefulWidget {
  final ListenableList<HttpRequest> container;

  const CookieJarPage({super.key, required this.container});

  @override
  State<CookieJarPage> createState() => _CookieJarPageState();
}

class _CookieJarPageState extends State<CookieJarPage> {
  String _query = '';

  /// host -> cookie name -> value
  Map<String, Map<String, String>> _collect() {
    final result = <String, Map<String, String>>{};
    for (final request in widget.container) {
      final host = request.requestUri?.host ?? '';
      if (host.isEmpty) continue;
      final bucket = result.putIfAbsent(host, () => <String, String>{});

      void addPairs(String raw) {
        for (final part in raw.split(';')) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) continue;
          final eq = trimmed.indexOf('=');
          if (eq <= 0) continue;
          final name = trimmed.substring(0, eq).trim();
          final value = trimmed.substring(eq + 1).trim();
          if (name.isEmpty) continue;
          bucket[name] = value;
        }
      }

      for (final entry in request.headers.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'cookie') {
          for (final value in entry.value) {
            addPairs(value);
          }
        }
      }
      final response = request.response;
      if (response != null) {
        for (final entry in response.headers.entries) {
          if (entry.key.toLowerCase() != 'set-cookie') continue;
          for (final value in entry.value) {
            final first = value.split(';').first.trim();
            final eq = first.indexOf('=');
            if (eq > 0) {
              bucket[first.substring(0, eq).trim()] = first.substring(eq + 1).trim();
            }
          }
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final all = _collect();
    final hosts = all.keys.where((h) => _query.isEmpty || h.toLowerCase().contains(_query.toLowerCase())).toList()
      ..sort();

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
        title: const Text('Cookie Jar',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: DarkPalette.text1)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(fontSize: 13, color: DarkPalette.text1),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: DarkPalette.panel,
              hintText: 'Filter by host',
              hintStyle: const TextStyle(fontSize: 13, color: DarkPalette.text3),
              prefixIcon: const Icon(Icons.search, size: 18, color: DarkPalette.text3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: DarkPalette.divider, width: 0.5)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: DarkPalette.divider, width: 0.5)),
            ),
          ),
        ),
        Expanded(
          child: hosts.isEmpty
              ? const Center(
                  child: Text('No cookies captured yet',
                      style: TextStyle(fontSize: 13, color: DarkPalette.text3)))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: hosts.length,
                  itemBuilder: (context, index) {
                    final host = hosts[index];
                    final cookies = all[host]!;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text(host,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, color: DarkPalette.primary)),
                      ),
                      ...cookies.entries.map((cookie) => InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: '${cookie.key}=${cookie.value}'));
                              FlutterToastr.show('Copied', context);
                            },
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              decoration: const BoxDecoration(
                                  border: Border(
                                      bottom: BorderSide(color: DarkPalette.divider, width: 0.5))),
                              child: Row(children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(cookie.key,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, color: DarkPalette.text1)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: Text(cookie.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 12.5, color: DarkPalette.text2)),
                                ),
                              ]),
                            ),
                          )),
                    ]);
                  },
                ),
        ),
      ]),
    );
  }
}

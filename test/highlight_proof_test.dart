import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

void main() {
  test('python snippet is highlighted with several colours', () {
    const code = '''
import requests

url = 'https://api.example.com/v1'
headers = {'x-api-key': 'abc123'}
r = requests.post(url, headers=headers, json={'a': 1})
print(r.status_code)  # done
''';
    final h = Highlight();
    for (final entry in builtinAllLanguages.entries) {
      h.registerLanguage(entry.key, entry.value);
    }
    final result = h.highlight(code: code, language: 'python');
    final renderer = TextSpanRenderer(
        const TextStyle(fontFamily: 'monospace', color: Color(0xFFEDEDED)), atomOneDarkTheme);
    result.render(renderer);
    final span = renderer.span!;

    final colours = <int>{};
    span.visitChildren((s) {
      if (s is TextSpan) {
        final c = s.style?.color;
        if (c != null) colours.add(c.toARGB32());
      }
      return true;
    });

    // ignore: avoid_print
    print('distinct colours in the highlighted python snippet: ${colours.length} -> '
        '${colours.map((c) => c.toRadixString(16)).toList()}');
    expect(span.toPlainText(), contains('import requests'));
    expect(colours.length, greaterThan(2),
        reason: 'the snippet must render with several token colours, not one flat colour');
  });

  test('every target language resolves to a grammar', () {
    final h = Highlight();
    for (final entry in builtinAllLanguages.entries) {
      h.registerLanguage(entry.key, entry.value);
    }
    for (final language in [
      'shell', 'python', 'js', 'ts', 'java', 'kotlin', 'swift', 'go', 'rust',
      'php', 'ruby', 'csharp', 'cpp', 'c', 'dart', 'json', 'xml', 'yaml', 'powershell'
    ]) {
      final result = h.highlight(code: 'x = 1', language: language);
      expect(result.language, isNotNull, reason: 'no grammar for $language');
    }
  });
}

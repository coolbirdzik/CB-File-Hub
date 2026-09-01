import 'package:cb_file_manager/ui/utils/preview_syntax_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PreviewSyntaxHighlighter.languageForPath', () {
    test('maps common code extensions', () {
      expect(
        PreviewSyntaxHighlighter.languageForPath('/proj/main.dart'),
        'dart',
      );
      expect(
        PreviewSyntaxHighlighter.languageForPath('/proj/index.ts'),
        'typescript',
      );
      expect(
        PreviewSyntaxHighlighter.languageForPath('/proj/app.jsx'),
        'javascript',
      );
      expect(
        PreviewSyntaxHighlighter.languageForPath('/proj/query.sql'),
        'sql',
      );
    });

    test('maps extensionless basenames', () {
      expect(
        PreviewSyntaxHighlighter.languageForPath('/repo/Dockerfile'),
        'dockerfile',
      );
      expect(
        PreviewSyntaxHighlighter.languageForPath('/repo/Makefile'),
        'makefile',
      );
    });
  });

  group('PreviewSyntaxHighlighter.buildHighlightedSpan', () {
    test('colors dart keywords and strings', () {
      const source = "void main() {\n  print('hi');\n}";
      final span = PreviewSyntaxHighlighter.buildHighlightedSpan(
        source: source,
        filePath: '/tmp/sample.dart',
        baseStyle: const TextStyle(fontSize: 12, color: Colors.black),
        brightness: Brightness.light,
      );

      final flattened = <TextSpan>[];
      void walk(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text != null && span.text!.isNotEmpty) {
            flattened.add(span);
          }
          span.children?.forEach(walk);
        }
      }

      walk(span);
      expect(flattened.length, greaterThan(1));
      expect(
        flattened.any(
          (part) =>
              part.style?.color != null && part.style!.color != Colors.black,
        ),
        isTrue,
      );
    });
  });
}

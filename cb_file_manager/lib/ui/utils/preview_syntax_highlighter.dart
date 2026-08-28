import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node, Result;
import 'package:path/path.dart' as p;

/// Syntax highlighting for the file preview pane (highlight.js via [highlight]).
class PreviewSyntaxHighlighter {
  PreviewSyntaxHighlighter._();

  static const Map<String, String> _extensionToLanguage = {
    'dart': 'dart',
    'js': 'javascript',
    'jsx': 'javascript',
    'mjs': 'javascript',
    'cjs': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'py': 'python',
    'java': 'java',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'swift': 'swift',
    'c': 'c',
    'h': 'c',
    'cpp': 'cpp',
    'cc': 'cpp',
    'cxx': 'cpp',
    'hpp': 'cpp',
    'cs': 'csharp',
    'go': 'go',
    'rs': 'rust',
    'rb': 'ruby',
    'php': 'php',
    'sql': 'sql',
    'json': 'json',
    'xml': 'xml',
    'yaml': 'yaml',
    'yml': 'yaml',
    'html': 'xml',
    'htm': 'xml',
    'css': 'css',
    'scss': 'scss',
    'sass': 'scss',
    'less': 'css',
    'md': 'markdown',
    'markdown': 'markdown',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'fish': 'bash',
    'ps1': 'powershell',
    'bat': 'dos',
    'cmd': 'dos',
    'vue': 'xml',
    'gradle': 'gradle',
    'groovy': 'groovy',
    'scala': 'scala',
    'lua': 'lua',
    'r': 'r',
    'pl': 'perl',
    'pm': 'perl',
    'proto': 'protobuf',
    'graphql': 'graphql',
    'vim': 'vim',
    'toml': 'ini',
    'ini': 'ini',
    'cfg': 'ini',
    'conf': 'ini',
    'properties': 'properties',
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'cmake': 'cmake',
    'tex': 'tex',
    'svg': 'xml',
  };

  static const Map<String, String> _basenameToLanguage = {
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'gnumakefile': 'makefile',
    'cmakelists.txt': 'cmake',
    'gemfile': 'ruby',
    'rakefile': 'ruby',
    'procfile': 'yaml',
    'vagrantfile': 'ruby',
  };

  /// Resolves a highlight.js language id from [filePath], or null for auto-detect.
  static String? languageForPath(String filePath) {
    final basename = p.basename(filePath).toLowerCase();
    final fromBasename = _basenameToLanguage[basename];
    if (fromBasename != null) return fromBasename;

    final ext = p.extension(filePath).toLowerCase();
    if (ext.isEmpty) return null;
    return _extensionToLanguage[ext.substring(1)];
  }

  /// Builds a syntax-colored [TextSpan] tree for [source].
  static TextSpan buildHighlightedSpan({
    required String source,
    required String filePath,
    required TextStyle baseStyle,
    required Brightness brightness,
  }) {
    if (source.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    final language = languageForPath(filePath);
    final Result result = language != null
        ? highlight.parse(source, language: language)
        : highlight.parse(source, autoDetection: true);

    final styles = brightness == Brightness.dark
        ? _darkStyles(baseStyle)
        : _lightStyles(baseStyle);

    final nodes = result.nodes;
    if (nodes == null || nodes.isEmpty) {
      return TextSpan(text: source, style: baseStyle);
    }

    return TextSpan(
      style: baseStyle,
      children:
          nodes.map((node) => _nodeToSpan(node, styles, baseStyle)).toList(),
    );
  }

  static TextSpan _nodeToSpan(
    Node node,
    Map<String, TextStyle> styles,
    TextStyle base,
  ) {
    final style =
        node.className != null ? styles[node.className!] ?? base : base;

    if (node.value != null) {
      return TextSpan(text: node.value, style: style);
    }

    if (node.children != null) {
      return TextSpan(
        children: node.children!
            .map((child) => _nodeToSpan(child, styles, style))
            .toList(),
      );
    }

    return const TextSpan();
  }

  static Map<String, TextStyle> _darkStyles(TextStyle base) {
    TextStyle colored(Color color, {FontStyle? fontStyle}) =>
        base.copyWith(color: color, fontStyle: fontStyle);

    return {
      'keyword': colored(const Color(0xFFCC9AEF)),
      'built_in': colored(const Color(0xFFF2C17B)),
      'type': colored(const Color(0xFF8BE9FD)),
      'literal': colored(const Color(0xFFFF8FA3)),
      'number': colored(const Color(0xFFF2A17B)),
      'string': colored(const Color(0xFFA6E3A1)),
      'regexp': colored(const Color(0xFFA6E3A1)),
      'symbol': colored(const Color(0xFF8BE9FD)),
      'comment': colored(const Color(0xFF6B7089), fontStyle: FontStyle.italic),
      'doctag': colored(const Color(0xFF6B7089), fontStyle: FontStyle.italic),
      'function': colored(const Color(0xFF89B4FA)),
      'title': colored(const Color(0xFF89B4FA)),
      'class': colored(const Color(0xFFF2C17B)),
      'params': colored(const Color(0xFFD8DEE9)),
      'meta': colored(const Color(0xFF6B7089)),
      'attr': colored(const Color(0xFFF2C17B)),
      'attribute': colored(const Color(0xFFF2C17B)),
      'name': colored(const Color(0xFFA6E3A1)),
      'tag': colored(const Color(0xFF89B4FA)),
      'selector-tag': colored(const Color(0xFF89B4FA)),
      'selector-id': colored(const Color(0xFF8BE9FD)),
      'selector-class': colored(const Color(0xFF8BE9FD)),
      'section': colored(const Color(0xFF89B4FA)),
      'bullet': colored(const Color(0xFF89B4FA)),
      'quote': colored(const Color(0xFF6B7089), fontStyle: FontStyle.italic),
      'formula': colored(const Color(0xFF8BE9FD)),
      'variable': colored(const Color(0xFFD8DEE9)),
      'template-variable': colored(const Color(0xFF8BE9FD)),
      'addition': colored(const Color(0xFFA6E3A1)),
      'deletion': colored(const Color(0xFFFF8FA3)),
    };
  }

  static Map<String, TextStyle> _lightStyles(TextStyle base) {
    TextStyle colored(Color color, {FontStyle? fontStyle}) =>
        base.copyWith(color: color, fontStyle: fontStyle);

    return {
      'keyword': colored(const Color(0xFF8959A8)),
      'built_in': colored(const Color(0xFFC18401)),
      'type': colored(const Color(0xFF4271AE)),
      'literal': colored(const Color(0xFFC82829)),
      'number': colored(const Color(0xFFF5871F)),
      'string': colored(const Color(0xFF718C00)),
      'regexp': colored(const Color(0xFF718C00)),
      'symbol': colored(const Color(0xFF4271AE)),
      'comment': colored(const Color(0xFF8E908C), fontStyle: FontStyle.italic),
      'doctag': colored(const Color(0xFF8E908C), fontStyle: FontStyle.italic),
      'function': colored(const Color(0xFF4271AE)),
      'title': colored(const Color(0xFF4271AE)),
      'class': colored(const Color(0xFFC18401)),
      'params': colored(const Color(0xFF4D4D4C)),
      'meta': colored(const Color(0xFF8E908C)),
      'attr': colored(const Color(0xFFC18401)),
      'attribute': colored(const Color(0xFFC18401)),
      'name': colored(const Color(0xFF718C00)),
      'tag': colored(const Color(0xFF4271AE)),
      'selector-tag': colored(const Color(0xFF4271AE)),
      'selector-id': colored(const Color(0xFF4271AE)),
      'selector-class': colored(const Color(0xFF4271AE)),
      'section': colored(const Color(0xFF4271AE)),
      'bullet': colored(const Color(0xFF4271AE)),
      'quote': colored(const Color(0xFF8E908C), fontStyle: FontStyle.italic),
      'formula': colored(const Color(0xFF4271AE)),
      'variable': colored(const Color(0xFF4D4D4C)),
      'template-variable': colored(const Color(0xFF4271AE)),
      'addition': colored(const Color(0xFF718C00)),
      'deletion': colored(const Color(0xFFC82829)),
    };
  }
}

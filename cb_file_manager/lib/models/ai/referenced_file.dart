import 'package:equatable/equatable.dart';

/// Represents a file that was referenced (dropped/dragged) into the chat.
class ReferencedFile extends Equatable {
  /// Absolute path to the file.
  final String path;

  /// File name extracted from path.
  final String fileName;

  /// Whether the file is a text file that can be read.
  final bool isTextFile;

  /// Content of the text file (only set if isTextFile is true).
  final String? content;

  /// Whether the content was successfully read.
  final bool contentLoaded;

  /// Error message if reading failed.
  final String? error;

  const ReferencedFile({
    required this.path,
    required this.fileName,
    required this.isTextFile,
    this.content,
    this.contentLoaded = false,
    this.error,
  });

  ReferencedFile copyWith({
    String? content,
    bool? contentLoaded,
    String? error,
  }) {
    return ReferencedFile(
      path: path,
      fileName: fileName,
      isTextFile: isTextFile,
      content: content ?? this.content,
      contentLoaded: contentLoaded ?? this.contentLoaded,
      error: error ?? this.error,
    );
  }

  /// Returns the file extension (without dot) in lowercase.
  String get extension {
    if (!fileName.contains('.')) return '';
    return fileName.split('.').last.toLowerCase();
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'fileName': fileName,
        'isTextFile': isTextFile,
        'content': content,
        'contentLoaded': contentLoaded,
        'error': error,
      };

  factory ReferencedFile.fromJson(Map<String, dynamic> json) => ReferencedFile(
        path: json['path'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        isTextFile: json['isTextFile'] as bool? ?? false,
        content: json['content'] as String?,
        contentLoaded: json['contentLoaded'] as bool? ?? false,
        error: json['error'] as String?,
      );

  @override
  List<Object?> get props =>
      [path, fileName, isTextFile, content, contentLoaded, error];

  /// Returns true if the file extension matches a known text file type.
  static bool isTextExtension(String ext) {
    const textExts = {
      'txt', 'md', 'markdown', 'json', 'xml', 'yaml', 'yml', 'csv',
      'log', 'ini', 'cfg', 'conf', 'config', 'properties',
      'html', 'htm', 'css', 'scss', 'sass', 'less',
      'js', 'ts', 'tsx', 'jsx', 'mjs', 'cjs',
      'dart', 'py', 'java', 'kt', 'scala', 'groovy',
      'c', 'cpp', 'cc', 'cxx', 'h', 'hpp', 'cs',
      'go', 'rs', 'rb', 'php', 'pl', 'pm',
      'sh', 'bash', 'zsh', 'fish', 'bat', 'ps1', 'cmd',
      'sql', 'toml', 'makefile', 'cmake', 'gradle',
      'gitignore', 'editorconfig', 'dockerfile',
      'vue', 'svelte', 'astro',
      'proto', 'graphql',
      'r', 'lua', 'vim', 'vimrc', 'tmux',
      'lock', 'patch', 'diff',
    };
    return textExts.contains(ext.toLowerCase());
  }
}

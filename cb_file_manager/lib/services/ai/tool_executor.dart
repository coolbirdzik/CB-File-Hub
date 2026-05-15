import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../helpers/files/trash_manager.dart';
import '../../helpers/tags/tag_manager.dart';
import '../../utils/app_logger.dart';
import '../album_service.dart';
import '../video_library_service.dart';

/// Result of executing a tool.
class ToolResult {
  final String toolName;
  final String output;
  final bool success;

  const ToolResult({
    required this.toolName,
    required this.output,
    this.success = true,
  });
}

/// A parsed tool call from the AI response.
class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({required this.name, required this.arguments});
}

/// Executes tools requested by the AI agent.
class ToolExecutor {
  static const int _maxOutputLength = 8000;
  static const int maxToolCalls = 10;
  static const Duration _timeout = Duration(seconds: 15);

  static final _blockedPatterns = RegExp(
    r'(rm\s+-rf|del\s+/[sfq]|format\s|mkfs|dd\s|shutdown|reboot|'
    r':(){ :|taskkill|net\s+stop|reg\s+delete)',
    caseSensitive: false,
  );

  /// Tool names we recognise.
  static const _knownTools = {
    'list_directory',
    'search_files',
    'read_file',
    'write_file',
    'delete_file',
    'get_file_info',
    'run_command',
    'search_by_tag',
    'get_file_tags',
    'list_all_tags',
    'search_content',
    'list_video_libraries',
    'get_video_library_files',
    'list_albums',
    'get_album_files',
  };

  /// Tools that must always go through user approval before executing.
  static const _dangerousTools = {'run_command', 'write_file', 'delete_file'};

  /// Public getter for the BLoC to check.
  static Set<String> get dangerousTools => _dangerousTools;

  /// Parses tool calls from the AI's response text.
  ///
  /// Supports multiple formats:
  /// 1. `<tool_call>{"name":"...","arguments":{...}}</tool_call>`
  /// 2. ```json {"name":"...","arguments":{...}} ```
  /// 3. Bare JSON object with "name" and "arguments" keys
  static List<ToolCall> parseToolCalls(String text) {
    final calls = <ToolCall>[];

    // Format 1: <tool_call> ... </tool_call>
    final tagMatches = RegExp(
      r'<tool_call>\s*([\s\S]*?)\s*</tool_call>',
    ).allMatches(text);
    for (final match in tagMatches) {
      _tryParseCall(match.group(1), calls);
    }

    if (calls.isNotEmpty) return calls;

    // Format 2: ```json { "name": "...", "arguments": {...} } ```
    final codeBlockMatches = RegExp(
      r'```(?:json)?\s*\n?(\{[\s\S]*?\})\s*\n?```',
    ).allMatches(text);
    for (final match in codeBlockMatches) {
      _tryParseCall(match.group(1), calls);
    }

    if (calls.isNotEmpty) return calls;

    // Format 3: bare JSON object with "name" key matching a known tool
    final bareMatches = RegExp(
      r'\{\s*"name"\s*:\s*"(\w+)"[\s\S]*?"arguments"\s*:\s*\{[\s\S]*?\}\s*\}',
    ).allMatches(text);
    for (final match in bareMatches) {
      _tryParseCall(match.group(0), calls);
    }

    return calls;
  }

  static void _tryParseCall(String? jsonStr, List<ToolCall> calls) {
    if (jsonStr == null) return;
    try {
      final json = jsonDecode(jsonStr.trim()) as Map<String, dynamic>;
      final name = json['name'] as String? ?? '';
      if (_knownTools.contains(name)) {
        calls.add(ToolCall(
          name: name,
          arguments: (json['arguments'] as Map<String, dynamic>?) ?? {},
        ));
      }
    } catch (e) {
      AppLogger.debug('[ToolExecutor] Failed to parse tool call: $e');
    }
  }

  /// Returns true if the text likely contains a tool call.
  static bool hasToolCalls(String text) {
    if (text.contains('<tool_call>')) return true;
    // Check for JSON with a known tool name
    for (final tool in _knownTools) {
      if (text.contains('"name"') && text.contains('"$tool"')) return true;
    }
    return false;
  }

  /// Executes a single tool call and returns the result.
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.name) {
        case 'list_directory':
          return await _listDirectory(call.arguments);
        case 'search_files':
          return await _searchFiles(call.arguments);
        case 'read_file':
          return await _readFile(call.arguments);
        case 'write_file':
          return await _writeFile(call.arguments);
        case 'get_file_info':
          return await _getFileInfo(call.arguments);
        case 'run_command':
          return await _runCommand(call.arguments);
        case 'search_by_tag':
          return await _searchByTag(call.arguments);
        case 'get_file_tags':
          return await _getFileTags(call.arguments);
        case 'list_all_tags':
          return await _listAllTags(call.arguments);
        case 'search_content':
          return await _searchContent(call.arguments);
        case 'list_video_libraries':
          return await _listVideoLibraries(call.arguments);
        case 'get_video_library_files':
          return await _getVideoLibraryFiles(call.arguments);
        case 'list_albums':
          return await _listAlbums(call.arguments);
        case 'get_album_files':
          return await _getAlbumFiles(call.arguments);
        case 'delete_file':
          return await _deleteFile(call.arguments);
        default:
          return ToolResult(
            toolName: call.name,
            output: 'Unknown tool: ${call.name}',
            success: false,
          );
      }
    } catch (e) {
      return ToolResult(
        toolName: call.name,
        output: 'Error: $e',
        success: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Tool implementations
  // ---------------------------------------------------------------------------

  Future<ToolResult> _listDirectory(Map<String, dynamic> args) async {
    final path = args['path'] as String? ?? '';
    final recursive = args['recursive'] as bool? ?? false;
    final pattern = args['pattern'] as String?;

    if (path.isEmpty) {
      if (Platform.isWindows) {
        try {
          final result = await Process.run(
            'cmd',
            [
              '/c',
              'wmic',
              'logicaldisk',
              'get',
              'name,size,freespace',
              '/format:csv'
            ],
          ).timeout(_timeout);
          return ToolResult(
            toolName: 'list_directory',
            output: _truncate('Available drives:\n${result.stdout}'),
          );
        } catch (_) {
          // Fallback: list drive letters
          final drives = <String>[];
          for (int i = 65; i <= 90; i++) {
            final letter = '${String.fromCharCode(i)}:\\';
            if (Directory(letter).existsSync()) drives.add(letter);
          }
          return ToolResult(
            toolName: 'list_directory',
            output: 'Available drives: ${drives.join(', ')}',
          );
        }
      }
      return const ToolResult(toolName: 'list_directory', output: 'Root: /');
    }

    final dir = Directory(path);
    if (!await dir.exists()) {
      return ToolResult(
        toolName: 'list_directory',
        output: 'Directory not found: $path',
        success: false,
      );
    }

    final buffer = StringBuffer();
    int count = 0;
    const limit = 200;

    try {
      await for (final entity in dir
          .list(
            recursive: recursive,
            followLinks: false,
          )
          .handleError((_) {})
          .take(limit * 2)) {
        if (count >= limit) {
          buffer.writeln('... (truncated, $limit+ entries)');
          break;
        }

        final name = entity.path.replaceFirst(path, '').replaceAll('\\', '/');
        if (name.isEmpty) continue;

        if (pattern != null &&
            !name.toLowerCase().contains(pattern.toLowerCase())) {
          continue;
        }

        try {
          final stat = await entity.stat();
          final isDir = entity is Directory;
          final sizeStr = isDir ? '<DIR>' : _formatSize(stat.size);
          final dateStr = stat.modified.toIso8601String().substring(0, 10);
          buffer.writeln('$dateStr  $sizeStr  $name');
        } catch (_) {
          buffer.writeln('            ?  $name');
        }
        count++;
      }
    } on TimeoutException {
      buffer.writeln('... (timed out after scanning $count entries)');
    } catch (e) {
      buffer.writeln('Error: $e');
    }

    return ToolResult(
      toolName: 'list_directory',
      output: _truncate('Directory: $path ($count entries)\n$buffer'),
    );
  }

  Future<ToolResult> _searchFiles(Map<String, dynamic> args) async {
    final query = args['query'] as String? ?? '';
    final path = args['path'] as String? ?? '';
    final ext = args['extension'] as String?;

    if (query.isEmpty && ext == null) {
      return const ToolResult(
        toolName: 'search_files',
        output: 'Error: "query" or "extension" argument required',
        success: false,
      );
    }

    // Use Dart directory listing instead of Process.run to avoid encoding issues
    final searchRoot = path.isNotEmpty
        ? path
        : (Platform.isWindows
            ? 'C:\\Users'
            : Platform.environment['HOME'] ?? '/');

    final dir = Directory(searchRoot);
    if (!await dir.exists()) {
      return ToolResult(
        toolName: 'search_files',
        output: 'Directory not found: $searchRoot',
        success: false,
      );
    }

    final queryLower = query.toLowerCase();
    final extLower = ext?.toLowerCase();
    final results = <String>[];
    const maxResults = 100;

    try {
      await for (final entity in dir
          .list(recursive: true, followLinks: false)
          .handleError((_) {})
          .timeout(_timeout, onTimeout: (sink) => sink.close())) {
        if (results.length >= maxResults) break;
        if (entity is! File) continue;

        final fileName =
            entity.path.split(Platform.pathSeparator).last.toLowerCase();

        bool matches = false;
        if (queryLower.isNotEmpty && fileName.contains(queryLower)) {
          matches = true;
        }
        if (extLower != null && fileName.endsWith(extLower)) {
          matches = true;
        }

        if (matches) {
          results.add(entity.path);
        }
      }
    } catch (_) {
      // Timeout or permission error — return what we have
    }

    return ToolResult(
      toolName: 'search_files',
      output: _truncate(
        'Search for "${query.isNotEmpty ? query : ext}" in $searchRoot:\n'
        'Found ${results.length} file(s)${results.length >= maxResults ? " (limit reached)" : ""}\n'
        '${results.join('\n')}',
      ),
    );
  }

  Future<ToolResult> _readFile(Map<String, dynamic> args) async {
    final path = args['path'] as String? ?? '';
    final maxLines = args['max_lines'] as int? ?? 50;

    if (path.isEmpty) {
      return const ToolResult(
        toolName: 'read_file',
        output: 'Error: "path" argument required',
        success: false,
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      return ToolResult(
        toolName: 'read_file',
        output: 'File not found: $path',
        success: false,
      );
    }

    try {
      final stat = await file.stat();
      if (stat.size > 1024 * 1024) {
        return ToolResult(
          toolName: 'read_file',
          output: 'File too large (${_formatSize(stat.size)}). Max 1MB.',
          success: false,
        );
      }

      String content;
      try {
        content = await file.readAsString(encoding: utf8);
      } catch (_) {
        try {
          content = await file.readAsString(encoding: latin1);
        } catch (_) {
          return const ToolResult(
            toolName: 'read_file',
            output: 'Cannot read file: binary or unsupported encoding',
            success: false,
          );
        }
      }

      final lines = content.split('\n');
      final preview = lines.take(maxLines).join('\n');
      final truncated = lines.length > maxLines;

      return ToolResult(
        toolName: 'read_file',
        output: _truncate(
          'File: $path (${_formatSize(stat.size)}, ${lines.length} lines)\n'
          '---\n$preview'
          '${truncated ? '\n--- (showing $maxLines of ${lines.length} lines)' : ''}',
        ),
      );
    } catch (e) {
      return ToolResult(
        toolName: 'read_file',
        output: 'Error reading file: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _writeFile(Map<String, dynamic> args) async {
    final path = args['path'] as String? ?? '';
    final content = args['content'] as String? ?? '';
    final append = args['append'] as bool? ?? false;

    if (path.isEmpty) {
      return const ToolResult(
        toolName: 'write_file',
        output: 'Error: "path" argument required',
        success: false,
      );
    }

    try {
      final file = File(path);
      // Ensure parent directory exists
      await file.parent.create(recursive: true);
      if (append) {
        await file.writeAsString(content, mode: FileMode.append);
      } else {
        await file.writeAsString(content);
      }
      final stat = await file.stat();
      return ToolResult(
        toolName: 'write_file',
        output:
            'Successfully ${append ? 'appended' : 'wrote'} ${content.length} chars to $path (${_formatSize(stat.size)} total)',
      );
    } catch (e) {
      return ToolResult(
        toolName: 'write_file',
        output: 'Error writing file: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _getFileInfo(Map<String, dynamic> args) async {
    final path = args['path'] as String? ?? '';

    if (path.isEmpty) {
      return const ToolResult(
        toolName: 'get_file_info',
        output: 'Error: "path" argument required',
        success: false,
      );
    }

    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.notFound) {
        return ToolResult(
          toolName: 'get_file_info',
          output: 'Not found: $path',
          success: false,
        );
      }

      final stat = FileStat.statSync(path);
      final buffer = StringBuffer();
      buffer.writeln('Path: $path');
      buffer.writeln(
          'Type: ${type == FileSystemEntityType.directory ? "Directory" : "File"}');
      buffer.writeln('Size: ${_formatSize(stat.size)}');
      buffer.writeln('Modified: ${stat.modified}');
      buffer.writeln('Accessed: ${stat.accessed}');

      return ToolResult(toolName: 'get_file_info', output: buffer.toString());
    } catch (e) {
      return ToolResult(
        toolName: 'get_file_info',
        output: 'Error: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _runCommand(Map<String, dynamic> args) async {
    final command = args['command'] as String? ?? '';
    final workingDir = args['working_directory'] as String?;

    if (command.isEmpty) {
      return const ToolResult(
        toolName: 'run_command',
        output: 'Error: "command" argument required',
        success: false,
      );
    }

    if (_blockedPatterns.hasMatch(command)) {
      return const ToolResult(
        toolName: 'run_command',
        output: 'Blocked: This command is not allowed for safety reasons.',
        success: false,
      );
    }

    Process? process;
    try {
      String executable;
      List<String> execArgs;

      if (Platform.isWindows) {
        // Use chcp 65001 to force UTF-8 output
        executable = 'cmd';
        execArgs = ['/c', 'chcp 65001 >nul & $command'];
      } else {
        executable = 'sh';
        execArgs = ['-c', command];
      }

      process = await Process.start(
        executable,
        execArgs,
        workingDirectory: workingDir,
      );

      // Read stdout/stderr with timeout
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCodeFuture = process.exitCode;

      final results = await Future.wait([
        stdoutFuture,
        stderrFuture,
        exitCodeFuture,
      ]).timeout(_timeout);

      final stdout = (results[0] as String).trim();
      final stderr = (results[1] as String).trim();
      final exitCode = results[2] as int;

      final buffer = StringBuffer();
      buffer.writeln('Exit code: $exitCode');
      if (stdout.isNotEmpty) buffer.writeln('Output:\n$stdout');
      if (stderr.isNotEmpty) buffer.writeln('Stderr:\n$stderr');

      return ToolResult(
        toolName: 'run_command',
        output: _truncate(buffer.toString()),
        success: exitCode == 0,
      );
    } on TimeoutException {
      process?.kill();
      return const ToolResult(
        toolName: 'run_command',
        output: 'Error: Command timed out after 15 seconds',
        success: false,
      );
    } catch (e) {
      process?.kill();
      return ToolResult(
        toolName: 'run_command',
        output: 'Error: $e',
        success: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CB File Hub tag & content tools
  // ---------------------------------------------------------------------------

  Future<ToolResult> _searchByTag(Map<String, dynamic> args) async {
    final tag = args['tag'] as String? ?? '';
    final path = args['path'] as String?;
    final global = args['global'] as bool? ?? true;

    if (tag.isEmpty) {
      return const ToolResult(
        toolName: 'search_by_tag',
        output: 'Error: "tag" argument required',
        success: false,
      );
    }

    try {
      await TagManager.initialize();

      List<FileSystemEntity> files;
      if (global || path == null || path.isEmpty) {
        files = await TagManager.findFilesByTagGlobally(tag);
      } else {
        files = await TagManager.findFilesByTag(path, tag);
      }

      if (files.isEmpty) {
        return ToolResult(
          toolName: 'search_by_tag',
          output: 'No files found with tag "$tag"',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Files with tag "$tag": ${files.length} found');
      for (final f in files.take(100)) {
        final stat = await f.stat();
        buffer.writeln('  ${f.path}  (${_formatSize(stat.size)})');
      }
      if (files.length > 100) {
        buffer.writeln('  ... and ${files.length - 100} more');
      }

      return ToolResult(
        toolName: 'search_by_tag',
        output: _truncate(buffer.toString()),
      );
    } catch (e) {
      return ToolResult(
        toolName: 'search_by_tag',
        output: 'Error: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _getFileTags(Map<String, dynamic> args) async {
    final path = args['path'] as String? ?? '';

    if (path.isEmpty) {
      return const ToolResult(
        toolName: 'get_file_tags',
        output: 'Error: "path" argument required',
        success: false,
      );
    }

    try {
      await TagManager.initialize();
      final tags = await TagManager.getTags(path);

      if (tags.isEmpty) {
        return ToolResult(
          toolName: 'get_file_tags',
          output: 'File "$path" has no tags',
        );
      }

      return ToolResult(
        toolName: 'get_file_tags',
        output: 'Tags for "$path": ${tags.join(", ")}',
      );
    } catch (e) {
      return ToolResult(
        toolName: 'get_file_tags',
        output: 'Error: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _listAllTags(Map<String, dynamic> args) async {
    try {
      await TagManager.initialize();
      final tags = await TagManager.getAllUniqueTags('');

      if (tags.isEmpty) {
        return const ToolResult(
          toolName: 'list_all_tags',
          output: 'No tags found in the system',
        );
      }

      final sorted = tags.toList()..sort();
      final buffer = StringBuffer();
      buffer.writeln('All tags (${sorted.length}):');
      for (final tag in sorted) {
        buffer.writeln('  #$tag');
      }

      return ToolResult(
        toolName: 'list_all_tags',
        output: _truncate(buffer.toString()),
      );
    } catch (e) {
      return ToolResult(
        toolName: 'list_all_tags',
        output: 'Error: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _searchContent(Map<String, dynamic> args) async {
    final query = args['query'] as String? ?? '';
    final path = args['path'] as String? ?? '';
    final ext = args['extension'] as String?;
    final caseSensitive = args['case_sensitive'] as bool? ?? false;

    if (query.isEmpty) {
      return const ToolResult(
        toolName: 'search_content',
        output: 'Error: "query" argument required',
        success: false,
      );
    }

    final searchRoot = path.isNotEmpty
        ? path
        : (Platform.isWindows
            ? (Platform.environment['USERPROFILE'] ?? 'C:\\Users')
            : Platform.environment['HOME'] ?? '/');

    final dir = Directory(searchRoot);
    if (!await dir.exists()) {
      return ToolResult(
        toolName: 'search_content',
        output: 'Directory not found: $searchRoot',
        success: false,
      );
    }

    final textExts = ext != null
        ? {ext.toLowerCase()}
        : const {
            '.txt',
            '.md',
            '.json',
            '.xml',
            '.yaml',
            '.yml',
            '.csv',
            '.log',
            '.ini',
            '.cfg',
            '.conf',
            '.html',
            '.css',
            '.js',
            '.ts',
            '.dart',
            '.py',
            '.java',
            '.c',
            '.cpp',
            '.h',
            '.go',
            '.rs',
            '.rb',
            '.php',
            '.sh',
            '.bat',
            '.sql',
            '.toml',
          };

    final queryLower = caseSensitive ? query : query.toLowerCase();
    final results = <String>[];
    const maxResults = 50;

    try {
      await for (final entity in dir
          .list(recursive: true, followLinks: false)
          .handleError((_) {})
          .timeout(_timeout, onTimeout: (sink) => sink.close())) {
        if (results.length >= maxResults) break;
        if (entity is! File) continue;

        final fileName = entity.path.split(Platform.pathSeparator).last;
        final fileExt = fileName.contains('.')
            ? '.${fileName.split('.').last}'.toLowerCase()
            : '';
        if (!textExts.contains(fileExt)) continue;

        try {
          final stat = await entity.stat();
          if (stat.size > 512 * 1024) continue; // skip files > 512KB

          final content = await entity.readAsString(encoding: utf8);
          final searchIn = caseSensitive ? content : content.toLowerCase();

          if (searchIn.contains(queryLower)) {
            // Find the matching line for context
            final lines = content.split('\n');
            String? matchLine;
            int? lineNum;
            for (int i = 0; i < lines.length; i++) {
              final lineLower =
                  caseSensitive ? lines[i] : lines[i].toLowerCase();
              if (lineLower.contains(queryLower)) {
                lineNum = i + 1;
                matchLine = lines[i].trim();
                if (matchLine.length > 120) {
                  matchLine = '${matchLine.substring(0, 120)}...';
                }
                break;
              }
            }
            results.add(
              '${entity.path}:$lineNum: $matchLine',
            );
          }
        } catch (_) {
          // Skip unreadable files
        }
      }
    } catch (_) {
      // Timeout — return what we have
    }

    if (results.isEmpty) {
      return ToolResult(
        toolName: 'search_content',
        output: 'No files containing "$query" found in $searchRoot',
      );
    }

    return ToolResult(
      toolName: 'search_content',
      output: _truncate(
        'Content search for "$query" in $searchRoot:\n'
        'Found in ${results.length} file(s)${results.length >= maxResults ? " (limit reached)" : ""}\n\n'
        '${results.join('\n')}',
      ),
    );
  }

  Future<ToolResult> _deleteFile(Map<String, dynamic> args) async {
    AppLogger.info('[ToolExecutor] delete_file called with args: $args');
    // Support single path or array of paths
    final List<String> paths;
    final pathArg = args['path'];
    final pathsArg = args['paths'];
    if (pathsArg is List) {
      paths = pathsArg.map((e) => e.toString()).where((p) => p.isNotEmpty).toList();
    } else if (pathArg is String && pathArg.isNotEmpty) {
      paths = [pathArg];
    } else {
      return const ToolResult(
        toolName: 'delete_file',
        output: 'Error: "path" (string) or "paths" (array) argument required',
        success: false,
      );
    }

    final trashManager = TrashManager();
    final succeeded = <String>[];
    final failed = <String, String>{};

    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);

      if (type == FileSystemEntityType.notFound) {
        failed[path] = 'Not found';
        continue;
      }

      // Move to recycle bin (not permanent delete)
      final ok = await trashManager.moveToTrash(path);
      if (ok) {
        succeeded.add(path);
      } else {
        failed[path] = 'Failed to move to recycle bin';
      }
    }

    // Build output listing results
    final buffer = StringBuffer();
    if (succeeded.isNotEmpty) {
      buffer.writeln('Moved to recycle bin (${succeeded.length} item(s)):');
      for (final p in succeeded) {
        buffer.writeln('  ✓ $p');
      }
    }
    if (failed.isNotEmpty) {
      if (succeeded.isNotEmpty) buffer.writeln();
      buffer.writeln('Failed (${failed.length} item(s)):');
      for (final entry in failed.entries) {
        buffer.writeln('  ✗ ${entry.key}: ${entry.value}');
      }
    }

    return ToolResult(
      toolName: 'delete_file',
      output: buffer.toString().trim(),
      success: failed.isEmpty,
    );
  }

  // ---------------------------------------------------------------------------
  // Video Library and Album Tools
  // ---------------------------------------------------------------------------

  Future<ToolResult> _listVideoLibraries(Map<String, dynamic> args) async {
    try {
      final service = VideoLibraryService();
      final libraries = await service.getAllLibraries();

      if (libraries.isEmpty) {
        return const ToolResult(
          toolName: 'list_video_libraries',
          output: 'No video libraries found.',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Found ${libraries.length} video library(ies):');
      buffer.writeln();

      for (final library in libraries) {
        buffer.writeln('ID: ${library.id}');
        buffer.writeln('Name: ${library.name}');
        if (library.description != null && library.description!.isNotEmpty) {
          buffer.writeln('Description: ${library.description}');
        }
        if (library.coverImagePath != null) {
          buffer.writeln('Cover: ${library.coverImagePath}');
        }
        buffer.writeln('Created: ${library.createdAt}');
        buffer.writeln('Modified: ${library.modifiedAt}');
        buffer.writeln('---');
      }

      return ToolResult(
        toolName: 'list_video_libraries',
        output: _truncate(buffer.toString().trim()),
      );
    } catch (e) {
      return ToolResult(
        toolName: 'list_video_libraries',
        output: 'Error listing video libraries: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _getVideoLibraryFiles(Map<String, dynamic> args) async {
    try {
      final libraryId = args['library_id'] as int?;
      if (libraryId == null) {
        return const ToolResult(
          toolName: 'get_video_library_files',
          output: 'Error: library_id is required',
          success: false,
        );
      }

      final service = VideoLibraryService();
      final library = await service.getLibraryById(libraryId);
      if (library == null) {
        return ToolResult(
          toolName: 'get_video_library_files',
          output: 'Error: Video library with ID $libraryId not found',
          success: false,
        );
      }

      final files = await service.getLibraryFiles(libraryId);

      if (files.isEmpty) {
        return ToolResult(
          toolName: 'get_video_library_files',
          output: 'Video library "${library.name}" (ID: $libraryId) contains no files.',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Video library: ${library.name} (ID: $libraryId)');
      buffer.writeln('Found ${files.length} video file(s):');
      buffer.writeln();

      for (final filePath in files) {
        final file = File(filePath);
        if (file.existsSync()) {
          final stat = file.statSync();
          buffer.writeln('$filePath  (${_formatSize(stat.size)})');
        } else {
          buffer.writeln('$filePath  (file not found)');
        }
      }

      return ToolResult(
        toolName: 'get_video_library_files',
        output: _truncate(buffer.toString().trim()),
      );
    } catch (e) {
      return ToolResult(
        toolName: 'get_video_library_files',
        output: 'Error getting video library files: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _listAlbums(Map<String, dynamic> args) async {
    try {
      final service = AlbumService.instance;
      final albums = await service.getAllAlbums();

      if (albums.isEmpty) {
        return const ToolResult(
          toolName: 'list_albums',
          output: 'No albums found.',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Found ${albums.length} album(s):');
      buffer.writeln();

      for (final album in albums) {
        buffer.writeln('ID: ${album.id}');
        buffer.writeln('Name: ${album.name}');
        if (album.description != null && album.description!.isNotEmpty) {
          buffer.writeln('Description: ${album.description}');
        }
        if (album.coverImagePath != null) {
          buffer.writeln('Cover: ${album.coverImagePath}');
        }
        buffer.writeln('Created: ${album.createdAt}');
        buffer.writeln('Modified: ${album.modifiedAt}');
        buffer.writeln('---');
      }

      return ToolResult(
        toolName: 'list_albums',
        output: _truncate(buffer.toString().trim()),
      );
    } catch (e) {
      return ToolResult(
        toolName: 'list_albums',
        output: 'Error listing albums: $e',
        success: false,
      );
    }
  }

  Future<ToolResult> _getAlbumFiles(Map<String, dynamic> args) async {
    try {
      final albumId = args['album_id'] as int?;
      if (albumId == null) {
        return const ToolResult(
          toolName: 'get_album_files',
          output: 'Error: album_id is required',
          success: false,
        );
      }

      final service = AlbumService.instance;
      final album = await service.getAlbumById(albumId);
      if (album == null) {
        return ToolResult(
          toolName: 'get_album_files',
          output: 'Error: Album with ID $albumId not found',
          success: false,
        );
      }

      final albumFiles = await service.getAlbumFiles(albumId);

      if (albumFiles.isEmpty) {
        return ToolResult(
          toolName: 'get_album_files',
          output: 'Album "${album.name}" (ID: $albumId) contains no files.',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Album: ${album.name} (ID: $albumId)');
      buffer.writeln('Found ${albumFiles.length} file(s):');
      buffer.writeln();

      for (final albumFile in albumFiles) {
        final file = File(albumFile.filePath);
        if (file.existsSync()) {
          final stat = file.statSync();
          buffer.write('${albumFile.filePath}  (${_formatSize(stat.size)})');
          if (albumFile.caption != null && albumFile.caption!.isNotEmpty) {
            buffer.write(' - ${albumFile.caption}');
          }
          buffer.writeln();
        } else {
          buffer.write('${albumFile.filePath}  (file not found)');
          if (albumFile.caption != null && albumFile.caption!.isNotEmpty) {
            buffer.write(' - ${albumFile.caption}');
          }
          buffer.writeln();
        }
      }

      return ToolResult(
        toolName: 'get_album_files',
        output: _truncate(buffer.toString().trim()),
      );
    } catch (e) {
      return ToolResult(
        toolName: 'get_album_files',
        output: 'Error getting album files: $e',
        success: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _truncate(String text) {
    if (text.length <= _maxOutputLength) return text;
    return '${text.substring(0, _maxOutputLength)}\n... (truncated)';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Tool definitions for the system prompt.
  static String get toolDefinitions => '''
=== CB FILE HUB KNOWLEDGE ===

You are the AI assistant for **CB File Hub**, a cross-platform file manager app.
CB File Hub has a powerful **tag system** that lets users tag files with custom labels (like #vacation, #work, #important). Tags are stored in a SQLite database and work across all drives.

Key concepts:
- **Tags**: Users can add multiple tags to any file. Tags are case-insensitive. Searching by tag is instant (database-indexed).
- **Tag search**: Users use #tag syntax in the search bar. Multiple tags can be combined (#nature #vacation = files with BOTH tags).
- **File browsing**: Tab-based file browser with folder navigation, drive switching, and network shares (SMB/FTP).
- **Media support**: Built-in video player, image gallery, streaming server.

=== AVAILABLE TOOLS ===

To use a tool, respond with a <tool_call> block:
<tool_call>
{"name": "tool_name", "arguments": {"arg1": "value1"}}
</tool_call>

**File System Tools:**

1. **list_directory** — List files and folders
   {"path": "C:\\\\Users", "recursive": false, "pattern": "optional_filter"}
   Empty path = list all drives. Use pattern to filter by name.

2. **search_files** — Search files by name or extension
   {"query": "photo", "path": "C:\\\\Users\\\\Pictures", "extension": ".jpg"}
   Searches recursively (15s timeout). Use specific paths, NOT entire drives.

3. **read_file** — Read text file content only
   {"path": "C:\\\\file.txt", "max_lines": 50}
   IMPORTANT: Only use on text-based files (txt, md, json, dart, py, js, ts, yaml, html, css, etc.).
   - Text files dropped by the user have their content PRE-LOADED in the message. Do NOT call read_file on them again.
   - NEVER call read_file on image files (jpg, png, gif, webp), video files (mp4, mkv), audio files (mp3, wav), PDFs, or archives (zip, rar, 7z) — it will fail.
   - For non-text files: use **get_file_info** instead.

4. **write_file** — Write or append text to a file — REQUIRES USER APPROVAL
   {"path": "C:\\\\file.txt", "content": "text here", "append": false}
   append=true adds to the end of the file. Creates the file (and parent directories) if it doesn't exist.

5. **get_file_info** — Get file metadata
   {"path": "C:\\\\file.txt"}

6. **delete_file** — Move file(s) to recycle bin — REQUIRES USER APPROVAL
   Single: {"path": "C:\\\\file.txt"}
   Multiple: {"paths": ["C:\\\\a.txt", "C:\\\\b.txt"]}
   Files are moved to the system recycle bin, NOT permanently deleted. User can restore them later.
   Returns a list of all items successfully moved and any that failed.

7. **run_command** — Execute a shell command (15s timeout) — REQUIRES USER APPROVAL
   Arguments: {"command": "dir /s /b C:\\\\Users\\\\*.pdf", "working_directory": "C:\\\\Users"}
   Destructive commands are blocked. USER MUST APPROVE before it runs.

**CB File Hub Tag Tools:**

8. **search_by_tag** — Find files tagged with a specific tag
   {"tag": "vacation", "global": true, "path": "C:\\\\Photos"}
   global=true searches all files. global=false + path searches within that directory only.
   This is the BEST way to find files that users have organized with tags.

9. **get_file_tags** — Get all tags of a file
   {"path": "C:\\\\Photos\\\\beach.jpg"}

10. **list_all_tags** — List all tags in the system
   {} (no arguments needed)
   Use this FIRST when the user asks about tags or tagged files to see what tags exist.

**Content Search Tool:**

11. **search_content** — Search inside text files for specific content (grep-like)
   {"query": "TODO", "path": "C:\\\\Projects", "extension": ".dart", "case_sensitive": false}
   Searches text files recursively for content matches. Shows matching line with context.

**Video Library and Album Tools:**

12. **list_video_libraries** — List all video libraries in CB File Hub
   {} (no arguments needed)
   Returns all video libraries with their IDs, names, descriptions, and metadata.
   Use this when users ask about video libraries, video collections, or want to see what video libraries exist.

13. **get_video_library_files** — Get all video files in a specific video library
   {"library_id": 1}
   Returns all video file paths in the specified video library with file sizes.
   Use this to search within a specific video library or list its contents.
   IMPORTANT: You must use **list_video_libraries** first to get the library_id.

14. **list_albums** — List all albums in CB File Hub
   {} (no arguments needed)
   Returns all albums with their IDs, names, descriptions, and metadata.
   Use this when users ask about albums, photo collections, or want to see what albums exist.

15. **get_album_files** — Get all files in a specific album
   {"album_id": 5}
   Returns all file paths in the specified album with file sizes and captions.
   Use this to search within a specific album or list its contents.
   IMPORTANT: You must use **list_albums** first to get the album_id.

=== STRATEGY ===

- For "find files with tag X": use **list_all_tags** first to check if the tag exists, then **search_by_tag**.
- For "find files named X": use **search_files** with a specific directory.
- For "find files containing X": use **search_content**.
- For "find videos in library X": use **list_video_libraries** first to get the library ID, then **get_video_library_files**.
- For "find files in album X": use **list_albums** first to get the album ID, then **get_album_files**.
- For "what video libraries exist": use **list_video_libraries**.
- For "what albums exist": use **list_albums**.
- For browsing: use **list_directory** → then narrow down.
- Referenced files (📎) are pre-loaded — their content is included in the message. Do NOT call read_file on them again.
- NEVER call read_file on images, videos, audio, PDFs, or archives. Use get_file_info for metadata instead.
- For creating or editing files: use **write_file** (requires user approval).
- For deleting files: use **delete_file** (requires user approval). Files go to recycle bin, not permanent deletion.
- When delete completes, ALWAYS list the files that were deleted in your response so the user knows what happened.
- Always search in specific directories (user home, known paths), NOT entire drives.
- You can call multiple tools in sequence. After each result, decide to continue or give a final answer.
- When done, respond with normal text (NO tool_call blocks).
''';
}

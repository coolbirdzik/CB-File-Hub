import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../helpers/files/trash_manager.dart';
import '../../utils/app_logger.dart';
import '../album_service.dart';
import '../disk_cleaner/cleaner_categories.dart';
import '../disk_cleaner/cleaner_models.dart';
import '../disk_cleaner/disk_cleaner_service.dart';
import '../disk_cleaner/disk_tree_node.dart';
import 'cleaner_scan_registry.dart';
import 'assistant_response_text.dart';
import 'agent_tool_catalog.dart';
import 'agent_file_tools.dart';
import 'agent_tag_tools.dart';
import 'disk_cleaner_skill.dart';
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
  final String? ownerTabId;

  ToolExecutor({this.ownerTabId, AgentTagStore? tagStore})
    : _tagStoreOverride = tagStore;

  AgentTagStore? _tagStoreOverride;
  AgentTagStore get _tagStore => _tagStoreOverride ??= AgentTagStore();
  AgentFileTools? _fileToolsCache;
  AgentFileTools get _fileTools => _fileToolsCache ??= AgentFileTools();
  String _workingDirectory = '';
  String _browsingPath = '';
  bool Function() _isCancelled = () => false;

  void beginTurn({
    required String currentPath,
    required bool Function() isCancelled,
  }) {
    _browsingPath = currentPath;
    _workingDirectory =
        currentPath.isNotEmpty &&
            !currentPath.startsWith('#') &&
            !currentPath.contains('://')
        ? currentPath
        : Platform.environment['USERPROFILE'] ??
              Platform.environment['HOME'] ??
              '';
    _isCancelled = isCancelled;
  }

  String? validateCall(ToolCall call) =>
      AgentToolCatalog.validate(call.name, call.arguments);

  ToolCall prepareCall(ToolCall call) {
    final normalized = normalizeCall(call);
    final args = Map<String, dynamic>.from(normalized.arguments);
    // Freeze exact resolved targets before approval. Empty list_directory path
    // explicitly means drive discovery; omitted path means the current folder.
    for (final key in ['path', 'source', 'destination', 'working_directory']) {
      if (args[key] is String &&
          !(call.name == 'list_directory' && args[key] == '')) {
        args[key] = AgentFileTools.resolvePath(
          args[key] as String,
          _workingDirectory,
        );
      }
    }
    if (args['paths'] is List) {
      args['paths'] = (args['paths'] as List)
          .map(
            (path) =>
                AgentFileTools.resolvePath(path as String, _workingDirectory),
          )
          .toList();
    }
    if ([
          'list_directory',
          'search_files',
          'search_content',
          'search_by_tag',
        ].contains(call.name) &&
        !args.containsKey('path')) {
      args['path'] = _workingDirectory;
    }
    if (call.name == 'run_command' && !args.containsKey('working_directory')) {
      args['working_directory'] = _workingDirectory;
    }
    return ToolCall(name: normalized.name, arguments: args);
  }

  static const int _maxOutputLength = 8000;
  static const int maxToolCalls = 10;
  static const Duration _timeout = Duration(seconds: 15);

  static final _blockedPatterns = RegExp(
    r'(rm\s+-rf|del\s+/[sfq]|format\s|mkfs|dd\s|shutdown|reboot|'
    r':(){ :|taskkill|net\s+stop|reg\s+delete)',
    caseSensitive: false,
  );

  /// Tool names we recognise.
  static Set<String> get _knownTools => AgentToolCatalog.names;

  static const _toolAliases = {
    'get_current_clean_cleaner_scan': 'get_current_cleaner_scan',
  };

  /// Tools that must always go through user approval before executing.
  static Set<String> get _dangerousTools => AgentToolCatalog.approvalTools;

  /// Public getter for the BLoC to check.
  static Set<String> get dangerousTools => _dangerousTools;

  /// Parses tool calls from the AI's response text.
  ///
  /// Supports multiple formats:
  /// 1. `<tool_call>{"name":"...","arguments":{...}}</tool_call>`
  /// 2. ```json {"name":"...","arguments":{...}} ```
  /// 3. Bare JSON object with "name" and "arguments" keys
  /// 4. Gemma-style `<|tool_call>call:tool_call{name: "..."}<tool_call|>`
  static List<ToolCall> parseToolCalls(String text) {
    text = stripAssistantReasoning(text);
    final calls = <ToolCall>[];

    // Format 1: <tool_call> ... </tool_call>
    final tagMatches = RegExp(
      r'<tool_call>\s*([\s\S]*?)\s*</tool_call>',
    ).allMatches(text);
    for (final match in tagMatches) {
      _tryParseCall(match.group(1), calls);
    }

    if (calls.isNotEmpty) return calls;

    // Format 1b: Gemma/LiteRT style:
    // <|tool_call>call:tool_call{name: "tool", "arg": true}<tool_call|>
    final gemmaMatches = RegExp(
      r'<\|tool_call>\s*call:tool_call\s*\{([\s\S]*?)\}\s*<tool_call\|>',
    ).allMatches(text);
    for (final match in gemmaMatches) {
      _tryParseGemmaCall(match.group(1), calls);
    }

    if (calls.isNotEmpty) return calls;

    // Format 1c: bare Gemma call without sentinel tokens.
    final bareGemmaMatches = RegExp(
      r'call:tool_call\s*\{([\s\S]*?)\}',
    ).allMatches(text);
    for (final match in bareGemmaMatches) {
      _tryParseGemmaCall(match.group(1), calls);
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

    // Balanced objects preserve nested arguments and braces inside quoted text.
    for (final object in _jsonObjects(text)) {
      _tryParseCall(object, calls);
    }

    return calls;
  }

  static Iterable<String> _jsonObjects(String text) sync* {
    var start = -1;
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (start < 0) {
        if (char == '{') {
          start = i;
          depth = 1;
        }
        continue;
      }
      if (escaped) {
        escaped = false;
        continue;
      }
      if (quoted && char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        quoted = !quoted;
        continue;
      }
      if (quoted) continue;
      if (char == '{') depth++;
      if (char == '}' && --depth == 0) {
        yield text.substring(start, i + 1);
        start = -1;
      }
    }
  }

  static void _tryParseCall(String? jsonStr, List<ToolCall> calls) {
    if (jsonStr == null) return;
    try {
      final json = jsonDecode(jsonStr.trim()) as Map<String, dynamic>;
      if (!json.containsKey('arguments')) return;
      final name = _canonicalToolName(json['name'] as String? ?? '');
      if (name.isNotEmpty) {
        calls.add(
          ToolCall(
            name: name,
            arguments: (json['arguments'] as Map<String, dynamic>?) ?? {},
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[ToolExecutor] Failed to parse tool call: $e');
    }
  }

  static void _tryParseGemmaCall(String? body, List<ToolCall> calls) {
    if (body == null) return;
    final nameMatch = RegExp(
      r'(?:"name"|name)\s*:\s*"([^"]+)"',
    ).firstMatch(body);
    final name = _canonicalToolName(nameMatch?.group(1) ?? '');
    if (name.isEmpty) return;

    final args = <String, dynamic>{};
    final fields = RegExp(
      r'(?:"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))\s*:\s*("[^"]*"|true|false|null|-?\d+(?:\.\d+)?)',
    ).allMatches(body);
    for (final field in fields) {
      final key = field.group(1) ?? field.group(2) ?? '';
      if (key.isEmpty || key == 'name') continue;
      args[key] = _parseScalarValue(field.group(3) ?? '');
    }

    calls.add(ToolCall(name: name, arguments: args));
  }

  static dynamic _parseScalarValue(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    if (trimmed == 'true') return true;
    if (trimmed == 'false') return false;
    if (trimmed == 'null') return null;
    return num.tryParse(trimmed) ?? trimmed;
  }

  static String _canonicalToolName(String name) {
    return _toolAliases[name] ?? name;
  }

  /// Returns true if the text likely contains a tool call.
  static bool hasToolCalls(String text) {
    text = stripAssistantReasoning(text);
    if (text.contains('[approval]') ||
        RegExp(
          '(?:^|\\n)\\s*(?:${AgentToolCatalog.names.map(RegExp.escape).join('|')})\\s*\\(',
        ).hasMatch(text)) {
      return true; // Invalid syntax: request repair, never execute as prose.
    }
    if (text.contains('<tool_call>')) return true;
    if (parseToolCalls(text).isNotEmpty) return true;
    if (text.contains('<|tool_call>') || text.contains('call:tool_call')) {
      return true;
    }
    // Check for JSON with a known tool name
    for (final tool in _knownTools) {
      if (text.contains('"name"') && text.contains('"$tool"')) return true;
    }
    return false;
  }

  /// Executes a single tool call and returns the result.
  Future<ToolResult> execute(ToolCall call) async {
    final cancelled = _isCancelled;
    try {
      final validation = validateCall(call);
      if (validation != null) {
        return ToolResult(
          toolName: call.name,
          output: jsonEncode({'ok': false, 'error': validation}),
          success: false,
        );
      }
      call = prepareCall(call);
      if (cancelled()) throw StateError('Operation stopped by user.');
      if (call.name == 'get_context') {
        return ToolResult(
          toolName: call.name,
          output: jsonEncode({
            'ok': true,
            'working_directory': _workingDirectory,
            'browsing_path': _browsingPath,
            'platform': Platform.operatingSystem,
          }),
        );
      }
      if (call.name == 'get_tool_guide') {
        final topic = call.arguments['topic'];
        final guide = switch (topic) {
          'files' =>
            'Browse/search in the current folder. Follow next_cursor with unchanged filters. Inspect sources and destinations before changes. For identical content, compare exact size_bytes, then file_checksum for candidates; report incomplete scans honestly. Use read_file start_line and next_start_line for text pages. Never infer duplicates from matching names alone.',
          'tags' =>
            'Tags are stored by CB File Hub, not the filesystem. Discover actual names with list_all_tags(query). Read get_file_tags(path); search_by_tag(tag,path,global:false) is scoped to a folder. global:true crosses drives. Follow next_cursor. update_file_tags(add/remove) preserves other tags and requires approval.',
          'media' =>
            'list_video_libraries({}) -> get_video_library_files({"library_id":actual_id}); list_albums({}) -> get_album_files({"album_id":actual_id}). Use only IDs returned by the listing tool. Read metadata, not binary media contents.',
          'cleaner' => DiskCleanerSkill.skillBlock,
          'app' =>
            'CB File Hub uses tabs and app tags. Virtual #home/#tags/#albums/#video/#ai-chat screens are not filesystem directories. Use get_context for the working folder. get_current_app_storage({}) inspects existing app storage analysis; get_current_cleaner_scan({}) reads an existing scan.',
          _ => throw ArgumentError(
            'Unknown topic. Choose files, tags, media, cleaner, app.',
          ),
        };
        return ToolResult(toolName: call.name, output: guide);
      }
      if (AgentFileTools.names.contains(call.name)) {
        List<String>? sourceTags;
        if (call.name == 'move_file' || call.name == 'copy_file') {
          sourceTags = await _tagStore.read(call.arguments['source'] as String);
        }
        final data = await _fileTools.execute(
          call.name,
          call.arguments,
          isCancelled: cancelled,
        );
        try {
          if (sourceTags != null && sourceTags.isNotEmpty) {
            final copiedTags = await _tagStore.write(
              call.arguments['destination'] as String,
              sourceTags,
            );
            if (!copiedTags) {
              data['warning'] =
                  'File operation succeeded, but tags could not be copied.';
            } else {
              if (call.name == 'move_file' &&
                  !await _tagStore.write(
                    call.arguments['source'] as String,
                    [],
                  )) {
                data['warning'] =
                    'File moved, but old tag metadata could not be cleared.';
              }
            }
          }
        } catch (error) {
          data['warning'] =
              'File operation succeeded; tag metadata update failed: $error';
        }
        return ToolResult(toolName: call.name, output: jsonEncode(data));
      }
      if (AgentTagTools.names.contains(call.name)) {
        final data = await AgentTagTools(
          _tagStore,
          _fileTools,
        ).execute(call.name, call.arguments, isCancelled: cancelled);
        return ToolResult(toolName: call.name, output: jsonEncode(data));
      }
      switch (call.name) {
        case 'run_command':
          return await _runCommand(call.arguments);
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
        // Disk Cleaner skill
        case 'list_disk_junk_categories':
          return await _listDiskJunkCategories(call.arguments);
        case 'get_drive_space':
          return await _getDriveSpace(call.arguments);
        case 'scan_disk_junk':
          return await _scanDiskJunk(call.arguments);
        case 'clean_disk_junk':
          return await _cleanDiskJunk(call.arguments);
        case 'get_pending_cleanup_review':
          return _getPendingCleanupReview(call.arguments);
        case 'get_current_cleaner_scan':
          return _getCurrentCleanerScan(call.arguments);
        case 'get_current_app_storage':
          return _getCurrentAppStorage(call.arguments);
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

  Future<ToolResult> _deleteFile(Map<String, dynamic> args) async {
    AppLogger.info('[ToolExecutor] delete_file called with args: $args');
    // Support single path or array of paths
    final List<String> paths;
    final pathArg = args['path'];
    final pathsArg = args['paths'];
    if (pathsArg is List) {
      paths = pathsArg
          .map((e) => e.toString())
          .where((p) => p.isNotEmpty)
          .toList();
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

    // Filter out paths that don't exist up front — SHFileOperationW would
    // skip them anyway, but reporting "Not found" here keeps the response
    // useful.
    final existingPaths = <String>[];
    for (final p in paths) {
      final type = FileSystemEntity.typeSync(p);
      if (type == FileSystemEntityType.notFound) {
        failed[p] = 'Not found';
      } else {
        existingPaths.add(p);
      }
    }

    if (existingPaths.isNotEmpty) {
      // Single batched native call — replaces the previous per-file loop
      // that spawned PowerShell on Windows.
      final ok = await trashManager.moveMultipleToTrashBatched(existingPaths);
      for (final p in existingPaths) {
        if (ok.contains(p)) {
          succeeded.add(p);
        } else {
          failed[p] = 'Failed to move to recycle bin';
        }
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
          output:
              'Video library "${library.name}" (ID: $libraryId) contains no files.',
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
  // Disk Cleaner skill tools
  // ---------------------------------------------------------------------------

  /// In-memory cache of scan results keyed by scan_id and isolated by tab.
  static final CleanerScanRegistry _scanRegistry = CleanerScanRegistry();

  ToolCall normalizeCall(ToolCall call) {
    if (call.name != 'scan_disk_junk' && call.name != 'clean_disk_junk') {
      return call;
    }

    final arguments = Map<String, dynamic>.from(call.arguments);
    final normalizedCategories = _normalizeCleanerCategories(
      arguments['categories'],
    );
    if (normalizedCategories != null) {
      arguments['categories'] = normalizedCategories;
    }

    if (call.name == 'clean_disk_junk') {
      final resolvedScanId = _scanRegistry.resolveId(
        arguments['scan_id'],
        ownerTabId: ownerTabId,
      );
      if (resolvedScanId != null) {
        arguments['scan_id'] = resolvedScanId;
      }
    }

    return ToolCall(name: call.name, arguments: arguments);
  }

  Future<ToolResult> _listDiskJunkCategories(Map<String, dynamic> args) async {
    if (!Platform.isWindows) {
      return const ToolResult(
        toolName: 'list_disk_junk_categories',
        output: 'Error: Disk Cleaner is only available on Windows.',
        success: false,
      );
    }

    final service = DiskCleanerService.instance;
    final categories = service.listCategories();
    final buffer = StringBuffer('Available junk categories on Windows:\n');
    for (final cat in categories) {
      final safetyStr = cat.safety.name;
      final defaultStr = cat.defaultEnabled ? 'default ON' : 'default OFF';
      final adminStr = cat.requiresAdmin ? ', needs admin' : '';
      buffer.writeln(
        '- ${cat.id} ($safetyStr, $defaultStr$adminStr): ${cat.description}',
      );
    }
    return ToolResult(
      toolName: 'list_disk_junk_categories',
      output: buffer.toString().trim(),
    );
  }

  Future<ToolResult> _getDriveSpace(Map<String, dynamic> args) async {
    if (!Platform.isWindows) {
      return const ToolResult(
        toolName: 'get_drive_space',
        output: 'Error: Only available on Windows.',
        success: false,
      );
    }

    final service = DiskCleanerService.instance;
    final drives = await service.getDriveSpace();
    if (drives.isEmpty) {
      return const ToolResult(
        toolName: 'get_drive_space',
        output: 'No fixed drives found.',
        success: false,
      );
    }

    final buffer = StringBuffer('Drive space (fixed drives):\n');
    for (final d in drives) {
      final label = d.label.isNotEmpty ? ' (${d.label})' : '';
      buffer.writeln(
        '- ${d.path}$label: ${_formatSize(d.usedBytes)} used / ${_formatSize(d.totalBytes)} total, ${_formatSize(d.freeBytes)} free',
      );
    }
    return ToolResult(
      toolName: 'get_drive_space',
      output: buffer.toString().trim(),
    );
  }

  Future<ToolResult> _scanDiskJunk(Map<String, dynamic> args) async {
    if (!Platform.isWindows) {
      return const ToolResult(
        toolName: 'scan_disk_junk',
        output: 'Error: Only available on Windows.',
        success: false,
      );
    }

    final service = DiskCleanerService.instance;
    if (service.isScanning) {
      return const ToolResult(
        toolName: 'scan_disk_junk',
        output:
            'Error: A scan is already in progress. Wait for it to finish or cancel it.',
        success: false,
      );
    }

    final normalizedArgs = normalizeCall(
      ToolCall(name: 'scan_disk_junk', arguments: args),
    ).arguments;

    // Parse arguments
    final drivesArg = normalizedArgs['drives'];
    final List<String> drives;
    if (drivesArg is List) {
      drives = drivesArg.map((e) => e.toString()).toList();
    } else {
      drives = const ['C:\\'];
    }

    final categoriesArg = normalizedArgs['categories'];
    final List<String> categories;
    if (categoriesArg is List) {
      categories = categoriesArg.map((e) => e.toString()).toList();
    } else {
      categories = const [];
    }

    try {
      service.emitAgentActivity(
        DiskCleanerAgentActivity(
          type: DiskCleanerAgentActivityType.scanStarted,
          ownerTabId: ownerTabId,
          message: 'CB Agent is scanning junk files...',
        ),
      );
      final report = await service.scanJunk(
        drivePaths: drives,
        categoryIds: categories,
        onProgress: (progress) {
          service.emitAgentActivity(
            DiskCleanerAgentActivity(
              type: DiskCleanerAgentActivityType.scanProgress,
              ownerTabId: ownerTabId,
              message: 'CB Agent is scanning junk files...',
              itemsFound: progress.itemsFound,
              bytesFound: progress.bytesFound,
              currentPath: progress.currentPath,
            ),
          );
        },
      );
      service.emitAgentActivity(
        DiskCleanerAgentActivity(
          type: DiskCleanerAgentActivityType.scanDone,
          ownerTabId: ownerTabId,
          message: 'CB Agent scan complete.',
          itemsFound: report.totalCount,
          bytesFound: report.totalBytes,
          report: report,
        ),
      );

      // Generate scan_id and cache the report
      final scanId =
          'sc_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      _scanRegistry.store(scanId, report, ownerTabId: ownerTabId);

      return ToolResult(
        toolName: 'scan_disk_junk',
        output: formatJunkScanReport(report, scanId),
      );
    } catch (e) {
      service.emitAgentActivity(
        DiskCleanerAgentActivity(
          type: DiskCleanerAgentActivityType.scanFailed,
          ownerTabId: ownerTabId,
          message: 'CB Agent scan failed: $e',
        ),
      );
      return ToolResult(
        toolName: 'scan_disk_junk',
        output: 'Error: $e',
        success: false,
      );
    }
  }

  /// Formats a junk scan as evidence for a recommendation, not as a cleanup
  /// instruction. Kept public so the output contract can be tested without
  /// touching the Windows filesystem.
  String formatJunkScanReport(ScanReport report, String scanId) {
    final buffer = StringBuffer();
    buffer.writeln('JUNK SCAN ANALYSIS');
    buffer.writeln('scan_id=$scanId');
    buffer.writeln('Drives: ${report.drivesScanned.join(', ')}');
    buffer.writeln(
      'Total rule-matched junk: ${report.totalCount} items, ${_formatSize(report.totalBytes)}',
    );

    final categories = report.itemsByCategory.entries.toList()
      ..sort((a, b) {
        final aBytes = a.value.fold<int>(
          0,
          (sum, item) => sum + item.sizeBytes,
        );
        final bBytes = b.value.fold<int>(
          0,
          (sum, item) => sum + item.sizeBytes,
        );
        return bBytes.compareTo(aBytes);
      });

    buffer.writeln();
    buffer.writeln('Categories ranked by reclaimable size:');
    if (categories.isEmpty) {
      buffer.writeln('  (none)');
    }
    for (final entry in categories) {
      final category = CleanerCategories.byId(entry.key);
      final items = entry.value.toList()
        ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      final bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
      final safety = category?.safety ?? CleanerSafety.careful;
      buffer.writeln(
        '- ${category?.displayName ?? entry.key} [id=${entry.key}, safety=${safety.name}]: '
        '${items.length} items, ${_formatSize(bytes)}. '
        '${category?.description ?? 'Unknown cleaner category.'}',
      );
      buffer.writeln('  recommendation: ${_categoryRecommendation(safety)}');
      for (final item in items.take(3)) {
        buffer.writeln(
          '  largest: ${item.path} [${item.isContainerOnly ? 'folder contents' : 'file/folder'}, '
          '${_formatSize(item.sizeBytes)}, owner=${_junkOwner(entry.key, item.path)}]',
        );
      }
      if (items.length > 3) {
        buffer.writeln('  ... ${items.length - 3} more in this category');
      }
    }

    if (report.warnings.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Coverage warnings:');
      for (final warning in report.warnings) {
        buffer.writeln('- $warning');
      }
    }

    buffer.writeln();
    buffer.writeln(
      'RESPONSE REQUIREMENT: Summarize the ranked findings in normal '
      'language. Include path, size, owner/category, CLEAN/REVIEW/KEEP, and '
      'reason. This scan is analysis-only. Do not call clean_disk_junk unless '
      'the user explicitly confirms cleanup after seeing the findings.',
    );
    return _truncate(buffer.toString().trim());
  }

  Future<ToolResult> _cleanDiskJunk(Map<String, dynamic> args) async {
    if (!Platform.isWindows) {
      return const ToolResult(
        toolName: 'clean_disk_junk',
        output: 'Error: Only available on Windows.',
        success: false,
      );
    }

    final normalizedCall = normalizeCall(
      ToolCall(name: 'clean_disk_junk', arguments: args),
    );
    final normalizedArgs = normalizedCall.arguments;
    final scanId = _scanRegistry.resolveId(
      normalizedArgs['scan_id'],
      ownerTabId: ownerTabId,
    );
    final cached = scanId == null ? null : _scanRegistry[scanId];
    if (cached == null) {
      final requestedScanId =
          normalizedArgs['scan_id']?.toString().trim() ?? '';
      final usedPlaceholder = CleanerScanRegistry.isPlaceholder(
        requestedScanId,
      );
      return ToolResult(
        toolName: 'clean_disk_junk',
        output: usedPlaceholder
            ? 'Error: No current junk scan is available. Run scan_disk_junk first.'
            : 'Error: scan_id not found, expired, or belongs to another tab. Run scan_disk_junk again.',
        success: false,
      );
    }

    // Filter by categories if specified
    final categoriesArg = normalizedArgs['categories'];
    final List<String>? filterCategories;
    if (categoriesArg is List && categoriesArg.isNotEmpty) {
      filterCategories = categoriesArg.map((e) => e.toString()).toList();
    } else {
      filterCategories = null;
    }

    final permanent = normalizedArgs['permanent'] as bool? ?? false;
    final maxItems = normalizedArgs['max_items'] as int? ?? 10000;

    // Collect items to clean
    var items = cached.report.allItems;
    if (filterCategories != null) {
      final cats = filterCategories;
      items = items.where((i) => cats.contains(i.categoryId)).toList();
    }
    if (items.length > maxItems) {
      items = items.sublist(0, maxItems);
    }

    if (items.isEmpty) {
      return const ToolResult(
        toolName: 'clean_disk_junk',
        output: 'No items to clean for the specified categories.',
      );
    }

    try {
      final service = DiskCleanerService.instance;
      final report = await service.cleanJunk(
        items: items,
        permanent: permanent,
      );

      final buffer = StringBuffer();
      buffer.writeln('Cleanup complete.');
      buffer.writeln(
        'Mode: ${report.wasPermanent ? "Permanent delete" : "Move to Recycle Bin"}',
      );
      buffer.writeln(
        'Freed: ${_formatSize(report.freedBytes)} across ${report.successCount} items',
      );
      buffer.writeln('Succeeded: ${report.successCount}');
      if (report.failureCount > 0) {
        buffer.writeln(
          'Failed: ${report.failureCount} (locked by other processes or permission denied)',
        );
        final examples = report.failed.entries.take(5);
        buffer.writeln('Examples of failures:');
        for (final e in examples) {
          buffer.writeln('  - ${e.key} (${e.value})');
        }
      }
      if (report.skippedInUse.isNotEmpty) {
        buffer.writeln(
          'Skipped (currently in use): ${report.skippedInUse.length}',
        );
      }
      if (report.skippedUnsafe.isNotEmpty) {
        buffer.writeln(
          'Skipped (unsafe paths): ${report.skippedUnsafe.length}',
        );
      }

      // Remove from cache after successful clean
      _scanRegistry.remove(scanId!);

      return ToolResult(
        toolName: 'clean_disk_junk',
        output: _truncate(buffer.toString().trim()),
      );
    } catch (e) {
      return ToolResult(
        toolName: 'clean_disk_junk',
        output: 'Error: $e',
        success: false,
      );
    }
  }

  ToolResult _getPendingCleanupReview(Map<String, dynamic> args) {
    final service = DiskCleanerService.instance;
    final items = service.pendingCleanupItems;
    if (items == null || items.isEmpty) {
      return const ToolResult(
        toolName: 'get_pending_cleanup_review',
        output:
            'No pending cleanup items. The user has not selected anything to clean yet.',
      );
    }

    // Pre-compute Windows known-folder shortcuts so paths can be displayed
    // compactly (e.g. %TEMP% instead of C:\Users\...\AppData\Local\Temp).
    final shortcuts = _knownFolderShortcuts();

    final buffer = StringBuffer();
    buffer.writeln(
      'PENDING CLEANUP: ${items.length} items, '
      '${_formatSize(service.pendingCleanupBytes)}',
    );

    final byCategory = <String, List<JunkItem>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.categoryId, () => []).add(item);
    }

    for (final entry in byCategory.entries) {
      final catItems = entry.value;
      final catBytes = catItems.fold<int>(0, (s, i) => s + i.sizeBytes);
      buffer.writeln();
      buffer.writeln(
        '${entry.key}: ${catItems.length} items, '
        '${_formatSize(catBytes)}',
      );

      // Aggregate by ROOT (top-3 distinct path prefixes after shortcut)
      final byRoot = <String, _RootStat>{};
      final extCounts = <String, int>{};
      for (final f in catItems) {
        final root = _shortenPath(_findRootPrefix(f.path, catItems), shortcuts);
        final stat = byRoot.putIfAbsent(root, () => _RootStat());
        stat.count++;
        stat.bytes += f.sizeBytes;

        // Extension stats (category-wide)
        final dot = f.path.lastIndexOf('.');
        final slash = f.path.lastIndexOf(RegExp(r'[\\/]'));
        final ext = (dot > slash && dot > 0)
            ? f.path.substring(dot).toLowerCase()
            : '(no-ext)';
        extCounts[ext] = (extCounts[ext] ?? 0) + 1;
      }

      // Roots: top 3 by size
      final sortedRoots = byRoot.entries.toList()
        ..sort((a, b) => b.value.bytes.compareTo(a.value.bytes));
      final rootsLine = sortedRoots
          .take(3)
          .map(
            (e) => '${e.key} (${e.value.count}, ${_formatSize(e.value.bytes)})',
          )
          .join('; ');
      if (rootsLine.isNotEmpty) {
        buffer.writeln(
          '  roots: $rootsLine'
          '${sortedRoots.length > 3 ? ' +${sortedRoots.length - 3} more' : ''}',
        );
      }

      // Extensions: top 5
      final sortedExts = extCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final extsLine = sortedExts
          .take(5)
          .map((e) => '${e.key} x${e.value}')
          .join(', ');
      if (extsLine.isNotEmpty) {
        buffer.writeln(
          '  exts: $extsLine'
          '${sortedExts.length > 5 ? ', +${sortedExts.length - 5}' : ''}',
        );
      }
    }

    buffer.writeln();
    buffer.writeln(
      'Review: are these safe to move to Recycle Bin? '
      'Flag any risky categories or roots.',
    );

    return ToolResult(
      toolName: 'get_pending_cleanup_review',
      output: buffer.toString().trim(),
    );
  }

  ToolResult _getCurrentCleanerScan(Map<String, dynamic> args) {
    final service = DiskCleanerService.instance;
    final context = service.getCleanerScanContext(ownerTabId: ownerTabId);
    if (context == null) {
      return const ToolResult(
        toolName: 'get_current_cleaner_scan',
        output:
            'No current Cleaner scan context is available for this tab. Ask the user to open CB Agent from the Cleaner screen or run a scan first.',
      );
    }

    final maxItems = (args['max_items'] as int?)?.clamp(5, 50) ?? 20;
    final sectionLimit = maxItems > 8 ? 8 : maxItems;
    final includeSelected = args['include_selected'] as bool? ?? true;
    final root = context.root;
    final selectedNode = context.selectedPath == null
        ? null
        : _findDiskTreeNode(root, context.selectedPath!);
    final chartNode = context.chartPath == null
        ? null
        : _findDiskTreeNode(root, context.chartPath!);

    final largestFiles = <DiskTreeNode>[];
    final largestFolders = <DiskTreeNode>[];
    final junkNodes = <DiskTreeNode>[];
    final selectedNodes = <DiskTreeNode>[];
    var selectedBytes = 0;
    var selectedCount = 0;

    void collect(DiskTreeNode node, {bool coveredByJunkAncestor = false}) {
      if (node.fullPath.isNotEmpty && node.isSelectedForDeletion) {
        selectedNodes.add(node);
        selectedBytes += node.sizeBytes;
        selectedCount++;
      }

      if (node.fullPath.isNotEmpty && !identical(node, root)) {
        _offerLargest(
          node.isFile ? largestFiles : largestFolders,
          node,
          sectionLimit,
        );
      }

      final isCanonicalJunk = node.isJunk && !coveredByJunkAncestor;
      if (node.fullPath.isNotEmpty && isCanonicalJunk) {
        _offerLargest(junkNodes, node, sectionLimit);
      }
      for (final child in node.children) {
        collect(
          child,
          coveredByJunkAncestor: coveredByJunkAncestor || node.isJunk,
        );
      }
    }

    collect(root);
    selectedNodes.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    final buffer = StringBuffer();
    buffer.writeln(
      context.isCached
          ? 'PREVIOUS CACHED CLEANER SCAN'
          : 'CURRENT CLEANER SCAN',
    );
    buffer.writeln('Owner tab: ${context.ownerTabId}');
    buffer.writeln('Context published: ${context.updatedAt.toIso8601String()}');
    buffer.writeln(
      'Status: ${context.isCached
          ? "previous cached result"
          : context.isScanning
          ? "scanning"
          : "ready"}',
    );
    if (context.isCached) {
      buffer.writeln(
        'Freshness: previous cached result; this is not a current scan.',
      );
      buffer.writeln(
        'Refresh: Use Scan again to refresh before relying on this data.',
      );
    }
    buffer.writeln(
      'Root: ${root.fullPath} (${_formatSize(root.sizeBytes)}, ${root.fileCount} files)',
    );
    buffer.writeln('Junk marked: ${_formatSize(root.junkBytes)}');
    buffer.writeln(
      'Selected for cleanup: $selectedCount items, ${_formatSize(selectedBytes)}',
    );

    if (selectedNode != null) {
      buffer.writeln();
      buffer.writeln('Selected node: ${_formatDiskTreeNode(selectedNode)}');
    }
    if (chartNode != null && chartNode.fullPath != selectedNode?.fullPath) {
      buffer.writeln('Chart node: ${_formatDiskTreeNode(chartNode)}');
    }

    buffer.writeln();
    buffer.writeln('Largest folders (size is evidence, not deletion safety):');
    if (largestFolders.isEmpty) {
      buffer.writeln('  (none)');
    } else {
      for (final node in largestFolders) {
        buffer.writeln('  - ${_formatSpaceConsumer(node)}');
      }
    }

    buffer.writeln();
    buffer.writeln('Largest files (size is evidence, not deletion safety):');
    if (largestFiles.isEmpty) {
      buffer.writeln('  (none)');
    } else {
      for (final node in largestFiles) {
        buffer.writeln('  - ${_formatSpaceConsumer(node)}');
      }
    }

    buffer.writeln();
    buffer.writeln('Rule-backed cleanup candidates:');
    if (junkNodes.isEmpty) {
      buffer.writeln('  (none marked as junk)');
    } else {
      for (final node in junkNodes) {
        buffer.writeln('  - ${_formatCleanupCandidate(node)}');
      }
    }

    if (includeSelected) {
      buffer.writeln();
      buffer.writeln('Selected cleanup items:');
      if (selectedNodes.isEmpty) {
        buffer.writeln('  (none selected)');
      } else {
        for (final node in selectedNodes.take(sectionLimit)) {
          buffer.writeln('  - ${_formatDiskTreeNode(node)}');
        }
        if (selectedNodes.length > sectionLimit) {
          buffer.writeln('  ... ${selectedNodes.length - sectionLimit} more');
        }
      }
    }

    buffer.writeln();
    buffer.writeln(
      'RESPONSE REQUIREMENT: Answer with a readable ranked report, '
      'not JSON. Explain what each item belongs to and label it CLEAN, REVIEW, '
      'or KEEP with a reason. Do not call clean_disk_junk for an analysis or '
      'recommendation request.',
    );

    return ToolResult(
      toolName: 'get_current_cleaner_scan',
      output: _truncate(buffer.toString().trim()),
    );
  }

  ToolResult _getCurrentAppStorage(Map<String, dynamic> args) {
    final service = DiskCleanerService.instance;
    final context = service.getCleanerScanContext(ownerTabId: ownerTabId);
    final report = context?.appStorageReport;
    if (context == null || report == null) {
      return const ToolResult(
        toolName: 'get_current_app_storage',
        output:
            'No App Insights report is available for this Cleaner tab. Ask the user to finish a disk scan and open the Apps view first.',
      );
    }
    if (!context.appInsightsSharedWithAgent) {
      return const ToolResult(
        toolName: 'get_current_app_storage',
        output:
            'App Insights has not been shared with CB Agent. Ask the user to click Ask CB Agent in the Apps view.',
      );
    }

    final filter = (args['filter'] as String? ?? 'all').toLowerCase();
    final requestedAppId = (args['app_id'] as String?)?.trim();
    final maxApps = (args['max_apps'] as int?)?.clamp(1, 50) ?? 20;
    final wantsPaths = args['include_paths'] as bool? ?? false;
    final mayIncludePaths =
        wantsPaths &&
        requestedAppId != null &&
        requestedAppId.isNotEmpty &&
        requestedAppId == context.selectedAppId;
    const staleThreshold = Duration(days: 180);
    const largeThresholdBytes = 1024 * 1024 * 1024;
    final now = DateTime.now();

    var profiles = report.apps.toList(growable: false);
    if (requestedAppId != null && requestedAppId.isNotEmpty) {
      profiles = profiles
          .where((profile) => profile.app.id == requestedAppId)
          .toList(growable: false);
    } else {
      switch (filter) {
        case 'large':
          profiles = profiles
              .where(
                (profile) => profile.bestKnownSizeBytes >= largeThresholdBytes,
              )
              .toList(growable: false);
          break;
        case 'stale':
          profiles = profiles
              .where(
                (profile) =>
                    profile.isStale(now: now, threshold: staleThreshold),
              )
              .toList(growable: false);
          break;
        case 'cleanable':
          profiles = profiles
              .where((profile) => profile.cleanableBytes > 0)
              .toList(growable: false);
          break;
        case 'all':
          break;
        default:
          return ToolResult(
            toolName: 'get_current_app_storage',
            output:
                'Invalid filter "$filter". Use all, large, stale, or cleanable.',
            success: false,
          );
      }
    }

    profiles.sort(
      (a, b) => b.bestKnownSizeBytes.compareTo(a.bestKnownSizeBytes),
    );

    final staleCount = report.apps
        .where(
          (profile) => profile.isStale(now: now, threshold: staleThreshold),
        )
        .length;
    final largeCount = report.apps
        .where((profile) => profile.bestKnownSizeBytes >= largeThresholdBytes)
        .length;

    final buffer = StringBuffer();
    buffer.writeln('CURRENT CLEANER APP STORAGE');
    buffer.writeln('Drive: ${report.drivePath}');
    buffer.writeln('Generated: ${report.generatedAt.toIso8601String()}');
    buffer.writeln('Coverage: ${report.isPartial ? "partial" : "complete"}');
    buffer.writeln(
      'Apps: ${report.apps.length}; confirmed footprint: ${_formatSize(report.confirmedSizeBytes)}; '
      'large: $largeCount; not seen for 180+ days: $staleCount; '
      'cleanable app data: ${_formatSize(report.cleanableBytes)}',
    );
    buffer.writeln(
      'Last-opened values are local Windows evidence estimates. Unknown means no reliable evidence was found.',
    );

    if (profiles.isEmpty) {
      buffer.writeln('No apps match the requested filter.');
    } else {
      buffer.writeln();
      buffer.writeln('Matching apps:');
      for (final profile in profiles.take(maxApps)) {
        final app = profile.app;
        final usage = profile.usage;
        final lastOpenedAt = usage.lastOpenedAt;
        final lastOpened = lastOpenedAt == null || lastOpenedAt.isAfter(now)
            ? 'unknown'
            : '${now.difference(lastOpenedAt).inDays} days ago '
                  '(${usage.source?.name ?? "unknown"}, ${usage.confidence?.name ?? "unknown"})';
        final possible = profile.possibleSizeBytes > 0
            ? ', possible=${_formatSize(profile.possibleSizeBytes)}'
            : '';
        final cleanable = profile.cleanableBytes > 0
            ? ', cleanable=${_formatSize(profile.cleanableBytes)}'
            : '';
        buffer.writeln(
          '- ${app.displayName} [id=${app.id}, source=${app.source.name}, '
          'size=${_formatSize(profile.bestKnownSizeBytes)}, quality=${profile.measurementQuality.name}$possible$cleanable, '
          'last_opened=$lastOpened]',
        );
        for (final entry in profile.entries) {
          final description =
              '${entry.kind.name}: ${_formatSize(entry.sizeBytes)} '
              '[${entry.attributionConfidence.name}, ${entry.measurementQuality.name}${entry.isCleanable ? ", cleanable" : ""}]';
          if (mayIncludePaths) {
            buffer.writeln('  - $description ${entry.path}');
          } else {
            buffer.writeln('  - $description');
          }
        }
      }
      if (profiles.length > maxApps) {
        buffer.writeln('... ${profiles.length - maxApps} more matching apps');
      }
    }

    if (report.sharedOrUnattributed.isNotEmpty) {
      final sharedBytes = report.sharedOrUnattributed.fold<int>(
        0,
        (sum, entry) => sum + entry.sizeBytes,
      );
      buffer.writeln();
      buffer.writeln(
        'Shared or unattributed large folders: ${report.sharedOrUnattributed.length}, ${_formatSize(sharedBytes)}. '
        'They are informational and never cleanup targets.',
      );
    }
    if (report.warnings.isNotEmpty) {
      buffer.writeln('Warnings: ${report.warnings.join("; ")}');
    }

    return ToolResult(
      toolName: 'get_current_app_storage',
      output: _truncate(buffer.toString().trim()),
    );
  }

  DiskTreeNode? _findDiskTreeNode(DiskTreeNode root, String path) {
    if (root.fullPath == path) return root;
    for (final child in root.children) {
      final match = _findDiskTreeNode(child, path);
      if (match != null) return match;
    }
    return null;
  }

  String _formatDiskTreeNode(DiskTreeNode node) {
    final type = node.isFile ? 'file' : 'folder';
    final junk = node.isJunk
        ? ', junk=${node.junkCategoryId}'
        : (node.hasJunkChildren
              ? ', junk_children=${_formatSize(node.junkBytes)}'
              : '');
    final selected = node.isSelectedForDeletion ? ', selected' : '';
    return '${node.fullPath} [$type, ${_formatSize(node.sizeBytes)}, ${node.fileCount} files$junk$selected]';
  }

  void _offerLargest(
    List<DiskTreeNode> nodes,
    DiskTreeNode candidate,
    int limit,
  ) {
    nodes.add(candidate);
    nodes.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    if (nodes.length > limit) {
      nodes.removeLast();
    }
  }

  String _formatSpaceConsumer(DiskTreeNode node) {
    final type = node.isFile ? 'file' : 'folder';
    if (node.isJunk) {
      final categoryId = node.junkCategoryId!;
      final category = CleanerCategories.byId(categoryId);
      final safety = category?.safety ?? CleanerSafety.careful;
      return '${node.fullPath} [$type, ${_formatSize(node.sizeBytes)}, '
          'owner=${_junkOwner(categoryId, node.fullPath)}, '
          'category=${category?.displayName ?? categoryId}, '
          '${_categoryRecommendation(safety)}]';
    }
    return '${node.fullPath} [$type, ${_formatSize(node.sizeBytes)}, '
        'owner=${_pathOwner(node.fullPath)}, REVIEW: Large size alone does not '
        'make this safe to delete; keep it unless the user recognizes it.]';
  }

  String _formatCleanupCandidate(DiskTreeNode node) {
    final categoryId = node.junkCategoryId!;
    final category = CleanerCategories.byId(categoryId);
    final safety = category?.safety ?? CleanerSafety.careful;
    final type = node.isFile ? 'file' : 'folder';
    return '${node.fullPath} [$type, ${_formatSize(node.sizeBytes)}, '
        'owner=${_junkOwner(categoryId, node.fullPath)}, '
        'category=${category?.displayName ?? categoryId} ($categoryId), '
        'safety=${safety.name}, ${_categoryRecommendation(safety)}]';
  }

  String _categoryRecommendation(CleanerSafety safety) {
    switch (safety) {
      case CleanerSafety.safe:
        return 'CLEAN: Usually safe because the OS or app can recreate it.';
      case CleanerSafety.careful:
        return 'REVIEW: Usually removable, but inspect the side effects first.';
      case CleanerSafety.risky:
        return 'KEEP: Do not clean by default; rebuilding may be slow or costly.';
    }
  }

  String _junkOwner(String categoryId, String path) {
    final category = CleanerCategories.byId(categoryId);
    if (category == null) return 'Unknown';

    final upperPath = path.toUpperCase();
    final hints = <String>[];
    for (final rule in category.rules) {
      for (final hint in rule.appOwnerHints) {
        final normalized = hint.trim();
        if (normalized.isEmpty || normalized.toLowerCase().endsWith('.exe')) {
          continue;
        }
        if (!hints.contains(normalized)) hints.add(normalized);
      }
    }
    for (final hint in hints) {
      final tokens = RegExp(r'[A-Za-z0-9]+')
          .allMatches(hint.toUpperCase())
          .map((match) => match.group(0)!)
          .where((token) => token.length > 1);
      if (tokens.isNotEmpty && tokens.every(upperPath.contains)) return hint;
    }
    return hints.isNotEmpty ? hints.take(3).join(' / ') : category.displayName;
  }

  String _pathOwner(String path) {
    final normalized = path.replaceAll('/', r'\').toUpperCase();
    if (normalized.contains(r'\WINDOWS\')) return 'Windows system';
    if (normalized.contains(r'\PROGRAM FILES\') ||
        normalized.contains(r'\PROGRAM FILES (X86)\')) {
      return 'Installed application';
    }
    if (normalized.contains(r'\USERS\') &&
        (normalized.contains(r'\DOWNLOADS\') ||
            normalized.endsWith(r'\DOWNLOADS'))) {
      return 'User Downloads';
    }
    if (normalized.contains(r'\APPDATA\')) return 'Application data';
    return 'User or application data (unclassified)';
  }

  /// Resolves Windows known folders so paths in the review can be shown as
  /// short shortcuts (`%TEMP%`, `%APPDATA%`, etc).
  List<MapEntry<String, String>> _knownFolderShortcuts() {
    if (!Platform.isWindows) return const [];
    final env = Platform.environment;
    final result = <MapEntry<String, String>>[];
    void add(String name, String? path) {
      if (path != null && path.isNotEmpty) {
        result.add(MapEntry(path.toUpperCase(), '%$name%'));
      }
    }

    add('TEMP', env['TEMP']);
    add('LOCALAPPDATA', env['LOCALAPPDATA']);
    add('APPDATA', env['APPDATA']);
    add('USERPROFILE', env['USERPROFILE']);
    add('PROGRAMDATA', env['PROGRAMDATA']);
    add('WINDIR', env['WINDIR']);

    // Sort by length descending so we match the most-specific path first.
    result.sort((a, b) => b.key.length.compareTo(a.key.length));
    return result;
  }

  String _shortenPath(String path, List<MapEntry<String, String>> shortcuts) {
    final upper = path.toUpperCase();
    for (final pair in shortcuts) {
      if (upper.startsWith(pair.key)) {
        final remainder = path.substring(pair.key.length);
        return '${pair.value}$remainder';
      }
    }
    return path;
  }

  /// Returns a "natural root" for a path within the given items: the deepest
  /// shared directory prefix that contains the path. Falls back to the first
  /// 3 path segments if there's no obvious shared root.
  String _findRootPrefix(String path, List<JunkItem> peers) {
    final segments = path
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.length <= 3) return path;
    // Use first 3 segments as the root, e.g. C:\Users\ngtan
    return '${segments[0]}\\${segments[1]}\\${segments[2]}';
  }

  static List<String>? _normalizeCleanerCategories(Object? value) {
    if (value is! List) return null;

    final normalized = <String>[];
    void add(String category) {
      if (!normalized.contains(category)) {
        normalized.add(category);
      }
    }

    for (final raw in value) {
      final category = raw.toString().trim().toLowerCase();
      if (category == 'cache') {
        add('browser_cache');
        add('thumbnail_cache');
        add('app_cache');
      } else if (category.isNotEmpty) {
        add(category);
      }
    }
    return normalized;
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
  static String get toolDefinitions => AgentToolCatalog.definitions;
}

class _RootStat {
  int count = 0;
  int bytes = 0;
}

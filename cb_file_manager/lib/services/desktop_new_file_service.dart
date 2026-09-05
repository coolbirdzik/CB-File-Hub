import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/models/file_template.dart';
import 'package:cb_file_manager/services/file_template_service.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

enum DesktopNewFileItemKind { template, shellNew }

enum WindowsShellNewCreationMode { nullFile, templateFile, binaryData }

class WindowsShellNewEntry {
  final String id;
  final String extension;
  final WindowsShellNewCreationMode creationMode;
  final String? templateFilePath;
  final List<int>? binaryData;
  final String registryKey;

  const WindowsShellNewEntry({
    required this.id,
    required this.extension,
    required this.creationMode,
    required this.registryKey,
    this.templateFilePath,
    this.binaryData,
  });
}

class DesktopNewFileItem {
  final String id;
  final String extension;
  final IconData icon;
  final String suggestedBaseName;
  final DesktopNewFileItemKind kind;
  final FileTemplate? template;
  final WindowsShellNewEntry? shellNewEntry;

  const DesktopNewFileItem({
    required this.id,
    required this.extension,
    required this.icon,
    required this.suggestedBaseName,
    required this.kind,
    this.template,
    this.shellNewEntry,
  });
}

class DesktopNewFileService {
  DesktopNewFileService._();

  static final DesktopNewFileService instance = DesktopNewFileService._();
  static const Duration defaultShellNewWait = Duration(milliseconds: 120);

  Future<List<WindowsShellNewEntry>>? _shellNewEntriesFuture;

  Future<List<DesktopNewFileItem>> getAvailableItems({
    Duration shellNewWait = defaultShellNewWait,
  }) async {
    await FileTemplateService.instance.init();

    final shellNewEntries = await _getShellNewEntriesForMenu(
      waitDuration: shellNewWait,
    );
    final shellNewByExtension = <String, WindowsShellNewEntry>{
      for (final entry in shellNewEntries) entry.extension: entry,
    };

    final items = <DesktopNewFileItem>[];

    for (final template
        in FileTemplateService.instance.getAvailableTemplates()) {
      if (shellNewByExtension.containsKey(template.extension)) {
        continue;
      }
      items.add(
        DesktopNewFileItem(
          id: 'template:${template.extension}',
          extension: template.extension,
          icon: template.icon,
          suggestedBaseName:
              template.defaultFileName ??
              template.extension.replaceFirst('.', '').toUpperCase(),
          kind: DesktopNewFileItemKind.template,
          template: template,
        ),
      );
    }

    for (final entry in shellNewEntries) {
      items.add(
        DesktopNewFileItem(
          id: entry.id,
          extension: entry.extension,
          icon: FileTypeRegistry.getIcon(entry.extension),
          suggestedBaseName: _defaultBaseNameForExtension(entry.extension),
          kind: DesktopNewFileItemKind.shellNew,
          shellNewEntry: entry,
        ),
      );
    }

    items.sort((a, b) => a.extension.compareTo(b.extension));
    return items;
  }

  Future<List<WindowsShellNewEntry>> getShellNewEntries() {
    if (!Platform.isWindows) {
      return Future<List<WindowsShellNewEntry>>.value(const []);
    }
    _shellNewEntriesFuture ??= _loadShellNewEntries();
    return _shellNewEntriesFuture!;
  }

  Future<List<WindowsShellNewEntry>> _getShellNewEntriesForMenu({
    required Duration waitDuration,
  }) async {
    final future = getShellNewEntries();
    if (waitDuration <= Duration.zero) {
      return const [];
    }

    try {
      return await future.timeout(
        waitDuration,
        onTimeout: () => const <WindowsShellNewEntry>[],
      );
    } catch (_) {
      return const [];
    }
  }

  void invalidateShellNewCache() {
    _shellNewEntriesFuture = null;
  }

  Future<String?> createItem({
    required String directoryPath,
    required DesktopNewFileItem item,
    String? customBaseName,
  }) async {
    switch (item.kind) {
      case DesktopNewFileItemKind.template:
        final template = item.template;
        if (template == null) {
          return null;
        }
        return FileTemplateService.instance.createFile(
          directoryPath,
          template,
          customBaseName ?? item.suggestedBaseName,
        );
      case DesktopNewFileItemKind.shellNew:
        final shellNewEntry = item.shellNewEntry;
        if (shellNewEntry == null) {
          return null;
        }
        return _createFromShellNew(
          directoryPath: directoryPath,
          entry: shellNewEntry,
          baseName: customBaseName ?? item.suggestedBaseName,
        );
    }
  }

  List<String> buildDefaultQuickItemIds(List<DesktopNewFileItem> items) {
    const preferredExtensions = <String>[
      '.txt',
      '.bmp',
      '.rtf',
      '.zip',
      '.docx',
      '.xlsx',
      '.pptx',
      '.md',
      '.json',
    ];

    final itemByExtension = <String, DesktopNewFileItem>{
      for (final item in items) item.extension.toLowerCase(): item,
    };

    final orderedIds = <String>[];
    for (final extension in preferredExtensions) {
      final item = itemByExtension[extension];
      if (item != null) {
        orderedIds.add(item.id);
      }
    }

    if (orderedIds.length < 6) {
      for (final item in items) {
        if (orderedIds.contains(item.id)) {
          continue;
        }
        orderedIds.add(item.id);
        if (orderedIds.length >= 6) {
          break;
        }
      }
    }

    return orderedIds;
  }

  Future<List<WindowsShellNewEntry>> _loadShellNewEntries() async {
    try {
      final result = await Process.run('reg', [
        'query',
        'HKCR',
        '/f',
        'ShellNew',
        '/s',
        '/k',
      ]);
      if (result.exitCode != 0) {
        return const [];
      }

      final output = (result.stdout as String?) ?? '';
      final lines = const LineSplitter().convert(output);
      final shellNewKeys = <String>[];

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (!line.startsWith(r'HKEY_CLASSES_ROOT\.')) {
          continue;
        }
        if (!line.toLowerCase().endsWith(r'\shellnew')) {
          continue;
        }
        shellNewKeys.add(line);
      }

      final entriesByExtension = <String, WindowsShellNewEntry>{};
      for (final key in shellNewKeys) {
        final entry = await _loadShellNewEntry(key);
        if (entry == null) {
          continue;
        }
        final existing = entriesByExtension[entry.extension];
        if (existing == null ||
            _creationModePriority(entry.creationMode) >
                _creationModePriority(existing.creationMode)) {
          entriesByExtension[entry.extension] = entry;
        }
      }

      final entries = entriesByExtension.values.toList()
        ..sort((a, b) => a.extension.compareTo(b.extension));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  Future<WindowsShellNewEntry?> _loadShellNewEntry(String key) async {
    final extensionMatch = RegExp(
      r'^HKEY_CLASSES_ROOT\\(\.[^\\]+)',
    ).firstMatch(key);
    final extension = extensionMatch?.group(1)?.toLowerCase();
    if (extension == null || extension.isEmpty) {
      return null;
    }

    final result = await Process.run('reg', ['query', key]);
    if (result.exitCode != 0) {
      return null;
    }

    final output = (result.stdout as String?) ?? '';
    final values = _parseRegistryValues(output);

    if (values.containsKey('NullFile')) {
      return WindowsShellNewEntry(
        id: 'shellnew:$extension',
        extension: extension,
        creationMode: WindowsShellNewCreationMode.nullFile,
        registryKey: key,
      );
    }

    final templateFileRaw = values['FileName'] ?? values['filename'];
    if (templateFileRaw != null && templateFileRaw.trim().isNotEmpty) {
      final templateFilePath = _resolveTemplateFilePath(templateFileRaw.trim());
      if (templateFilePath != null) {
        return WindowsShellNewEntry(
          id: 'shellnew:$extension',
          extension: extension,
          creationMode: WindowsShellNewCreationMode.templateFile,
          templateFilePath: templateFilePath,
          registryKey: key,
        );
      }
    }

    final binaryDataRaw = values['Data'];
    if (binaryDataRaw != null && binaryDataRaw.trim().isNotEmpty) {
      final binaryData = _parseBinaryData(binaryDataRaw);
      if (binaryData.isNotEmpty) {
        return WindowsShellNewEntry(
          id: 'shellnew:$extension',
          extension: extension,
          creationMode: WindowsShellNewCreationMode.binaryData,
          binaryData: binaryData,
          registryKey: key,
        );
      }
    }

    return null;
  }

  Map<String, String> _parseRegistryValues(String output) {
    final values = <String, String>{};
    final lines = const LineSplitter().convert(output);
    for (final rawLine in lines) {
      if (rawLine.trim().isEmpty ||
          rawLine.trimLeft().startsWith('HKEY_CLASSES_ROOT')) {
        continue;
      }

      final match = RegExp(
        r'^\s*([^\s]+)\s+REG_[A-Z_]+\s+(.+)$',
      ).firstMatch(rawLine);
      if (match == null) {
        continue;
      }

      final name = match.group(1)?.trim();
      final value = match.group(2)?.trim();
      if (name == null || value == null) {
        continue;
      }
      values[name] = value;
    }
    return values;
  }

  String? _resolveTemplateFilePath(String rawValue) {
    final expanded = _expandEnvironmentVariables(rawValue);
    final directFile = File(expanded);
    if (directFile.existsSync()) {
      return directFile.path;
    }

    final windowsDir = Platform.environment['WINDIR'];
    if (windowsDir != null && windowsDir.isNotEmpty) {
      final candidate = File(path.join(windowsDir, 'ShellNew', expanded));
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }

    return null;
  }

  String _expandEnvironmentVariables(String input) {
    return input.replaceAllMapped(RegExp(r'%([^%]+)%'), (match) {
      final key = match.group(1);
      if (key == null) {
        return match.group(0) ?? '';
      }
      return Platform.environment[key] ?? match.group(0) ?? '';
    });
  }

  List<int> _parseBinaryData(String rawValue) {
    final cleaned = rawValue.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty || cleaned.length.isOdd) {
      return const [];
    }

    final bytes = <int>[];
    for (var i = 0; i < cleaned.length; i += 2) {
      final hexPair = cleaned.substring(i, i + 2);
      final value = int.tryParse(hexPair, radix: 16);
      if (value == null) {
        return const [];
      }
      bytes.add(value);
    }
    return bytes;
  }

  Future<String?> _createFromShellNew({
    required String directoryPath,
    required WindowsShellNewEntry entry,
    required String baseName,
  }) async {
    final uniquePath = await _buildUniquePath(
      directoryPath,
      _normalizeBaseName(baseName, entry.extension),
      entry.extension,
    );
    if (uniquePath == null) {
      return null;
    }

    try {
      switch (entry.creationMode) {
        case WindowsShellNewCreationMode.nullFile:
          await File(uniquePath).create(exclusive: true);
          break;
        case WindowsShellNewCreationMode.templateFile:
          final sourcePath = entry.templateFilePath;
          if (sourcePath == null || !File(sourcePath).existsSync()) {
            return null;
          }
          await File(sourcePath).copy(uniquePath);
          break;
        case WindowsShellNewCreationMode.binaryData:
          final data = entry.binaryData;
          if (data == null) {
            return null;
          }
          await File(uniquePath).writeAsBytes(data, flush: true);
          break;
      }

      return uniquePath;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _buildUniquePath(
    String directoryPath,
    String baseName,
    String extension,
  ) async {
    final normalizedExtension = extension.startsWith('.')
        ? extension
        : '.$extension';
    final fileName = '$baseName$normalizedExtension';
    final initialPath = path.join(directoryPath, fileName);
    if (!await File(initialPath).exists()) {
      return initialPath;
    }

    for (var index = 1; index <= 999; index++) {
      final candidatePath = path.join(
        directoryPath,
        '$baseName ($index)$normalizedExtension',
      );
      if (!await File(candidatePath).exists()) {
        return candidatePath;
      }
    }

    return null;
  }

  String _normalizeBaseName(String name, String extension) {
    final trimmed = name.trim().isEmpty
        ? _defaultBaseNameForExtension(extension)
        : name.trim();
    final withoutInvalidChars = trimmed
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return withoutInvalidChars.isEmpty
        ? _defaultBaseNameForExtension(extension)
        : withoutInvalidChars;
  }

  String _defaultBaseNameForExtension(String extension) {
    final raw = extension.replaceFirst('.', '').trim();
    if (raw.isEmpty) {
      return 'New File';
    }
    final normalized = raw.toUpperCase();
    return 'New $normalized File';
  }

  int _creationModePriority(WindowsShellNewCreationMode mode) {
    switch (mode) {
      case WindowsShellNewCreationMode.templateFile:
        return 3;
      case WindowsShellNewCreationMode.binaryData:
        return 2;
      case WindowsShellNewCreationMode.nullFile:
        return 1;
    }
  }
}

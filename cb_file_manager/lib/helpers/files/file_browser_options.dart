import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'file_attributes.dart';

/// Presentation and input preferences, independent of per-folder layout.
@immutable
class FileBrowserOptions {
  const FileBrowserOptions({
    this.showExtensions = true,
    this.showHidden = true,
    this.showSystem = true,
    this.selectionCheckboxes = false,
    this.singleClickToOpen = false,
  });

  // Keep the existing behavior for users upgrading from earlier releases.
  final bool showExtensions, showHidden, showSystem;
  final bool selectionCheckboxes, singleClickToOpen;

  FileBrowserOptions copyWith({
    bool? showExtensions,
    bool? showHidden,
    bool? showSystem,
    bool? selectionCheckboxes,
    bool? singleClickToOpen,
  }) => FileBrowserOptions(
    showExtensions: showExtensions ?? this.showExtensions,
    showHidden: showHidden ?? this.showHidden,
    showSystem: showSystem ?? this.showSystem,
    selectionCheckboxes: selectionCheckboxes ?? this.selectionCheckboxes,
    singleClickToOpen: singleClickToOpen ?? this.singleClickToOpen,
  );

  factory FileBrowserOptions.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return FileBrowserOptions(
      showExtensions: flag('extensions', true),
      showHidden: flag('hidden', true),
      showSystem: flag('system', true),
      selectionCheckboxes: flag('checkboxes', false),
      singleClickToOpen: flag('singleClick', false),
    );
  }

  Map<String, bool> toJson() => {
    'extensions': showExtensions,
    'hidden': showHidden,
    'system': showSystem,
    'checkboxes': selectionCheckboxes,
    'singleClick': singleClickToOpen,
  };

  String fileLabel(String name) {
    if (showExtensions) return name;
    final extension = p.extension(name);
    // Dotfiles without a second dot do not have an extension.
    return extension.isEmpty
        ? name
        : name.substring(0, name.length - extension.length);
  }

  bool sameVisibility(FileBrowserOptions other) =>
      showHidden == other.showHidden && showSystem == other.showSystem;

  @override
  bool operator ==(Object other) =>
      other is FileBrowserOptions &&
      showExtensions == other.showExtensions &&
      sameVisibility(other) &&
      selectionCheckboxes == other.selectionCheckboxes &&
      singleClickToOpen == other.singleClickToOpen;

  @override
  int get hashCode => Object.hash(
    showExtensions,
    showHidden,
    showSystem,
    selectionCheckboxes,
    singleClickToOpen,
  );
}

/// Filter a directory listing without modifying the real filenames or cached
/// raw listing. Windows attribute reads happen off the UI isolate.
Future<List<T>> visibleBrowserEntries<T extends FileSystemEntity>(
  List<T> entries,
  FileBrowserOptions options, {
  String? rootPath,
}) async {
  if (options.showHidden && (options.showSystem || !Platform.isWindows)) {
    return entries;
  }
  final excluded = await compute(_hiddenPaths, (
    paths: entries.map((entry) => entry.path).toList(),
    showHidden: options.showHidden,
    showSystem: options.showSystem,
    rootPath: rootPath,
  ));
  return entries.where((entry) => !excluded.contains(entry.path)).toList();
}

Set<String> _hiddenPaths(
  ({List<String> paths, bool showHidden, bool showSystem, String? rootPath})
  args,
) {
  final hidden = <String, bool>{};
  bool excluded(String path) => hidden.putIfAbsent(
    path,
    () => _excludePath(path, args.showHidden, args.showSystem),
  );
  bool excludedWithinRoot(String path) {
    if (excluded(path)) return true;
    final root = args.rootPath;
    if (root != null) {
      // Recursive search must also respect hidden ancestors, without hiding
      // the contents of a hidden directory the user explicitly navigated into.
      var parent = p.dirname(path);
      while (p.isWithin(root, parent)) {
        if (excluded(parent)) return true;
        final next = p.dirname(parent);
        if (next == parent) break;
        parent = next;
      }
    }
    return false;
  }

  return {
    for (final filePath in args.paths)
      if (excludedWithinRoot(filePath)) filePath,
  };
}

bool _excludePath(String filePath, bool showHidden, bool showSystem) {
  if (Platform.isWindows) {
    final attributes = FileAttributes.describe(filePath, null);
    return (!showHidden && attributes.contains('H')) ||
        (!showSystem && attributes.contains('S'));
  }
  return !showHidden && p.basename(filePath).startsWith('.');
}

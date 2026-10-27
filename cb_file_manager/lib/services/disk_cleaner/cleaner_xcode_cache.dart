import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_insights/app_insights_models.dart';
import 'cleaner_models.dart';

abstract final class CleanerXcodeCache {
  static const categoryId = 'xcode_build_cache';
  static const minAge = Duration(days: 7);
  static const relativeRoot = 'Library/Developer/Xcode/DerivedData';

  static const category = CleanerCategory(
    id: categoryId,
    displayName: 'Old Xcode build files',
    description:
        'Generated build products, intermediates, indexes and module caches unchanged for a week. Close Xcode and stop builds first. Sources, package checkouts, archives and dSYMs are kept; the next build and indexing may take longer.',
    safety: CleanerSafety.safe,
    defaultEnabled: true,
    rules: [
      CleanerPathRule(
        source: PathSource.env('HOME', relativeRoot),
        scope: CleanerRuleScope.xcodeBuildOutputs,
        minAge: minAge,
        excludeGlobs: ['LOCK', '*.lock', '*.lck'],
        appOwnerHints: ['Xcode', 'com.apple.dt.Xcode'],
        storageKind: AppStorageKind.cache,
      ),
    ],
  );

  static const _sharedCaches = {
    'ModuleCache.noindex',
    'CompilationCache.noindex',
    'SDKStatCaches.noindex',
    'SymbolCache.noindex',
  };
  static const _projectOutputs = [
    ['Build', 'Intermediates.noindex'],
    ['Build', 'Intermediates'],
    ['Build', 'Products'],
    ['Index.noindex'],
  ];

  /// Shallow discovery on the scan isolate. Never walks package checkouts,
  /// sources, Archives, simulators or arbitrary folders called "build".
  static List<String> discoverRoots(String derivedData, List<String> warnings) {
    final roots = <String>[];
    try {
      if (!_realDirectory(derivedData)) return roots;
      for (final entity in Directory(
        derivedData,
      ).listSync(followLinks: false)) {
        if (entity is! Directory || !_realDirectory(entity.path)) continue;
        if (_sharedCaches.contains(p.basename(entity.path))) {
          roots.add(entity.path);
          continue;
        }
        for (final output in _projectOutputs) {
          var target = entity.path;
          var exists = true;
          // Check each component so a symlinked Build cannot escape the scope.
          for (final component in output) {
            target = p.join(target, component);
            if (!_realDirectory(target)) {
              exists = false;
              break;
            }
          }
          if (exists) roots.add(target);
        }
      }
    } on FileSystemException catch (error) {
      warnings.add(
        '$categoryId: ${error.message} (${error.path ?? derivedData})',
      );
    }
    return roots;
  }

  static bool _realDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;

  /// Secondary check on every reported file, including native scan hits.
  static bool isGeneratedFile(String path) {
    final normalized = path.replaceAll(r'\', '/');
    const marker = '/$relativeRoot/';
    final index = normalized.indexOf(marker);
    if (index < 0) return false;
    final parts = normalized.substring(index + marker.length).split('/');
    if (parts.any((part) {
      final lower = part.toLowerCase();
      return part == '..' ||
          part == '.' ||
          lower == 'sourcepackages' ||
          lower == 'archives' ||
          lower.endsWith('.xcarchive') ||
          lower.endsWith('.dsym');
    })) {
      return false;
    }
    if (parts.length < 2) return false;
    if (_sharedCaches.contains(parts.first)) return true;
    if (parts.length >= 3 && parts[1] == 'Index.noindex') return true;
    return parts.length >= 4 &&
        parts[1] == 'Build' &&
        const {
          'Products',
          'Intermediates.noindex',
          'Intermediates',
        }.contains(parts[2]);
  }
}

import '../app_insights/app_insights_models.dart';
import 'cleaner_cache_rules.dart';
import 'cleaner_models.dart';

/// Narrow default locations verified by the Windows metadata audit, plus the
/// same developer caches at their Linux (XDG / dot-folder) and macOS defaults.
///
/// Only files a tool recreates or downloads again are taken: build and
/// analysis caches keyed per entry, downloaded installers and archives whose
/// extracted copy is kept, and plain log files. Installed dependencies
/// (`.m2/repository`, `.pub-cache`, Go `pkg/mod`, pnpm/uv/conda stores that
/// are hard-linked into environments) and extracted package trees, where a
/// partly deleted entry would look complete to the tool, stay out.
abstract final class CleanerAuditedRules {
  static const minAge = Duration(days: 7);
  static const _locks = ['LOCK', '*.lock', '*.lck', '*.tmp', '*.partial'];
  static const developerLogsId = 'developer_logs';
  static const cleanableIds = {
    'developer_analysis_cache',
    'developer_download_cache',
    developerLogsId,
    'electron_crash_reports',
  };

  static const _gradleHints = ['Gradle', 'Android Studio'];
  static const _rustupHints = ['rustup', 'Rust'];

  static final windows = <CleanerCategory>[
    CleanerCategory(
      id: 'developer_analysis_cache',
      displayName: 'Developer analysis and build caches',
      description:
          'Old Dart analysis, C/C++ precompiled headers, Go and Gradle build caches. Close editors, language servers and builds first. The next analysis/build may take longer.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        _cache('LOCALAPPDATA', '.dartServer/.analysis-driver', ['Dart']),
        _cache('USERPROFILE', '.dartServer/.analysis-driver', ['Dart']),
        _cache('LOCALAPPDATA', 'Microsoft/vscode-cpptools/ipch', [
          'Visual Studio Code',
        ]),
        _cache('LOCALAPPDATA', 'go-build', ['Go']),
        _cache('USERPROFILE', '.gradle/caches/build-cache-1', _gradleHints),
      ],
    ),
    CleanerCategory(
      id: 'developer_download_cache',
      displayName: 'Developer tool downloads',
      description:
          'Old cached VSIX installers, Comfy Desktop archives, node-gyp headers, Electron build tools, Android SDK downloads, Gradle distribution archives and rustup downloads. Finish installs/updates/builds first. Later installs may need internet; installed extensions, SDKs, environments and models are kept.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final folder in CleanerCacheRules.editorFolders)
          _cache('APPDATA', '$folder/CachedExtensionVSIXs', [folder]),
        _cache(
          'APPDATA',
          'Comfy Desktop/download-cache',
          ['Comfy Desktop'],
          globs: ['*.7z', '*.zip', '*.tar.gz', '*.tar.zst'],
        ),
        _cache('LOCALAPPDATA', 'node-gyp/Cache', ['node-gyp']),
        _cache('LOCALAPPDATA', 'electron-builder/Cache', ['electron-builder']),
        _cache('LOCALAPPDATA', 'electron/Cache', ['Electron']),
        ..._sharedDownloads('USERPROFILE'),
      ],
    ),
    CleanerCategory(
      id: developerLogsId,
      displayName: 'Developer tool logs',
      description: _logsDescription,
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final folder in CleanerCacheRules.editorFolders)
          _cache('APPDATA', '$folder/logs', [folder]),
        _cache('LOCALAPPDATA', 'npm-cache/_logs', ['npm'], globs: ['*.log']),
        _cache('APPDATA', 'npm-cache/_logs', ['npm'], globs: ['*.log']),
        _cache(
          'USERPROFILE',
          '.gradle/daemon',
          _gradleHints,
          globs: ['*.out.log'],
        ),
        _cache('LOCALAPPDATA', 'kotlin/daemon', ['Kotlin'], globs: ['*.log']),
      ],
    ),
    CleanerCategory(
      id: 'electron_crash_reports',
      displayName: 'Electron crash reports',
      description:
          'Crashpad minidumps unchanged for a week. They are diagnostic evidence, not app data. Keep reports still needed for troubleshooting; close the affected apps first.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final (folder, hints) in CleanerCacheRules.electronApps)
          for (final reports in ['reports', 'pending', 'completed'])
            _cache(
              'APPDATA',
              '$folder/Crashpad/$reports',
              hints,
              globs: ['*.dmp'],
            ),
      ],
    ),
    _review('cpp_database_review', 'C/C++ databases — review only', [
      const CleanerPathRule(
        source: PathSource.env('LOCALAPPDATA', 'Microsoft/vscode-cpptools'),
        includeGlobs: ['*.db'],
      ),
    ]),
    _review('vcpkg_artifacts_review', 'vcpkg artifacts — review only', [
      for (final folder in ['buildtrees', 'downloads', 'packages']) ...[
        _summary(PathSource.env('VCPKG_ROOT', folder)),
        _summary(PathSource.env('SystemDrive', 'vcpkg/$folder')),
      ],
    ]),
    _review('nvidia_shader_review', 'NVIDIA shader caches — review only', [
      for (final folder in ['DXCache', 'GLCache', 'OptixCache'])
        _summary(PathSource.env('LOCALAPPDATA', 'NVIDIA/$folder')),
    ]),
    _review('unreal_ddc_review', 'Unreal derived data — review only', [
      _summary(
        const PathSource.env('LOCALAPPDATA', 'UnrealEngine/Common/Zen/Data'),
      ),
      _summary(
        const PathSource.env(
          'LOCALAPPDATA',
          'UnrealEngine/Common/DerivedDataCache',
        ),
      ),
    ]),
    _review('pikpak_media_review', 'PikPak player cache — review only', [
      _summary(const PathSource.env('APPDATA', 'PikPak/Profiles/player-cache')),
    ]),
    _review('installer_cache_review', 'Installer packages — review only', [
      _summary(
        const PathSource.env('PROGRAMDATA', 'Microsoft/VisualStudio/Packages'),
      ),
      _summary(const PathSource.env('PROGRAMDATA', 'Package Cache')),
    ]),
  ];

  /// Linux defaults. `XDG_CACHE_HOME`/`XDG_CONFIG_HOME` are rarely set, so
  /// rules are anchored on `HOME`. node-gyp headers and electron-builder
  /// tools are extracted trees and are not taken here.
  static final linux = <CleanerCategory>[
    CleanerCategory(
      id: 'developer_analysis_cache',
      displayName: 'Developer analysis and build caches',
      description:
          'Old Dart analysis, C/C++ precompiled headers, Go and Gradle build caches. Close editors, language servers and builds first. The next analysis/build may take longer.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        _cache('HOME', '.dartServer/.analysis-driver', ['Dart']),
        _cache('HOME', '.cache/vscode-cpptools/ipch', ['Visual Studio Code']),
        _cache('HOME', '.cache/go-build', ['Go']),
        _cache('HOME', '.gradle/caches/build-cache-1', _gradleHints),
      ],
    ),
    CleanerCategory(
      id: 'developer_download_cache',
      displayName: 'Developer tool downloads',
      description:
          'Old cached VSIX installers, Electron downloads, Android SDK downloads, Gradle distribution archives and rustup downloads. Finish installs/updates/builds first. Later installs may need internet; installed extensions, SDKs and toolchains are kept.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final folder in CleanerCacheRules.editorFolders)
          _cache('HOME', '.config/$folder/CachedExtensionVSIXs', [folder]),
        _cache('HOME', '.cache/electron', ['Electron']),
        ..._sharedDownloads('HOME'),
      ],
    ),
    CleanerCategory(
      id: developerLogsId,
      displayName: 'Developer tool logs',
      description: _logsDescription,
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final folder in CleanerCacheRules.editorFolders)
          _cache('HOME', '.config/$folder/logs', [folder]),
        _cache('HOME', '.npm/_logs', ['npm'], globs: ['*.log']),
        _cache('HOME', '.gradle/daemon', _gradleHints, globs: ['*.out.log']),
        _cache(
          'HOME',
          '.local/share/kotlin/daemon',
          ['Kotlin'],
          globs: ['*.log'],
        ),
      ],
    ),
    CleanerCategory(
      id: 'electron_crash_reports',
      displayName: 'Electron crash reports',
      description:
          'Crashpad minidumps unchanged for a week. They are diagnostic evidence, not app data. Keep reports still needed for troubleshooting; close the affected apps first.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final (folder, hints) in CleanerCacheRules.electronApps)
          for (final reports in ['reports', 'pending', 'completed'])
            _cache(
              'HOME',
              '.config/$folder/Crashpad/$reports',
              hints,
              globs: ['*.dmp'],
            ),
      ],
    ),
  ];

  /// macOS defaults: editors keep their data under
  /// `~/Library/Application Support/<editor>` and most tools cache under
  /// `~/Library/Caches`, while dot-folder tools use the Linux layout.
  static final macos = <CleanerCategory>[
    CleanerCategory(
      id: 'developer_analysis_cache',
      displayName: 'Developer analysis and build caches',
      description:
          'Old Dart analysis, C/C++ precompiled headers, Go and Gradle build caches. Close editors, language servers and builds first. The next analysis/build may take longer.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        _cache('HOME', '.dartServer/.analysis-driver', ['Dart']),
        _cache('HOME', 'Library/Caches/vscode-cpptools/ipch', [
          'Visual Studio Code',
        ]),
        _cache('HOME', 'Library/Caches/go-build', ['Go']),
        _cache('HOME', '.gradle/caches/build-cache-1', _gradleHints),
      ],
    ),
    CleanerCategory(
      id: 'developer_download_cache',
      displayName: 'Developer tool downloads',
      description:
          'Old cached VSIX installers, Electron downloads, Android SDK downloads, Gradle distribution archives and rustup downloads. Finish installs/updates/builds first. Later installs may need internet; installed extensions, SDKs and toolchains are kept.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final folder in CleanerCacheRules.editorFolders)
          _cache(
            'HOME',
            'Library/Application Support/$folder/CachedExtensionVSIXs',
            [folder],
          ),
        _cache('HOME', 'Library/Caches/electron', ['Electron']),
        ..._sharedDownloads('HOME'),
      ],
    ),
    CleanerCategory(
      id: developerLogsId,
      displayName: 'Developer tool logs',
      description: _logsDescription,
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final folder in CleanerCacheRules.editorFolders)
          _cache('HOME', 'Library/Application Support/$folder/logs', [folder]),
        _cache('HOME', '.npm/_logs', ['npm'], globs: ['*.log']),
        _cache('HOME', '.gradle/daemon', _gradleHints, globs: ['*.out.log']),
        _cache(
          'HOME',
          'Library/Application Support/kotlin/daemon',
          ['Kotlin'],
          globs: ['*.log'],
        ),
      ],
    ),
    CleanerCategory(
      id: 'electron_crash_reports',
      displayName: 'Electron crash reports',
      description:
          'Crashpad minidumps unchanged for a week. They are diagnostic evidence, not app data. Keep reports still needed for troubleshooting; close the affected apps first.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        for (final (folder, hints) in CleanerCacheRules.electronApps)
          for (final reports in ['reports', 'pending', 'completed'])
            _cache(
              'HOME',
              'Library/Application Support/$folder/Crashpad/$reports',
              hints,
              globs: ['*.dmp'],
            ),
      ],
    ),
  ];

  static const _logsDescription =
      'Editor session logs, npm debug logs and Gradle/Kotlin daemon logs unchanged for a week. Keep logs still needed for troubleshooting. Settings, extensions and projects are kept.';

  /// Same layout on Windows (under USERPROFILE) and Linux (under HOME).
  /// Gradle keeps the unpacked distribution next to its zip and only needs the
  /// zip before unpacking; the `.ok` marker and unpacked folder stay.
  static List<CleanerPathRule> _sharedDownloads(String home) => [
    _cache(home, '.android/cache', ['Android SDK', 'Android Studio']),
    _cache(home, '.gradle/wrapper/dists', _gradleHints, globs: ['*.zip']),
    _cache(home, '.rustup/downloads', _rustupHints),
    _cache(home, '.rustup/tmp', _rustupHints),
  ];

  static CleanerPathRule _cache(
    String env,
    String path,
    List<String> hints, {
    List<String>? globs,
  }) => CleanerPathRule(
    source: PathSource.env(env, path),
    minAge: minAge,
    excludeGlobs: _locks,
    includeGlobs: globs,
    appOwnerHints: hints,
    storageKind: AppStorageKind.cache,
  );

  static CleanerPathRule _summary(PathSource source) =>
      CleanerPathRule(source: source, scope: CleanerRuleScope.folderSummary);
  static CleanerCategory _review(
    String id,
    String title,
    List<CleanerPathRule> rules,
  ) => CleanerCategory(
    id: id,
    displayName: title,
    description:
        'Inspection only. This category is never selected for cleanup.',
    safety: CleanerSafety.careful,
    reviewOnly: true,
    rules: rules,
  );

  /// Whether [path] sits under a rule of [categoryId] and, for rules limited
  /// by file name, also matches one of the rule's globs.
  static bool matchesCleanablePath(String categoryId, String path) {
    final normalized = '/${path.replaceAll(r'\', '/').toLowerCase()}/';
    final name = normalized
        .split('/')
        .lastWhere((part) => part.isNotEmpty, orElse: () => '');
    for (final category in [...windows, ...linux, ...macos]) {
      if (category.id != categoryId || category.reviewOnly) continue;
      for (final rule in category.rules) {
        if (!normalized.contains('/${rule.source.relative.toLowerCase()}/')) {
          continue;
        }
        final globs = rule.includeGlobs;
        if (globs == null || globs.any((glob) => _glob(glob).hasMatch(name))) {
          return true;
        }
      }
    }
    return false;
  }

  static final _globCache = <String, RegExp>{};

  static RegExp _glob(String glob) => _globCache.putIfAbsent(
    glob,
    () => RegExp(
      '^${glob.toLowerCase().split('*').map((part) => RegExp.escape(part).replaceAll(r'\?', '.')).join('.*')}\$',
    ),
  );
}

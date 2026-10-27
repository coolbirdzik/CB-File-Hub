import '../app_insights/app_insights_models.dart';
import 'cleaner_cache_rules.dart';
import 'cleaner_models.dart';

/// Narrow default locations verified by the Windows metadata audit.
abstract final class CleanerAuditedRules {
  static const minAge = Duration(days: 7);
  static const _locks = ['LOCK', '*.lock', '*.lck', '*.tmp', '*.partial'];
  static const cleanableIds = {
    'developer_analysis_cache',
    'developer_download_cache',
    'electron_crash_reports',
  };

  static final windows = <CleanerCategory>[
    CleanerCategory(
      id: 'developer_analysis_cache',
      displayName: 'Developer analysis and build caches',
      description:
          'Old Dart analysis, C/C++ precompiled headers and Go build caches. Close editors, language servers and builds first. The next analysis/build may take longer.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        _cache('LOCALAPPDATA', '.dartServer/.analysis-driver', ['Dart']),
        _cache('USERPROFILE', '.dartServer/.analysis-driver', ['Dart']),
        _cache('LOCALAPPDATA', 'Microsoft/vscode-cpptools/ipch', [
          'Visual Studio Code',
        ]),
        _cache('LOCALAPPDATA', 'go-build', ['Go']),
      ],
    ),
    CleanerCategory(
      id: 'developer_download_cache',
      displayName: 'Developer tool downloads',
      description:
          'Old cached VSIX installers, Comfy Desktop archives, node-gyp headers and Electron build tools. Finish installs/updates/builds first. Later installs may need internet; installed extensions, environments and models are kept.',
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

  static bool matchesCleanablePath(String categoryId, String path) {
    final normalized = '/${path.replaceAll(r'\', '/').toLowerCase()}/';
    for (final category in windows) {
      if (category.id != categoryId || category.reviewOnly) continue;
      for (final rule in category.rules) {
        if (normalized.contains('/${rule.source.relative.toLowerCase()}/')) {
          return true;
        }
      }
    }
    return false;
  }
}

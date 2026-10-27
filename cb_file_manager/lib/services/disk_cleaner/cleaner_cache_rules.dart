import '../app_insights/app_insights_models.dart';
import 'cleaner_models.dart';

/// Regenerable caches, deliberately separate from installed dependencies.
/// See docs/features/05-ai-agent.md for the upstream cache contracts.
abstract final class CleanerCacheRules {
  static const downloadMinAge = Duration(days: 7);
  static const _locks = ['LOCK', '*.lock', '*.lck'];

  static final List<CleanerCategory> windows = [
    const CleanerCategory(
      id: 'system_cache',
      displayName: 'Windows shader cache',
      description:
          'Old DirectX shader cache. Games may compile shaders again on their next launch.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        CleanerPathRule(
          source: PathSource.env('LOCALAPPDATA', 'D3DSCache'),
          excludeGlobs: _locks,
          minAge: downloadMinAge,
          appOwnerHints: ['Windows'],
          storageKind: AppStorageKind.cache,
        ),
      ],
    ),
    _downloads(isMacOS: false),
    _electron(isMacOS: false),
  ];

  static final List<CleanerCategory> macos = [
    _downloads(isMacOS: true),
    _electron(isMacOS: true),
  ];

  static CleanerCategory _downloads({required bool isMacOS}) => CleanerCategory(
    id: 'package_download_cache',
    displayName: 'Package download caches',
    description:
        'npm, pip, Cargo, NuGet HTTP and Composer download caches. Future installs may need a network connection; installed libraries are kept.',
    safety: CleanerSafety.safe,
    defaultEnabled: true,
    rules: [
      if (isMacOS) ...[
        _download('HOME', '.npm/_cacache', 'npm'),
        _download('HOME', 'Library/Caches/pip', 'pip'),
        _download('HOME', '.cargo/registry/cache', 'Cargo'),
        _download('HOME', '.local/share/NuGet/v3-cache', 'NuGet'),
        _download('HOME', 'Library/Caches/composer/files', 'Composer'),
      ] else ...[
        _download('LOCALAPPDATA', 'npm-cache/_cacache', 'npm'),
        _download('APPDATA', 'npm-cache/_cacache', 'npm'),
        _download('USERPROFILE', '.npm/_cacache', 'npm'),
        _download('LOCALAPPDATA', 'pip/Cache', 'pip'),
        _download('USERPROFILE', '.cargo/registry/cache', 'Cargo'),
        _download('LOCALAPPDATA', 'NuGet/v3-cache', 'NuGet'),
        _download('LOCALAPPDATA', 'Composer/files', 'Composer'),
      ],
    ],
  );

  static CleanerPathRule _download(String env, String relative, String owner) =>
      CleanerPathRule(
        source: PathSource.env(env, relative),
        excludeGlobs: _locks,
        minAge: downloadMinAge,
        appOwnerHints: [owner],
        storageKind: AppStorageKind.cache,
      );

  // Session data also contains credentials, IndexedDB, service-worker offline
  // data and drafts. Never scan an entire Electron profile or CacheStorage.
  static const _electronCacheFolders = [
    'Cache',
    'Code Cache',
    'GPUCache',
    'DawnCache',
    'DawnGraphiteCache',
    'DawnWebGPUCache',
    'GrShaderCache',
    'ShaderCache',
    'GraphiteDawnCache',
  ];

  static const electronApps = <(String, List<String>)>[
    ('discord', ['Discord', 'discord.exe']),
    ('discordptb', ['Discord PTB', 'discordptb.exe']),
    ('discordcanary', ['Discord Canary', 'discordcanary.exe']),
    ('Slack', ['Slack', 'slack.exe']),
    ('Code', ['Microsoft Visual Studio Code', 'code.exe']),
    ('Code - Insiders', ['Visual Studio Code - Insiders', 'code-insiders.exe']),
    ('Cursor', ['Cursor', 'cursor.exe']),
    ('Windsurf', ['Windsurf', 'windsurf.exe']),
    ('Notion', ['Notion', 'notion.exe']),
    ('obsidian', ['Obsidian', 'obsidian.exe']),
    ('Postman', ['Postman', 'postman.exe']),
    ('Figma', ['Figma', 'figma.exe']),
    ('Signal', ['Signal', 'signal.exe']),
    ('GitHub Desktop', ['GitHub Desktop', 'GitHubDesktop.exe']),
    ('Antigravity', ['Antigravity', 'antigravity.exe']),
    ('Antigravity IDE', ['Antigravity IDE']),
    ('Kiro', ['Kiro', 'kiro.exe']),
    ('ZCode', ['ZCode', 'zcode.exe']),
    ('CodeRabbit', ['CodeRabbit']),
    ('Devin', ['Devin']),
    ('Comfy Desktop', ['Comfy Desktop']),
    ('ComfyUI', ['ComfyUI']),
    ('CurseForge', ['CurseForge']),
    ('WeMod', ['WeMod', 'wemod.exe']),
    ('Sims 4 Mod Manager', ['Sims 4 Mod Manager']),
    ('SideQuest', ['SideQuest']),
    ('Docker Desktop', ['Docker Desktop']),
    ('Riot Client', ['Riot Client']),
    ('riot-client-ux', ['Riot Client']),
    ('UnityHub', ['Unity Hub']),
    ('PikPak', ['PikPak', 'pikpak.exe']),
    ('LM Studio', ['LM Studio']),
    ('CherryStudio', ['Cherry Studio']),
    ('anythingllm-desktop', ['AnythingLLM']),
    ('TagSpaces', ['TagSpaces']),
    ('TagStudio', ['TagStudio']),
    ('Termius', ['Termius']),
    ('TeraBox', ['TeraBox']),
  ];

  static const editorFolders = {
    'Code',
    'Code - Insiders',
    'Cursor',
    'Windsurf',
    'Antigravity',
    'Antigravity IDE',
    'Kiro',
    'ZCode',
    'CodeRabbit',
    'Devin',
  };

  // Already covered by app_cache on Windows. Do not emit a second category
  // for the same path: App Insights matches its category to the scan tree.
  static const _existingWindowsAppCache = {
    'discord/cache',
    'discord/code cache',
    'slack/cache',
    'slack/code cache',
    'code/cache',
    'code/code cache',
    'code/cacheddata',
  };

  static CleanerCategory _electron({required bool isMacOS}) => CleanerCategory(
    id: 'electron_cache',
    displayName: 'Electron app caches',
    description:
        'Web, JavaScript and GPU caches in known Electron apps. Close these apps before cleaning; their caches rebuild on launch.',
    safety: CleanerSafety.safe,
    defaultEnabled: true,
    rules: [
      for (final (folder, hints) in electronApps)
        for (final cache in [
          ..._electronCacheFolders,
          if (editorFolders.contains(folder)) 'CachedData',
        ])
          if (isMacOS ||
              !_existingWindowsAppCache.contains(
                '$folder/$cache'.toLowerCase(),
              ))
            CleanerPathRule(
              source: isMacOS
                  ? PathSource.env(
                      'HOME',
                      'Library/Application Support/$folder/$cache',
                    )
                  : PathSource.env('APPDATA', '$folder/$cache'),
              excludeGlobs: _locks,
              minAge: const Duration(days: 1),
              appOwnerHints: hints,
              storageKind: AppStorageKind.cache,
            ),
    ],
  );

  /// Additional validation for items carrying one of these category IDs.
  /// Segment boundaries keep siblings and installed dependency folders out.
  static bool matchesPath(String categoryId, String path) {
    final parts = _segments(path);
    final byFolder = _patterns[categoryId];
    if (byFolder == null) return false;
    for (var end = 0; end < parts.length - 1; end++) {
      for (final suffix in byFolder[parts[end]] ?? const <List<String>>[]) {
        final start = end - suffix.length + 1;
        if (start >= 0) {
          var matches = true;
          for (var j = 0; j < suffix.length; j++) {
            if (parts[start + j] != suffix[j]) {
              matches = false;
              break;
            }
          }
          if (matches) return true;
        }
      }
    }
    return false;
  }

  // Compile once and look up by cache-folder name, rather than splitting and
  // comparing every rule again for every file in a large npm/pip cache.
  static final _patterns = () {
    final result = <String, Map<String, List<List<String>>>>{};
    for (final category in [...windows, ...macos]) {
      final byFolder = result.putIfAbsent(category.id, () => {});
      for (final rule in category.rules) {
        final parts = _segments(rule.source.relative);
        byFolder.putIfAbsent(parts.last, () => []).add(parts);
      }
    }
    return result;
  }();

  static List<String> _segments(String path) => path
      .toLowerCase()
      .split(RegExp(r'[\\/]'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

import 'cleaner_models.dart';

/// Declarative table of all junk categories the cleaner knows about.
///
/// Add a new category by appending an entry here — the AI tools, the
/// `CbAgentCleanerScreen` UI, and the safety check all read from this single
/// list, so wiring stays minimal.
///
/// All paths target Windows. The cleaner is currently Windows-only.
class CleanerCategories {
  CleanerCategories._();

  /// All known categories.
  static List<CleanerCategory> all() => List.unmodifiable(_all);

  /// Lookup by [CleanerCategory.id]. Returns null if missing.
  static CleanerCategory? byId(String id) {
    for (final c in _all) {
      if (c.id == id) return c;
    }
    return null;
  }

  static final List<CleanerCategory> _all = [
    // -----------------------------------------------------------------------
    // 1. Windows %TEMP%
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'windows_temp',
      displayName: 'Windows temporary files',
      description: 'Files in your %TEMP% folders that apps left behind.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        CleanerPathRule(source: PathSource.env('TEMP')),
        CleanerPathRule(source: PathSource.env('TMP')),
        CleanerPathRule(source: PathSource.env('LOCALAPPDATA', 'Temp')),
      ],
    ),

    // -----------------------------------------------------------------------
    // 2. Browser caches
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'browser_cache',
      displayName: 'Browser caches',
      description:
          'Edge, Chrome, Firefox, Brave, and Opera disk caches. Browsers will rebuild them on demand.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        // Edge
        CleanerPathRule(
          source: PathSource.env(
              'LOCALAPPDATA', r'Microsoft\Edge\User Data\Default\Cache'),
        ),
        CleanerPathRule(
          source: PathSource.env(
              'LOCALAPPDATA', r'Microsoft\Edge\User Data\Default\Code Cache'),
        ),
        // Chrome
        CleanerPathRule(
          source: PathSource.env(
              'LOCALAPPDATA', r'Google\Chrome\User Data\Default\Cache'),
        ),
        CleanerPathRule(
          source: PathSource.env(
              'LOCALAPPDATA', r'Google\Chrome\User Data\Default\Code Cache'),
        ),
        // Brave
        CleanerPathRule(
          source: PathSource.env('LOCALAPPDATA',
              r'BraveSoftware\Brave-Browser\User Data\Default\Cache'),
        ),
        // Opera
        CleanerPathRule(
          source: PathSource.env(
              'APPDATA', r'Opera Software\Opera Stable\Cache'),
        ),
        // Firefox cache2 lives under Profiles\<random>.default\cache2
        // The scanner will recurse so pointing at the parent is enough.
        CleanerPathRule(
          source: PathSource.env('LOCALAPPDATA', r'Mozilla\Firefox\Profiles'),
          includeGlobs: ['*'],
        ),
      ],
    ),

    // -----------------------------------------------------------------------
    // 3. Recycle Bin
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'recycle_bin',
      displayName: 'Recycle Bin',
      description: 'Empty the Recycle Bin on every fixed drive.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        CleanerPathRule(source: PathSource.recycleBin()),
      ],
    ),

    // -----------------------------------------------------------------------
    // 4. Thumbnail / icon cache
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'thumbnail_cache',
      displayName: 'Thumbnail and icon cache',
      description: 'Explorer thumbnail and icon cache databases.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        CleanerPathRule(
          source:
              PathSource.env('LOCALAPPDATA', r'Microsoft\Windows\Explorer'),
          includeGlobs: ['thumbcache_*.db', 'iconcache_*.db', 'IconCache.db'],
          recursive: false,
        ),
      ],
    ),

    // -----------------------------------------------------------------------
    // 5. App caches (Discord, Spotify, Teams, VSCode, Slack, Zoom)
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'app_cache',
      displayName: 'App caches',
      description:
          'Caches from Discord, Spotify, Teams, VSCode, Slack, and Zoom.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        // Discord
        CleanerPathRule(source: PathSource.env('APPDATA', r'discord\Cache')),
        CleanerPathRule(
            source: PathSource.env('APPDATA', r'discord\Code Cache')),
        // Spotify
        CleanerPathRule(
            source: PathSource.env('LOCALAPPDATA', r'Spotify\Storage')),
        CleanerPathRule(source: PathSource.env('LOCALAPPDATA', r'Spotify\Data')),
        // Teams (new + classic)
        CleanerPathRule(
          source: PathSource.env('APPDATA',
              r'Microsoft\Teams\Service Worker\CacheStorage'),
        ),
        CleanerPathRule(source: PathSource.env('APPDATA', r'Microsoft\Teams\Cache')),
        // VSCode
        CleanerPathRule(source: PathSource.env('APPDATA', r'Code\Cache')),
        CleanerPathRule(source: PathSource.env('APPDATA', r'Code\CachedData')),
        CleanerPathRule(source: PathSource.env('APPDATA', r'Code\Code Cache')),
        // Slack
        CleanerPathRule(source: PathSource.env('APPDATA', r'Slack\Cache')),
        CleanerPathRule(source: PathSource.env('APPDATA', r'Slack\Code Cache')),
        // Zoom
        CleanerPathRule(source: PathSource.env('APPDATA', r'Zoom\data')),
      ],
    ),

    // -----------------------------------------------------------------------
    // 6. Crash dumps + old logs
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'crash_dumps_logs',
      displayName: 'Crash dumps and old logs',
      description:
          'CrashDumps, Windows Error Reporting, and *.log files older than 7 days under AppData.',
      safety: CleanerSafety.safe,
      defaultEnabled: true,
      rules: [
        CleanerPathRule(source: PathSource.env('LOCALAPPDATA', 'CrashDumps')),
        CleanerPathRule(
          source: PathSource.env('LOCALAPPDATA', r'Microsoft\Windows\WER'),
        ),
        CleanerPathRule(
          source: PathSource.env('APPDATA'),
          includeGlobs: ['*.log', '*.log.old'],
          minAge: Duration(days: 7),
        ),
        CleanerPathRule(
          source: PathSource.env('LOCALAPPDATA'),
          includeGlobs: ['*.log', '*.log.old'],
          minAge: Duration(days: 7),
        ),
      ],
    ),

    // -----------------------------------------------------------------------
    // 7. Windows Update download cache
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'windows_update_cache',
      displayName: 'Windows Update cache',
      description:
          r'C:\Windows\SoftwareDistribution\Download — re-downloaded next time Update runs.',
      safety: CleanerSafety.careful,
      defaultEnabled: false,
      requiresAdmin: true,
      rules: [
        CleanerPathRule(
          source: PathSource.absolute(r'C:\Windows\SoftwareDistribution\Download'),
        ),
      ],
    ),

    // -----------------------------------------------------------------------
    // 8. Prefetch
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'prefetch',
      displayName: 'Prefetch',
      description:
          r'C:\Windows\Prefetch *.pf files. Windows will rebuild over time.',
      safety: CleanerSafety.careful,
      defaultEnabled: false,
      requiresAdmin: true,
      rules: [
        CleanerPathRule(
          source: PathSource.absolute(r'C:\Windows\Prefetch'),
          includeGlobs: ['*.pf'],
          recursive: false,
        ),
      ],
    ),

    // -----------------------------------------------------------------------
    // 9. Delivery Optimization cache
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'delivery_optimization',
      displayName: 'Delivery Optimization',
      description:
          r'C:\Windows\SoftwareDistribution\DeliveryOptimization — peer-to-peer update payloads.',
      safety: CleanerSafety.careful,
      defaultEnabled: false,
      requiresAdmin: true,
      rules: [
        CleanerPathRule(
          source: PathSource.absolute(
              r'C:\Windows\SoftwareDistribution\DeliveryOptimization'),
        ),
      ],
    ),

    // -----------------------------------------------------------------------
    // 10. Developer caches (npm / pnpm / yarn / pip / gradle / .m2 / cargo /
    //     NuGet)
    // -----------------------------------------------------------------------
    const CleanerCategory(
      id: 'dev_cache',
      displayName: 'Developer caches',
      description:
          'npm, pnpm, yarn, pip, gradle, Maven (.m2), cargo, and NuGet caches. Re-downloads on next build.',
      safety: CleanerSafety.risky,
      defaultEnabled: false,
      rules: [
        CleanerPathRule(source: PathSource.env('APPDATA', r'npm-cache')),
        CleanerPathRule(source: PathSource.env('LOCALAPPDATA', r'npm-cache')),
        CleanerPathRule(source: PathSource.env('LOCALAPPDATA', r'pnpm-cache')),
        CleanerPathRule(source: PathSource.env('LOCALAPPDATA', r'Yarn\Cache')),
        CleanerPathRule(source: PathSource.env('LOCALAPPDATA', r'pip\Cache')),
        CleanerPathRule(source: PathSource.env('USERPROFILE', r'.gradle\caches')),
        CleanerPathRule(
            source: PathSource.env('USERPROFILE', r'.m2\repository')),
        CleanerPathRule(
            source: PathSource.env('USERPROFILE', r'.cargo\registry\cache')),
        CleanerPathRule(
            source: PathSource.env('USERPROFILE', r'.nuget\packages')),
      ],
    ),
  ];
}

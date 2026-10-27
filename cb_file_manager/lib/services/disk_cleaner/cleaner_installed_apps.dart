import '../app_insights/app_insights_models.dart';

/// Installed apps looked up by exact names, for labelling junk files.
///
/// Unlike `AppTokenIndex`, which leans towards a match so leftover detection
/// keeps live data, this only matches exactly: a wrong label tells the user
/// the wrong app made a file. Names shared by two apps are dropped, and
/// generic folder words (cache, data, setup, microsoft…) are never matched.
class CleanerInstalledApps {
  /// Full name tokens and install-folder / package names, three letters or
  /// more. A null value marks a name shared by several apps.
  final Map<String, InstalledAppInfo?> _names = {};

  /// Each app's brand word of four letters or more: its first non-generic
  /// word (`docker` for `Docker Desktop`). Only one word per app, so
  /// `Studio`, `Device` or `Reader` in a file name do not pick an app that
  /// merely has it, and a brand two apps share (`Corsair …`) names neither.
  final Map<String, InstalledAppInfo?> _words = {};

  /// Three-letter brand words (`WPS`, `Bun`) and acronyms (`IDM`).
  final Map<String, InstalledAppInfo?> _short = {};

  final Map<String, InstalledAppInfo?> _exes = {};

  /// Executable names without `.exe`, matched only against a whole folder or
  /// file name: Android Studio's `studio.exe` must not claim every
  /// `VisualStudio` log.
  final Map<String, InstalledAppInfo?> _exeStems = {};

  /// Lower-case install folders, without a trailing separator.
  final Map<String, InstalledAppInfo?> _roots = {};

  /// Memoised [byName] results; %TEMP% repeats the same folder names a lot.
  final Map<String, InstalledAppInfo?> _byNameCache = {};

  final bool isEmpty;

  CleanerInstalledApps(List<InstalledAppInfo> apps) : isEmpty = apps.isEmpty {
    for (final app in apps) {
      final name = _stripVersion(app.displayName);
      final fullTokens = <String>{
        _token(name),
        _token(_withoutLeadingGeneric(name)),
        _basenameToken(app.installLocation),
        ..._packageTokens(app.packageFamilyName),
      }..removeWhere((t) => t.length < 3 || _generic.contains(t));
      for (final token in fullTokens) {
        _add(_names, token, app);
      }
      for (final exe in app.executablePaths) {
        final stem = _basenameToken(exe, stripExtension: true);
        if (stem.length >= 3 && !_generic.contains(stem)) {
          _add(_exeStems, stem, app);
        }
      }

      final brand = _brandWord(name);
      if (brand != null) _add(brand.length == 3 ? _short : _words, brand, app);
      final acronym = _acronym(name);
      if (acronym.length >= 3) _add(_short, acronym, app);

      for (final exe in app.executablePaths) {
        final base = _basename(exe).toLowerCase();
        if (base.endsWith('.exe')) _add(_exes, base, app);
      }
      final root = _installRoot(app.installLocation);
      if (root != null) _add(_roots, root, app);
    }
  }

  static void _add(
    Map<String, InstalledAppInfo?> map,
    String key,
    InstalledAppInfo app,
  ) {
    if (!map.containsKey(key)) {
      map[key] = app;
      return;
    }
    final current = map[key];
    // The same app listed twice (HKLM and HKCU, Win32 and MSIX) is still
    // one app.
    if (current != null && _identity(current) != _identity(app)) {
      map[key] = null;
    }
  }

  static String _identity(InstalledAppInfo app) =>
      _token(_stripVersion(app.displayName));

  /// The app whose whole name, install folder or package is [name], ignoring
  /// case, spaces and punctuation. No word or suffix matching.
  InstalledAppInfo? byExactName(String name) {
    final token = _token(name);
    return token.length < 3 ? null : _names[token];
  }

  /// The app whose executable is [exeName] (`chrome.exe`).
  InstalledAppInfo? byExe(String exeName) => _exes[exeName.toLowerCase()];

  /// The app installed in a folder holding [lowerSegments].
  InstalledAppInfo? byInstallRoot(List<String> lowerSegments) {
    if (_roots.isEmpty) return null;
    for (var end = lowerSegments.length - 1; end >= 3; end--) {
      final app = _roots[lowerSegments.take(end).join(r'\')];
      if (app != null) return app;
    }
    return null;
  }

  /// The app a folder or file name refers to, or null.
  InstalledAppInfo? byName(String name) {
    if (_byNameCache.containsKey(name)) return _byNameCache[name];
    return _byNameCache[name] = _byName(name);
  }

  InstalledAppInfo? _byName(String name) {
    final stem = name.replaceFirst(
      RegExp(r'\.[a-z0-9]{1,5}$', caseSensitive: false),
      '',
    );
    var token = _token(stem);
    if (token.length < 3 || _generic.contains(token)) return _wordMatch(stem);
    final direct = _lookup(token);
    if (direct != null) return direct;

    // `IDM_Setup_Temp`, `TeraBoxUpdate`.
    var stripped = true;
    while (stripped) {
      stripped = false;
      for (final suffix in _suffixes) {
        if (token.endsWith(suffix) && token.length - suffix.length >= 3) {
          token = token.substring(0, token.length - suffix.length);
          final hit = _lookup(token);
          if (hit != null) return hit;
          stripped = true;
          break;
        }
      }
    }
    return _wordMatch(stem);
  }

  InstalledAppInfo? _lookup(String token) {
    if (token.length == 3) {
      return _names[token] ?? _short[token] ?? _exeStems[token];
    }
    return _names[token] ?? _exeStems[token];
  }

  /// `…stable_01-WarpSetup` → Warp, `.bun-1804…` → Bun. The first word
  /// that names one app wins. Three-letter words only count when they stand
  /// alone between separators: `VSGitHubCopilot` is not Git.
  InstalledAppInfo? _wordMatch(String stem) {
    for (final part in _separatorWords(stem)) {
      if (_generic.contains(part)) continue;
      final whole = part.length == 3
          ? _short[part] ?? _names[part]
          : part.length > 3
          ? _names[part] ?? _words[part]
          : null;
      if (whole != null) return whole;
    }
    for (final word in _humpWords(stem)) {
      if (word.length < 4 || _generic.contains(word)) continue;
      final app = _names[word] ?? _words[word];
      if (app != null) return app;
    }
    return null;
  }

  /// [InstalledAppInfo.displayName] without a trailing version or install
  /// scope: `CB File Hub v1.23.1.0` → `CB File Hub`.
  static String displayName(InstalledAppInfo app) {
    final cleaned = _stripVersion(app.displayName).trim();
    return cleaned.isEmpty ? app.displayName : cleaned;
  }

  // ---------------------------------------------------------------------------
  // Tokens
  // ---------------------------------------------------------------------------

  static String _token(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static final RegExp _humpPattern = RegExp(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+');

  /// Lower-case letter words split at camelCase humps too: `WarpSetup`.
  static Iterable<String> _humpWords(String value) =>
      _humpPattern.allMatches(value).map((m) => m.group(0)!.toLowerCase());

  /// Lower-case all-letter words between separators: `IDM_Setup_Temp` →
  /// idm, setup, temp. Parts with digits (`48dac9d9`, `x64`) are skipped, so
  /// hex IDs do not yield words like `dac`.
  static Iterable<String> _separatorWords(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty && !w.contains(RegExp(r'[0-9]')));

  /// The word that names the product: the first non-generic one.
  static String? _brandWord(String name) {
    for (final word in _separatorWords(name)) {
      if (word.length >= 3 && !_generic.contains(word)) return word;
    }
    return null;
  }

  static String _stripVersion(String value) => value
      .replaceAll(
        RegExp(
          r'\s*\((user|machine|x64|x86|arm64|64-bit|32-bit|remove only)\)\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'\s+v?\d+(\.\d+)+[a-z0-9.-]*\s*$', caseSensitive: false),
        '',
      )
      .trim();

  /// `Microsoft Visual Studio Code` → `Visual Studio Code`.
  static String _withoutLeadingGeneric(String name) {
    final parts = name.split(RegExp(r'\s+'));
    var start = 0;
    while (start < parts.length - 1 &&
        _generic.contains(parts[start].toLowerCase())) {
      start++;
    }
    return parts.skip(start).join(' ');
  }

  static String _acronym(String name) {
    final words = name
        .split(RegExp(r'[^A-Za-z]+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    if (words.length < 3) return '';
    return words.map((w) => w[0].toLowerCase()).join();
  }

  static Iterable<String> _packageTokens(String? family) sync* {
    final name = family?.split('_').first.trim();
    if (name == null || name.isEmpty) return;
    yield _token(name);
    final parts = name.split('.');
    // `Microsoft.WindowsTerminal` → `windowsterminal`.
    if (parts.length > 1) yield _token(parts.skip(1).join());
  }

  static String _basename(String path) => path
      .replaceAll('"', '')
      .replaceFirst(RegExp(r',\s*-?\d+$'), '')
      .split(RegExp(r'[\\/]'))
      .lastWhere((s) => s.isNotEmpty, orElse: () => '');

  static String _basenameToken(String? path, {bool stripExtension = false}) {
    if (path == null || path.trim().isEmpty) return '';
    var name = _basename(path.trim());
    if (stripExtension) name = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return _token(name);
  }

  /// An install folder specific enough to own the files below it. Registry
  /// values like `C:\`, the profile or `AppData\Local\Programs` are not.
  static String? _installRoot(String? location) {
    if (location == null) return null;
    final segments = location
        .replaceAll('"', '')
        .trim()
        .toLowerCase()
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.length < 3) return null;
    final last = segments.last;
    if (_baseFolders.contains(last)) return null;
    if (segments.length == 3 && segments[1] == 'users') return null;
    if (segments.length <= 5 &&
        segments.contains('appdata') &&
        (last == 'local' || last == 'roaming' || last == 'programs')) {
      return null;
    }
    return segments.join(r'\');
  }

  static const Set<String> _baseFolders = {
    'appdata',
    'local',
    'locallow',
    'roaming',
    'programs',
    'temp',
    'program files',
    'program files (x86)',
    'programdata',
    'windows',
    'system32',
    'users',
  };

  /// Trailing words a scratch folder adds to an app name.
  static const List<String> _suffixes = [
    'setup',
    'installer',
    'install',
    'updater',
    'updates',
    'update',
    'temp',
    'tmp',
    'cache',
    'logs',
    'log',
    'data',
    'files',
  ];

  /// Folder words that name no particular app.
  static const Set<String> _generic = {
    'agent',
    'app',
    'apps',
    'application',
    'applications',
    'appdata',
    'assets',
    'beta',
    'bin',
    'blob',
    'browser',
    'build',
    'cache',
    'caches',
    'chromium',
    'client',
    'code',
    'com',
    'common',
    'community',
    'components',
    'config',
    'core',
    'crash',
    'crashes',
    'crashpad',
    'data',
    'debug',
    'default',
    'desktop',
    'diagnostics',
    'driver',
    'drivers',
    'edition',
    'electron',
    'enterprise',
    'extension',
    'extensions',
    'file',
    'files',
    'free',
    'google',
    'helper',
    'helpers',
    'index',
    'insiders',
    'install',
    'installer',
    'lib',
    'libs',
    'local',
    'log',
    'logs',
    'manager',
    'media',
    'microsoft',
    'msi',
    'network',
    'nightly',
    'org',
    'output',
    'package',
    'packages',
    'player',
    'plugin',
    'plugins',
    'preview',
    'pro',
    'profile',
    'profiles',
    'program',
    'programs',
    'release',
    'report',
    'reports',
    'resource',
    'resources',
    'roaming',
    'runtime',
    'runtimes',
    'server',
    'service',
    'services',
    'session',
    'settings',
    'setup',
    'shader',
    'shared',
    'software',
    'source',
    'stable',
    'standard',
    'storage',
    'store',
    'support',
    'system',
    'temp',
    'test',
    'tests',
    'the',
    'tmp',
    'tool',
    'tools',
    'update',
    'updater',
    'updates',
    'user',
    'users',
    'version',
    'webview',
    'windows',
    'worker',
    'www',
  };
}

import 'app_insights_models.dart';
import 'app_leftover_finder.dart';

/// A folder whose direct children are checked on macOS or Linux.
class PosixLeftoverBase {
  final AppLeftoverLocation location;
  final String path;

  const PosixLeftoverBase(this.location, this.path);
}

/// Finds leftover app data on macOS and Linux from folder names alone.
///
/// macOS keys most app data by bundle identifier (`com.vendor.App`), which
/// is compared with the installed bundles; plain names are compared with app
/// and command names. On Linux, `~/.var/app` and `~/snap` are compared with
/// `flatpak list` and `snap list`, and the XDG config, data and cache folders
/// with desktop entries, commands on `PATH` and installed packages.
///
/// Like the Windows finder it errs towards "owned": a reverse-DNS name whose
/// vendor still has an installed app is kept, because vendors share
/// containers between their apps.
class PosixAppLeftoverFinder {
  const PosixAppLeftoverFinder();

  static List<PosixLeftoverBase> bases(
    Map<String, String> environment, {
    required String operatingSystem,
  }) {
    final home = environment['HOME'];
    if (home == null || home.isEmpty) return const [];
    String trim(String path) => path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final root = trim(home);
    if (operatingSystem == 'macos') {
      return [
        PosixLeftoverBase(
          AppLeftoverLocation.macContainers,
          '$root/Library/Containers',
        ),
        PosixLeftoverBase(
          AppLeftoverLocation.macGroupContainers,
          '$root/Library/Group Containers',
        ),
        PosixLeftoverBase(
          AppLeftoverLocation.macApplicationSupport,
          '$root/Library/Application Support',
        ),
        PosixLeftoverBase(
          AppLeftoverLocation.macCaches,
          '$root/Library/Caches',
        ),
      ];
    }
    if (operatingSystem == 'linux') {
      String xdg(String key, String fallback) {
        final value = environment[key];
        return value != null && value.startsWith('/')
            ? trim(value)
            : '$root/$fallback';
      }

      return [
        PosixLeftoverBase(
          AppLeftoverLocation.linuxConfig,
          xdg('XDG_CONFIG_HOME', '.config'),
        ),
        PosixLeftoverBase(
          AppLeftoverLocation.linuxData,
          xdg('XDG_DATA_HOME', '.local/share'),
        ),
        PosixLeftoverBase(
          AppLeftoverLocation.linuxCache,
          xdg('XDG_CACHE_HOME', '.cache'),
        ),
        PosixLeftoverBase(AppLeftoverLocation.linuxFlatpak, '$root/.var/app'),
        PosixLeftoverBase(AppLeftoverLocation.linuxSnap, '$root/snap'),
      ];
    }
    return const [];
  }

  /// [listing] holds the child folder names of each base.
  AppLeftoverReport find({
    required List<(PosixLeftoverBase, List<String>)> listing,
    required AppLeftoverInventory inventory,
    Iterable<String> excludedPaths = const <String>[],
    DateTime? generatedAt,
  }) {
    final generated = generatedAt ?? DateTime.now();
    final hasApps = inventory.apps.any(
      (app) => app.source != InstalledAppSource.executable,
    );
    if (!hasApps) {
      return AppLeftoverReport(
        drivePath: '/',
        candidates: const <AppLeftoverCandidate>[],
        generatedAt: generated,
        isPartial: true,
        inventoryUnavailable: true,
      );
    }

    final owners = PosixAppOwnership(inventory.apps);
    final excluded = excludedPaths
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    bool isExcluded(String path) => excluded.any(
      (other) =>
          path == other ||
          other.startsWith('$path/') ||
          path.startsWith('$other/'),
    );

    bool owned(AppLeftoverLocation location, String name) {
      switch (location) {
        case AppLeftoverLocation.linuxFlatpak:
          return inventory.flatpakApps!.contains(name);
        case AppLeftoverLocation.linuxSnap:
          return inventory.snaps!.contains(name) || name == 'bin';
        default:
          return owners.of(location, name).kind != AppFolderOwnerKind.none;
      }
    }

    final candidates = <AppLeftoverCandidate>[];
    for (final (base, names) in listing) {
      if (base.location == AppLeftoverLocation.linuxFlatpak &&
          inventory.flatpakApps == null) {
        continue;
      }
      if (base.location == AppLeftoverLocation.linuxSnap &&
          inventory.snaps == null) {
        continue;
      }
      for (final name in names) {
        if (name.isEmpty || name.startsWith('.')) continue;
        final path = '${base.path}/$name';
        if (isExcluded(path) || owned(base.location, name)) continue;
        candidates.add(
          AppLeftoverCandidate(
            path: path,
            displayName: name,
            location: base.location,
            reason: AppLeftoverReason.noInstalledApp,
            sizeBytes: 0,
          ),
        );
      }
    }
    return AppLeftoverReport(
      drivePath: '/',
      candidates: candidates,
      generatedAt: generated,
      isPartial: inventory.isPartial,
    );
  }

  static const Set<String> _topLevelDomains = <String>{
    'com',
    'org',
    'net',
    'io',
    'app',
    'dev',
    'me',
    'co',
    'de',
    'uk',
    'fr',
    'jp',
    'cn',
    'ru',
    'nl',
    'se',
    'ch',
    'at',
    'it',
    'es',
    'br',
    'in',
    'ca',
    'us',
    'au',
    'info',
    'edu',
    'tv',
    'ai',
    'so',
    'sh',
    'cc',
    'eu',
    'pl',
    'cz',
    'kr',
    'tw',
    'vn',
    'fi',
    'no',
    'dk',
    'be',
    'pt',
    'gg',
    'xyz',
    'tech',
  };

  /// `com.vendor.App`-style names (two or more segments after a known
  /// top-level domain).
  static bool isReverseDns(String name) {
    final parts = name.split('.');
    if (parts.length < 2 || parts.any((part) => part.isEmpty)) return false;
    return _topLevelDomains.contains(parts.first.toLowerCase());
  }

  /// `group.com.vendor.app` and `TEAMID1234.com.vendor.app` → the bundle id
  /// part. Apple's own groups return null so they are never reported.
  static String? groupContainerBundleId(String name) {
    var id = name;
    if (id.startsWith('group.')) id = id.substring('group.'.length);
    final team = RegExp(r'^[A-Z0-9]{10}\.').firstMatch(id);
    if (team != null) id = id.substring(team.end);
    if (id.toLowerCase().contains('apple')) return null;
    return isReverseDns(id) ? id : null;
  }

  static bool _isIgnoredMacName(String name) {
    final lower = name.toLowerCase();
    if (lower.startsWith('com.apple.') || lower.contains('apple')) {
      return true;
    }
    if (_ignoredPrefixes.any(lower.startsWith)) return true;
    // System daemons keep folders named after themselves (`routined`).
    if (RegExp(r'^[a-z]{3,24}d$').hasMatch(name)) return true;
    return _ignoredMacNames.contains(lower);
  }

  static bool _isIgnoredLinuxName(String name) {
    final lower = name.toLowerCase();
    if (_ignoredLinuxPrefixes.any(lower.startsWith)) return true;
    if (_ignoredPrefixes.any(lower.startsWith)) return true;
    return _ignoredLinuxNames.contains(lower);
  }

  /// Toolchain caches named after a tool and a variant
  /// (`ms-playwright-go`, `ms-playwright-mcp`).
  static const List<String> _ignoredPrefixes = <String>['ms-playwright'];

  /// macOS system and toolchain folders with plain names.
  static const Set<String> _ignoredMacNames = <String>{
    // macOS frameworks that keep per-user folders.
    'gamekit',
    'temporaryitems',
    // The Go toolchain (`go` is too short to match an installed command).
    'go',
    'goimports',
    // Crash and native-access SDKs embedded in many apps, not one app.
    'sentrycrash',
    'io.sentry',
    'jna',
    // Homebrew's cask downloads.
    'cask',
    'addressbook',
    'animoji',
    'app store',
    'appstore',
    'callhistorydb',
    'callhistorytransactions',
    'clouddocs',
    'cloudkit',
    'controlcenter',
    'coreparsec',
    'crashreporter',
    'diskimages',
    'dock',
    'familycircle',
    'fileprovider',
    'geoservices',
    'icloud',
    'knowledge',
    'mobilesync',
    'passkit',
    'quick look',
    'siritts',
    'syncservices',
    'homebrew',
    'pip',
    'pypoetry',
    'yarn',
    'node-gyp',
    'ms-playwright',
    'go-build',
    'gopls',
    'deno',
    'typescript',
    'cache',
    'caches',
    'temp',
    'tmp',
  };

  static const List<String> _ignoredLinuxPrefixes = <String>[
    'gnome',
    'kde',
    'plasma',
    'xdg',
    'gtk',
    'qt',
    'kf5',
    'kf6',
    'dconf',
    'systemd',
    'pulse',
    'pipewire',
    'ibus',
    'fcitx',
    'gvfs',
    'tracker',
    'mesa',
    'evolution',
    'akonadi',
    'baloo',
    'kwin',
  ];

  /// Desktop, session and toolchain folders shared by many apps.
  static const Set<String> _ignoredLinuxNames = <String>{
    'go',
    'goimports',
    'autostart',
    'applications',
    'backgrounds',
    'cache',
    'dbus-1',
    'desktop-directories',
    'environment.d',
    'flatpak',
    'fontconfig',
    'fonts',
    'goa-1.0',
    'icons',
    'keyrings',
    'menus',
    'mime',
    'nvidia',
    'recently-used.xbel',
    'session',
    'sessions',
    'snap',
    'sounds',
    'themes',
    'thumbnails',
    'trash',
    'user-tmpfiles.d',
    'wireplumber',
    'xorg',
    'pip',
    'pypoetry',
    'yarn',
    'npm',
    'node-gyp',
    'go-build',
    'gopls',
    'deno',
    'ms-playwright',
    'jedi',
    'pre-commit',
    'virtualenv',
    'containers',
    'docker',
    'libvirt',
  };
}

/// Who a folder under one of the [PosixAppLeftoverFinder.bases] belongs to.
enum AppFolderOwnerKind {
  /// One installed app: an exact or nested bundle id, or its name.
  app,

  /// An app of the same vendor (`com.vendor.*`): shared between its apps.
  vendor,

  /// macOS or the desktop itself, a toolchain, or a folder never judged.
  system,

  /// No installed app: what the Leftovers page reports.
  none,
}

class AppFolderOwner {
  final AppFolderOwnerKind kind;

  /// The app for [AppFolderOwnerKind.app] and [AppFolderOwnerKind.vendor].
  final InstalledAppInfo? app;

  const AppFolderOwner(this.kind, [this.app]);

  static const system = AppFolderOwner(AppFolderOwnerKind.system);
  static const none = AppFolderOwner(AppFolderOwnerKind.none);
}

/// Decides which installed app owns a folder name in a base folder. The
/// Leftovers page keeps what has no owner; the App storage page groups the
/// rest by owner, so both read ownership from here.
class PosixAppOwnership {
  final AppTokenIndex _names;
  final _BundleIndex _bundles;

  PosixAppOwnership(List<InstalledAppInfo> apps)
    : _names = AppTokenIndex(apps),
      _bundles = _BundleIndex(apps);

  AppFolderOwner of(AppLeftoverLocation location, String name) {
    switch (location) {
      case AppLeftoverLocation.macContainers:
        // Extension and system containers can have non-bundle names.
        if (!PosixAppLeftoverFinder.isReverseDns(name)) {
          return AppFolderOwner.system;
        }
        return _bundles.owner(name, _names);
      case AppLeftoverLocation.macGroupContainers:
        final id = PosixAppLeftoverFinder.groupContainerBundleId(name);
        if (id == null) return AppFolderOwner.system;
        return _bundles.owner(id, _names);
      case AppLeftoverLocation.macApplicationSupport:
      case AppLeftoverLocation.macCaches:
        if (PosixAppLeftoverFinder._isIgnoredMacName(name)) {
          return AppFolderOwner.system;
        }
        return _byName(name);
      case AppLeftoverLocation.linuxConfig:
      case AppLeftoverLocation.linuxData:
      case AppLeftoverLocation.linuxCache:
        if (PosixAppLeftoverFinder._isIgnoredLinuxName(name)) {
          return AppFolderOwner.system;
        }
        return _byName(name);
      default:
        return AppFolderOwner.system;
    }
  }

  /// Words apps add to their own name for a data folder (`ZaloData` for
  /// Zalo, `SlackCache`).
  static const List<String> _dataSuffixes = <String>[
    'data',
    'caches',
    'cache',
    'support',
    'storage',
    'files',
    'helper',
  ];

  /// A plain name, or a bundle id where one is used.
  AppFolderOwner _byName(String name) {
    if (PosixAppLeftoverFinder.isReverseDns(name)) {
      return _bundles.owner(name, _names);
    }
    final app = _names.matchName(name) ?? _matchWithoutSuffix(_names, name);
    return app == null
        ? AppFolderOwner.none
        : AppFolderOwner(AppFolderOwnerKind.app, app);
  }
}

/// [AppTokenIndex.matchName] of [name] without a trailing data word, so a
/// short app name (`Zalo`, four letters, below the prefix-match length)
/// still owns its `ZaloData` folder.
InstalledAppInfo? _matchWithoutSuffix(AppTokenIndex names, String name) {
  final letters = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  for (final suffix in PosixAppOwnership._dataSuffixes) {
    if (letters.length - suffix.length < 3 || !letters.endsWith(suffix)) {
      continue;
    }
    final app = names.matchName(
      letters.substring(0, letters.length - suffix.length),
    );
    if (app != null) return app;
  }
  return null;
}

/// Installed bundle, desktop-file and Flatpak ids.
class _BundleIndex {
  final Map<String, InstalledAppInfo> _ids = <String, InstalledAppInfo>{};
  final Map<String, InstalledAppInfo> _vendors = <String, InstalledAppInfo>{};

  _BundleIndex(List<InstalledAppInfo> apps) {
    for (final app in apps) {
      final id = app.packageFamilyName?.trim().toLowerCase();
      if (id == null || id.isEmpty) continue;
      _ids.putIfAbsent(id, () => app);
      final vendor = _vendor(id);
      if (vendor != null) _vendors.putIfAbsent(vendor, () => app);
    }
  }

  AppFolderOwner owner(String rawId, AppTokenIndex names) {
    final id = rawId.toLowerCase();
    if (id.startsWith('com.apple.')) return AppFolderOwner.system;
    for (final MapEntry(key: installed, value: app) in _ids.entries) {
      if (id == installed ||
          id.startsWith('$installed.') ||
          installed.startsWith('$id.')) {
        return AppFolderOwner(AppFolderOwnerKind.app, app);
      }
    }
    final vendor = _vendor(id);
    final vendorApp = vendor == null ? null : _vendors[vendor];
    if (vendorApp != null) {
      return AppFolderOwner(AppFolderOwnerKind.vendor, vendorApp);
    }
    // `com.electron.dockerdesktop` for Docker.app, `org.gnome.Gedit` for gedit.
    final last = rawId.substring(rawId.lastIndexOf('.') + 1);
    final named = names.matchName(last);
    return named == null
        ? AppFolderOwner.none
        : AppFolderOwner(AppFolderOwnerKind.app, named);
  }

  /// `com.vendor` from `com.vendor.app`.
  static String? _vendor(String id) {
    final parts = id.split('.');
    if (parts.length < 3) return null;
    return '${parts[0]}.${parts[1]}';
  }
}

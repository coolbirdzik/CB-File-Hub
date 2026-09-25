/// How this copy of the app was installed. It decides where updates come from:
/// the two stores update through their own APIs, the direct downloads through
/// GitHub Releases.
enum AppDistribution {
  microsoftStore,
  googlePlay,

  /// Windows MSI installer (installed under Program Files).
  windowsInstaller,

  /// Windows portable ZIP, run from any writable folder.
  windowsPortable,

  /// macOS app bundle copied out of the release DMG.
  macosDmg,

  /// No supported update path: debug builds, sideloaded APKs, Linux, iOS,
  /// or an app launched straight from the mounted DMG.
  unsupported;

  bool get isStore => this == microsoftStore || this == googlePlay;

  /// Direct downloads we fetch and install ourselves.
  bool get isSelfUpdating =>
      this == windowsInstaller || this == windowsPortable || this == macosDmg;
}

/// A newer release that can be installed.
class AppUpdateInfo {
  /// Display version, e.g. `1.2.0`. Empty when the store does not expose it.
  final String version;

  /// Release notes (Markdown). Empty for store updates.
  final String releaseNotes;

  /// Page describing the release, shown as a fallback link.
  final String? releaseUrl;

  /// Asset to download for self-updating distributions.
  final String? downloadUrl;
  final String? assetName;
  final int? assetSize;

  /// `sha256` hex digest published by GitHub for the asset, when available.
  final String? sha256;

  const AppUpdateInfo({
    required this.version,
    this.releaseNotes = '',
    this.releaseUrl,
    this.downloadUrl,
    this.assetName,
    this.assetSize,
    this.sha256,
  });
}

enum AppUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,

  /// Downloaded and waiting for the user to confirm the install.
  readyToInstall,
  installing,
  error,
}

/// Compares dotted numeric versions (`v1.2.10` > `1.2.9`). A leading `v` and
/// any `+build` / `-pre` suffix are ignored.
int compareVersions(String a, String b) {
  List<int> parse(String value) {
    var core = value.trim();
    if (core.startsWith('v') || core.startsWith('V')) core = core.substring(1);
    core = core.split('+').first.split('-').first;
    return core
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList(growable: false);
  }

  final left = parse(a);
  final right = parse(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

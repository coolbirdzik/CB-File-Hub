import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_update_models.dart';

/// Reads the latest published release from GitHub Releases — the same place
/// the website's Windows and macOS download buttons point at.
class GithubReleaseSource {
  static const String repository = 'coolbirdzik/CB-File-Hub';
  static final Uri latestReleaseUri = Uri.parse(
    'https://api.github.com/repos/$repository/releases/latest',
  );

  final http.Client _client;

  GithubReleaseSource({http.Client? client})
    : _client = client ?? http.Client();

  /// Returns the latest release when it is newer than [currentVersion] and
  /// ships an asset for [distribution]; otherwise `null`.
  Future<AppUpdateInfo?> fetchUpdate({
    required String currentVersion,
    required AppDistribution distribution,
  }) async {
    final response = await _client
        .get(
          latestReleaseUri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'CB-File-Hub-Updater',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'GitHub returned HTTP ${response.statusCode}',
        latestReleaseUri,
      );
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Unexpected release payload');
    }
    return parseRelease(json, currentVersion, distribution);
  }

  static AppUpdateInfo? parseRelease(
    Map<String, dynamic> release,
    String currentVersion,
    AppDistribution distribution,
  ) {
    if (release['draft'] == true || release['prerelease'] == true) return null;
    final tag = (release['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty || compareVersions(tag, currentVersion) <= 0) return null;

    final assets = (release['assets'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    Map<String, dynamic>? asset;
    for (final candidate in assets) {
      final name = candidate['name'] as String? ?? '';
      if (assetMatches(name, distribution)) {
        asset = candidate;
        break;
      }
    }
    if (asset == null) return null;

    final digest = asset['digest'] as String?;
    return AppUpdateInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      releaseNotes: release['body'] as String? ?? '',
      releaseUrl: release['html_url'] as String?,
      downloadUrl: asset['browser_download_url'] as String?,
      assetName: asset['name'] as String?,
      assetSize: (asset['size'] as num?)?.toInt(),
      sha256: digest != null && digest.startsWith('sha256:')
          ? digest.substring('sha256:'.length).toLowerCase()
          : null,
    );
  }

  /// Release asset names come from `.github/workflows/release.yml`.
  static bool assetMatches(String name, AppDistribution distribution) {
    final lower = name.toLowerCase();
    switch (distribution) {
      case AppDistribution.windowsInstaller:
        return lower.endsWith('.msi');
      case AppDistribution.windowsPortable:
        return lower.endsWith('-windows-portable.zip');
      case AppDistribution.macosDmg:
        return lower.endsWith('.dmg');
      case AppDistribution.microsoftStore:
      case AppDistribution.googlePlay:
      case AppDistribution.unsupported:
        return false;
    }
  }
}

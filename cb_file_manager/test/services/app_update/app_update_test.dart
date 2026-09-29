import 'package:cb_file_manager/services/app_update/app_update_models.dart';
import 'package:cb_file_manager/services/app_update/desktop_update_installer.dart';
import 'package:cb_file_manager/services/app_update/github_release_source.dart';
import 'package:cb_file_manager/services/app_update/release_notes.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _release({
  String tag = 'v1.2.0',
  bool prerelease = false,
  String? digest,
}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': prerelease,
  'html_url': 'https://github.com/coolbirdzik/CB-File-Hub/releases/tag/$tag',
  'body': '# 🎉 CB File Hub 1.2.0\n\n## 📝 What\'s Changed\n\n- Fix a bug',
  'assets': [
    {
      'name': 'CBFileHub-1.2.0-arm64-v8a.apk',
      'size': 10,
      'browser_download_url': 'https://example.com/app.apk',
    },
    {
      'name': 'CBFileHub-1.2.0-windows-portable.zip',
      'size': 20,
      'browser_download_url': 'https://example.com/portable.zip',
    },
    {
      'name': 'CBFileHub-Setup-1.2.0.msi',
      'size': 30,
      'browser_download_url': 'https://example.com/setup.msi',
      'digest': ?digest,
    },
    {
      'name': 'CBFileHub-1.2.0-macos.dmg',
      'size': 40,
      'browser_download_url': 'https://example.com/app.dmg',
    },
  ],
};

void main() {
  group('compareVersions', () {
    test('compares numerically, ignoring v prefix and build suffix', () {
      expect(compareVersions('v1.1.10', '1.1.9'), greaterThan(0));
      expect(compareVersions('1.1.10', '1.1.10+5'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.1.10', 'v2.0.0'), lessThan(0));
    });
  });

  group('GithubReleaseSource.parseRelease', () {
    test('picks the asset for each direct-download distribution', () {
      String? url(AppDistribution d) => GithubReleaseSource.parseRelease(
        _release(),
        '1.1.10',
        d,
      )?.downloadUrl;

      expect(
        url(AppDistribution.windowsInstaller),
        'https://example.com/setup.msi',
      );
      expect(
        url(AppDistribution.windowsPortable),
        'https://example.com/portable.zip',
      );
      expect(url(AppDistribution.macosDmg), 'https://example.com/app.dmg');
      expect(url(AppDistribution.googlePlay), isNull);
    });

    test('returns null when the release is not newer', () {
      expect(
        GithubReleaseSource.parseRelease(
          _release(tag: 'v1.1.10'),
          '1.1.10',
          AppDistribution.macosDmg,
        ),
        isNull,
      );
    });

    test('skips pre-releases', () {
      expect(
        GithubReleaseSource.parseRelease(
          _release(prerelease: true),
          '1.0.0',
          AppDistribution.macosDmg,
        ),
        isNull,
      );
    });

    test('reads version, size and sha256 digest', () {
      final info = GithubReleaseSource.parseRelease(
        _release(digest: 'sha256:ABCDEF'),
        '1.0.0',
        AppDistribution.windowsInstaller,
      )!;
      expect(info.version, '1.2.0');
      expect(info.assetSize, 30);
      expect(info.sha256, 'abcdef');
    });
  });

  test('trimReleaseNotes keeps only the change list', () {
    const notes = '''
# 🎉 CB File Hub 1.2.0

## 📝 What's Changed

- Add updater (abc123)

## 📦 Downloads

- **Portable**: zip
''';
    expect(
      trimReleaseNotes(notes),
      "## 📝 What's Changed\n\n- Add updater (abc123)",
    );
  });

  group('parseReleaseChanges', () {
    test('groups conventional commits and drops hashes and CI noise', () {
      const notes = '''
# 🎉 CB File Hub 1.2.0

## 📝 What's Changed

Changes from `v1.1.0` to `v1.2.0`.

- feat(update): show updates in the status center (4b8b237)
- fix: keep macOS permissions after updating (f8a31fe)
- ci: auto bump build number to 2 (7405a9b)
- test: cover the updater (96df98a)
- perf: faster thumbnails (f59793a)
- Tweak spacing by @someone in https://github.com/o/r/pull/12
- feat(update): show updates in the status center (1234567)

## 📦 Downloads

- **Portable**: zip
''';
      expect(parseReleaseChanges(notes), const [
        ReleaseChange(
          ReleaseChangeKind.feature,
          'Show updates in the status center',
        ),
        ReleaseChange(
          ReleaseChangeKind.fix,
          'Keep macOS permissions after updating',
        ),
        ReleaseChange(ReleaseChangeKind.improvement, 'Faster thumbnails'),
        ReleaseChange(ReleaseChangeKind.improvement, 'Tweak spacing'),
      ]);
      expect(releaseNotesHaveList(notes), isTrue);
    });

    test('is empty for prose and for lists of hidden changes only', () {
      expect(parseReleaseChanges('Bug fixes.'), isEmpty);
      expect(releaseNotesHaveList('Bug fixes.'), isFalse);

      const ciOnly = '- ci: bump (abc1234)\n- No commits found';
      expect(parseReleaseChanges(ciOnly), isEmpty);
      expect(releaseNotesHaveList(ciOnly), isTrue);
    });
  });

  group('DesktopUpdateInstaller', () {
    test('finds the macOS app bundle from the executable', () {
      expect(
        DesktopUpdateInstaller.macosBundlePath(
          '/Applications/CB File Hub.app/Contents/MacOS/CB File Hub',
        ),
        '/Applications/CB File Hub.app',
      );
      expect(DesktopUpdateInstaller.macosBundlePath('/usr/bin/tool'), isNull);
    });

    test('MSI script elevates msiexec and relaunches the app', () {
      final script = DesktopUpdateInstaller.buildWindowsScript(
        portable: false,
        processId: 42,
        executablePath: r"C:\Program Files\CB File Hub\cb_file_hub.exe",
        packagePath: r"C:\Temp\O'Brien\CBFileHub-Setup-1.2.0.msi",
        logPath: r'C:\Temp\update.log',
      );
      expect(script, contains(r'$appPid = 42'));
      expect(script, contains("msiexec.exe"));
      expect(script, contains('-Verb RunAs'));
      // Single quotes in paths are doubled inside PowerShell literals.
      expect(script, contains(r"'C:\Temp\O''Brien\CBFileHub-Setup-1.2.0.msi'"));
      expect(script, contains(r'Start-Process -FilePath $exe'));
      expect(script, isNot(contains('robocopy')));
      // An unexpected error must not stop the script before the install.
      expect(script, contains('trap {'));
      // Hidden app processes (the spare window) are closed without waiting.
      expect(script, contains(r'$_.MainWindowHandle -eq 0'));
    });

    test('portable script extracts and copies over the app folder', () {
      final script = DesktopUpdateInstaller.buildWindowsScript(
        portable: true,
        processId: 7,
        executablePath: r'D:\Apps\CBFileHub\cb_file_hub.exe',
        packagePath: r'C:\Temp\CBFileHub-1.2.0-windows-portable.zip',
        logPath: r'C:\Temp\update.log',
      );
      expect(script, contains('Expand-Archive'));
      expect(script, contains(r'robocopy $source $appDir /E'));
      expect(script, isNot(contains('msiexec')));
    });

    test('macOS scripts quote paths and fall back to admin rights', () {
      final replace = DesktopUpdateInstaller.buildMacosReplaceScript(
        bundlePath: "/Applications/Bob's App.app",
        mountPoint: '/tmp/update/mount',
      );
      expect(replace, contains(r"APP='/Applications/Bob'\''s App.app'"));
      expect(replace, contains('ditto "\$SRC" "\$APP.update"'));

      final main = DesktopUpdateInstaller.buildMacosScript(
        processId: 99,
        bundlePath: '/Applications/CB File Hub.app',
        dmgPath: '/tmp/update/CBFileHub-1.2.0-macos.dmg',
        mountPoint: '/tmp/update/mount',
        replaceScriptPath: '/tmp/update/replace_app.sh',
        logPath: '/tmp/update/update.log',
      );
      expect(main, contains('while kill -0 99'));
      expect(main, contains('hdiutil attach -nobrowse -readonly'));
      expect(main, contains('with administrator privileges'));
      expect(main, contains('open "\$APP"'));
    });
  });
}

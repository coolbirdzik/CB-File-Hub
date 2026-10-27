import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_installed_apps.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_item_origin.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:flutter_test/flutter_test.dart';

const String _local = r'C:\Users\me\AppData\Local';
const String _temp = '$_local\\Temp';

InstalledAppInfo _app(
  String id,
  String name, {
  String? publisher,
  String? location,
  List<String> exes = const [],
}) => InstalledAppInfo(
  id: id,
  displayName: name,
  publisher: publisher,
  installLocation: location,
  source: InstalledAppSource.win32,
  executablePaths: exes,
);

final List<InstalledAppInfo> _apps = [
  _app('warp', 'Warp', location: r'C:\Program Files\Warp\'),
  _app('warpinator', 'Warpinator 1.1'),
  _app('idm', 'Internet Download Manager', publisher: 'Tonec Inc.'),
  _app('wps', 'WPS Office', publisher: 'Kingsoft Corp.'),
  _app('terabox', 'TeraBox', location: r'C:\Users\me\AppData\Roaming\TeraBox'),
  _app('bun', 'Bun', location: r'C:\Users\me\.bun'),
  _app('cmake', 'CMake', exes: [r'C:\Program Files\CMake\bin\cmake-gui.exe']),
  _app('git', 'Git', publisher: 'The Git Development Community'),
  _app('lagofast', 'LagoFast'),
  _app(
    'android',
    'Android Studio',
    exes: [r'C:\Program Files\Android\Android Studio\bin\studio.exe'],
  ),
  _app('vs', 'Visual Studio Community 2026'),
  _app(
    'vscode',
    'Microsoft Visual Studio Code (User)',
    location: r'C:\Users\me\AppData\Local\Programs\Microsoft VS Code\',
    exes: [r'C:\Users\me\AppData\Local\Programs\Microsoft VS Code\Code.exe'],
  ),
  _app('cbhub', 'CB File Hub v1.23.1.0'),
  _app('cbhub-msix', 'CB File Hub'),
  _app('corsair-1', 'Corsair Device Control Service', publisher: 'Corsair'),
  _app('corsair-2', 'Corsair iCUE', publisher: 'Corsair'),
  _app('denuvo', 'Denuvo Anti-Cheat'),
  _app(
    'chrome',
    'Google Chrome',
    exes: [r'C:\Program Files\Google\Chrome\Application\chrome.exe'],
  ),
  _app('edge-webview', 'Microsoft Edge WebView2 Runtime'),
  // Registry install folders that own nothing.
  _app('junk-root-1', 'Odd Tool', location: r'C:\Users\me\AppData\Local'),
  _app('junk-root-2', 'Other Tool', location: r'C:\'),
  _app('junk-root-3', 'Third Tool', location: r'C:\Users\me'),
];

void main() {
  final apps = CleanerInstalledApps(_apps);
  String? name(String value) => apps.byName(value)?.id;

  group('byName', () {
    test('names in folders and files', () {
      expect(name('.tmpv0.2026.10.14.08.27.stable_01-WarpSetup.exe'), 'warp');
      expect(name('IDM_Setup_Temp'), 'idm');
      expect(name('wps'), 'wps');
      expect(name('TeraBox'), 'terabox');
      expect(name('TeraBoxUpdate'), 'terabox');
      expect(name('.bun-1804480122-e1cd43857cefa531.dll'), 'bun');
      expect(name('cb_file_hub'), 'cbhub');
    });

    test('words other apps merely contain do not match', () {
      // `make` is not CMake, `git` inside a hump is not Git, `fast` is not
      // LagoFast, and `studio` belongs to two apps.
      expect(name('make40316-1.bat'), isNull);
      expect(name('VSGitHubCopilotLogs'), isNull);
      expect(name('agenttandem-fast-YbqnbV'), isNull);
      expect(name('dd_setup_001_Microsoft.VisualStudio.Product.log'), isNull);
      // Android Studio's studio.exe only matches a whole name.
      expect(
        name('VS8E53F127.Microsoft.VisualStudio.Services.ZBUA.svclog'),
        isNull,
      );
      expect(name('studio'), 'android');
      // A brand two installed apps share names neither.
      expect(name('agenttandem-quota-device-YrlZKp'), isNull);
      expect(name('Corsair'), isNull);
      // Hex IDs do not spell acronyms (Denuvo Anti-Cheat → dac).
      expect(name('folder-display-prefs-dac3edd3'), isNull);
    });

    test('generic folder names never name an app', () {
      for (final folder in [
        'Code Cache',
        'Cache',
        'Microsoft',
        'Google',
        'resources',
        'com.alexmercerind.media_kit.NativeReferenceHolder.10344',
      ]) {
        expect(name(folder), isNull, reason: folder);
      }
    });

    test('a name two apps share is ambiguous, the same app twice is not', () {
      expect(name('warpinator'), 'warpinator');
      expect(apps.byExactName('CB File Hub'), isNotNull);
    });
  });

  test('install folders, ignoring ones that are only a base folder', () {
    List<String> segs(String path) => path.toLowerCase().split(r'\');
    expect(
      apps.byInstallRoot(segs(r'C:\Users\me\AppData\Roaming\TeraBox\x\y.tmp')),
      isNotNull,
    );
    expect(apps.byInstallRoot(segs('$_local\\SomeTool\\Cache\\f')), isNull);
    expect(apps.byInstallRoot(segs(r'C:\Users\me\Downloads\a.bin')), isNull);
  });

  test('display names drop the version and install scope', () {
    expect(
      CleanerInstalledApps.displayName(_apps[11]),
      'Microsoft Visual Studio Code',
    );
    expect(CleanerInstalledApps.displayName(_apps[12]), 'CB File Hub');
  });

  group('origins', () {
    CleanerItemOrigin of(String categoryId, String path) =>
        CleanerItemOrigins.of(
          JunkItem(path: path, sizeBytes: 1, categoryId: categoryId),
          apps: apps,
        );

    test('%TEMP% items name the installed app', () {
      final warp = of(
        'windows_temp',
        '$_temp\\.tmpv0.2026.10.14.08.27.stable_01-WarpSetup.exe',
      );
      expect(warp.app, 'Warp');
      expect(warp.installedApp?.id, 'warp');
      expect(warp.kind, CleanerItemKind.installer);

      final idm = of('windows_temp', '$_temp\\IDM_Setup_Temp\\a.dat');
      expect(idm.app, 'Internet Download Manager');
      expect(idm.appIsFolder, isFalse);
    });

    test('names this file already knows link to the installed entry', () {
      final chrome = of(
        'browser_cache',
        '$_local\\Google\\Chrome\\User Data\\Default\\Cache\\f_1',
      );
      expect(chrome.app, 'Google Chrome');
      expect(chrome.installedApp?.id, 'chrome');

      // A crash dump's executable becomes the app's name.
      final dump = of(
        'crash_dumps_logs',
        '$_local\\CrashDumps\\cmake-gui.exe.12.dmp',
      );
      expect(dump.app, 'CMake');
      expect(dump.installedApp?.id, 'cmake');
    });

    test('Code Cache under an unknown folder is not VS Code', () {
      final origin = of(
        'app_cache',
        r'C:\Users\me\AppData\Roaming\SomeTool\Code Cache\js\a',
      );
      expect(origin.installedApp, isNull);
      expect(origin.app, 'SomeTool');
      expect(origin.appIsFolder, isTrue);
    });

    test('Windows itself is never linked', () {
      final origin = of(
        'thumbnail_cache',
        '$_local\\Microsoft\\Windows\\Explorer\\thumbcache_96.db',
      );
      expect(origin.app, 'Windows Explorer');
      expect(origin.installedApp, isNull);
    });

    test('several folders of one app share one source key', () {
      final a = of('windows_temp', '$_temp\\TeraBox\\a.tmp');
      final b = of('windows_temp', '$_temp\\TeraBoxUpdate\\b.tmp');
      expect(a.key, b.key);
    });
  });
}

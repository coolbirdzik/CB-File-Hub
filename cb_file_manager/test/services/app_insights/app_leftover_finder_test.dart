import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_finder.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

const _mib = 1024 * 1024;

const _environment = <String, String>{
  'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
  'APPDATA': r'C:\Users\me\AppData\Roaming',
  'PROGRAMDATA': r'C:\ProgramData',
  'PROGRAMFILES': r'C:\Program Files',
};

DiskTreeNode _dir(
  String path, [
  int sizeBytes = 0,
  List<DiskTreeNode> children = const <DiskTreeNode>[],
]) {
  final total = children.fold<int>(sizeBytes, (sum, c) => sum + c.sizeBytes);
  return DiskTreeNode(
    name: path.split(r'\').last,
    fullPath: path,
    sizeBytes: total,
    children: children,
  );
}

DiskTreeNode _tree() {
  const local = r'C:\Users\me\AppData\Local';
  const roaming = r'C:\Users\me\AppData\Roaming';
  return DiskTreeNode(
    name: r'C:\',
    fullPath: r'C:\',
    children: [
      _dir(r'C:\Users', 0, [
        _dir(r'C:\Users\me', 0, [
          _dir(r'C:\Users\me\AppData', 0, [
            _dir(local, 0, [
              _dir('$local\\Discord', 200 * _mib),
              _dir('$local\\OldGame', 300 * _mib),
              _dir('$local\\Microsoft', 1024 * _mib),
              _dir('$local\\Temp', 900 * _mib),
              _dir('$local\\Tiny', 1024),
              _dir('$local\\JetBrains', 0, [
                _dir('$local\\JetBrains\\PyCharm2021.3', 400 * _mib),
                _dir('$local\\JetBrains\\PyCharm2024.1', 500 * _mib),
                _dir('$local\\JetBrains\\Rider2022.1', 50 * _mib),
                _dir('$local\\JetBrains\\CrashReports', 20 * _mib),
              ]),
            ]),
            _dir(roaming, 0, [
              _dir('$roaming\\Code', 80 * _mib),
              _dir('$roaming\\Spotify', 90 * _mib),
              _dir('$roaming\\Forgotten Tool', 15 * _mib),
              _dir('$roaming\\ComfyUI', 40 * _mib),
              _dir('$roaming\\Apple Computer', 0, [
                _dir('$roaming\\Apple Computer\\MobileSync', 4096 * _mib),
              ]),
            ]),
          ]),
        ]),
      ]),
      _dir(r'C:\ProgramData', 0, [
        _dir(r'C:\ProgramData\OldVendor', 60 * _mib),
        _dir(r'C:\ProgramData\IDM', 20 * _mib),
        _dir(r'C:\ProgramData\Microsoft', 300 * _mib),
      ]),
      _dir(r'C:\Program Files', 0, [
        _dir(r'C:\Program Files\Acme', 0, [
          _dir(r'C:\Program Files\Acme\AcmeEditor', 700 * _mib),
          _dir(r'C:\Program Files\Acme\AcmeLegacy', 250 * _mib),
        ]),
        _dir(r'C:\Program Files\Common Files', 400 * _mib),
      ]),
    ],
  );
}

const _apps = <InstalledAppInfo>[
  InstalledAppInfo(
    id: 'discord',
    displayName: 'Discord',
    publisher: 'Discord Inc.',
    source: InstalledAppSource.win32,
    installLocation: r'C:\Users\me\AppData\Local\Discord',
  ),
  InstalledAppInfo(
    id: 'pycharm',
    displayName: 'PyCharm Community Edition 2024.1.2',
    publisher: 'JetBrains s.r.o.',
    version: '241.15989.155',
    source: InstalledAppSource.win32,
  ),
  InstalledAppInfo(
    id: 'vscode',
    displayName: 'Microsoft Visual Studio Code',
    publisher: 'Microsoft Corporation',
    source: InstalledAppSource.win32,
  ),
  InstalledAppInfo(
    id: 'acme',
    displayName: 'Acme Editor',
    publisher: 'Acme Inc',
    source: InstalledAppSource.win32,
    installLocation: r'C:\Program Files\Acme\AcmeEditor',
  ),
  InstalledAppInfo(
    id: 'idm',
    displayName: 'Internet Download Manager',
    publisher: 'Tonec Inc.',
    source: InstalledAppSource.win32,
    displayIconPath:
        r'C:\Program Files (x86)\Internet Download Manager\IDMan.exe',
  ),
  InstalledAppInfo(
    id: 'comfy',
    displayName: 'Comfy Desktop 1.1.8',
    publisher: 'Comfy Org',
    source: InstalledAppSource.win32,
  ),
  InstalledAppInfo(
    id: 'itunes',
    displayName: 'iTunes',
    publisher: 'Apple Inc.',
    source: InstalledAppSource.win32,
    installLocation: r'C:\Program Files\iTunes\',
  ),
  InstalledAppInfo(
    id: 'msix:spotify',
    displayName: 'Spotify Music',
    publisher: 'Spotify AB',
    source: InstalledAppSource.msix,
    packageFamilyName: 'SpotifyAB.SpotifyMusic_zpdnekdrzrea0',
  ),
];

AppLeftoverReport _find({
  List<InstalledAppInfo> apps = _apps,
  Iterable<String> excludedPaths = const <String>[],
}) {
  return const AppLeftoverFinder().find(
    root: _tree(),
    apps: apps,
    environment: _environment,
    excludedPaths: excludedPaths,
    generatedAt: DateTime(2026, 10, 1),
  );
}

AppLeftoverCandidate? _byName(AppLeftoverReport report, String name) {
  for (final candidate in report.candidates) {
    if (candidate.displayName == name) return candidate;
  }
  return null;
}

void main() {
  test('reports folders that no installed app or publisher accounts for', () {
    final report = _find();

    final oldGame = _byName(report, 'OldGame');
    expect(oldGame, isNotNull);
    expect(oldGame!.reason, AppLeftoverReason.noInstalledApp);
    expect(oldGame.location, AppLeftoverLocation.localAppData);
    expect(oldGame.sizeBytes, 300 * _mib);

    expect(
      _byName(report, 'Forgotten Tool')?.location,
      AppLeftoverLocation.roamingAppData,
    );
    expect(
      _byName(report, 'OldVendor')?.location,
      AppLeftoverLocation.programData,
    );
    expect(report.inventoryUnavailable, isFalse);
  });

  test('keeps folders of installed apps and system folders out', () {
    final names = _find().candidates.map((c) => c.displayName).toSet();

    // Install location, display-name word and MSIX package name matches.
    expect(names, isNot(contains('Discord')));
    expect(names, isNot(contains('Code')));
    expect(names, isNot(contains('Spotify')));
    expect(names, isNot(contains(r'Acme\AcmeEditor')));
    expect(names, isNot(contains(r'JetBrains\PyCharm2024.1')));
    // Windows, shared-component and tiny folders.
    expect(names, isNot(contains('Microsoft')));
    expect(names, isNot(contains('Temp')));
    expect(names, isNot(contains('Common Files')));
    expect(names, isNot(contains(r'JetBrains\CrashReports')));
    expect(names, isNot(contains('Tiny')));
  });

  test('flags older version folders next to the installed version', () {
    final report = _find();

    final older = _byName(report, r'JetBrains\PyCharm2021.3');
    expect(older, isNotNull);
    expect(older!.reason, AppLeftoverReason.olderVersion);
    expect(older.relatedAppName, 'PyCharm Community Edition 2024.1.2');
  });

  test('does not flag an older version that is still installed', () {
    final report = _find(
      apps: <InstalledAppInfo>[
        ..._apps,
        const InstalledAppInfo(
          id: 'pycharm-2021',
          displayName: 'PyCharm Community Edition 2021.3',
          publisher: 'JetBrains s.r.o.',
          source: InstalledAppSource.win32,
        ),
      ],
    );

    expect(_byName(report, r'JetBrains\PyCharm2021.3'), isNull);
  });

  test('never reports unknown folders inside vendor or install folders', () {
    final report = _find();

    // Vendor folders hold shared parts (Apple's MobileSync backups, an
    // Electron app's storage), so only older versions inside are reported.
    expect(_byName(report, r'JetBrains\Rider2022.1'), isNull);
    expect(_byName(report, r'Apple Computer\MobileSync'), isNull);
    expect(_byName(report, 'Apple Computer'), isNull);
    expect(_byName(report, r'Acme\AcmeLegacy'), isNull);
  });

  test('matches acronyms and folder names that extend an app word', () {
    final names = _find().candidates.map((c) => c.displayName).toSet();

    expect(names, isNot(contains('IDM')));
    expect(names, isNot(contains('ComfyUI')));
  });

  test('never reports excluded paths or their parents', () {
    final report = _find(
      excludedPaths: const <String>[r'C:\Users\me\AppData\Local\OldGame\sub'],
    );

    expect(_byName(report, 'OldGame'), isNull);
  });

  test('reports nothing without the Win32 inventory', () {
    final report = _find(
      apps: _apps
          .where((app) => app.source == InstalledAppSource.msix)
          .toList(growable: false),
    );

    expect(report.inventoryUnavailable, isTrue);
    expect(report.candidates, isEmpty);
  });

  test('sorts candidates by size', () {
    final sizes = _find().candidates.map((c) => c.sizeBytes).toList();
    final sorted = [...sizes]..sort((a, b) => b.compareTo(a));
    expect(sizes, sorted);
  });

  test('findNode walks path segments case-insensitively', () {
    final root = _tree();
    final node = AppLeftoverFinder.findNode(
      root,
      r'c:\users\ME\appdata\local\jetbrains\pycharm2021.3',
    );
    expect(
      node?.fullPath,
      r'C:\Users\me\AppData\Local\JetBrains\PyCharm2021.3',
    );
    expect(AppLeftoverFinder.findNode(root, r'C:\Missing'), isNull);
    expect(AppLeftoverFinder.findNode(root, r'D:\Users'), isNull);
  });
}

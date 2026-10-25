import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_finder.dart';
import 'package:cb_file_manager/services/app_insights/posix_app_leftover_finder.dart';
import 'package:flutter_test/flutter_test.dart';

const _mac = <InstalledAppInfo>[
  InstalledAppInfo(
    id: 'mac:com.google.Chrome',
    displayName: 'Google Chrome',
    publisher: 'google',
    source: InstalledAppSource.macApp,
    installLocation: '/Applications/Google Chrome.app',
    packageFamilyName: 'com.google.Chrome',
  ),
  InstalledAppInfo(
    id: 'mac:com.tinyspeck.slackmacgap',
    displayName: 'Slack',
    publisher: 'tinyspeck',
    source: InstalledAppSource.macApp,
    packageFamilyName: 'com.tinyspeck.slackmacgap',
  ),
  InstalledAppInfo(
    id: 'exe:git',
    displayName: 'git',
    source: InstalledAppSource.executable,
  ),
];

List<String> _names(AppLeftoverReport report) =>
    report.candidates.map((c) => c.displayName).toList();

void main() {
  group('bases', () {
    test('macOS uses the user Library folders', () {
      final bases = PosixAppLeftoverFinder.bases(const <String, String>{
        'HOME': '/Users/me/',
      }, operatingSystem: 'macos');
      expect(bases.map((b) => b.path), <String>[
        '/Users/me/Library/Containers',
        '/Users/me/Library/Group Containers',
        '/Users/me/Library/Application Support',
        '/Users/me/Library/Caches',
      ]);
    });

    test('Linux honours XDG overrides', () {
      final bases = PosixAppLeftoverFinder.bases(const <String, String>{
        'HOME': '/home/me',
        'XDG_CONFIG_HOME': '/data/config',
      }, operatingSystem: 'linux');
      expect(bases.map((b) => b.path), <String>[
        '/data/config',
        '/home/me/.local/share',
        '/home/me/.cache',
        '/home/me/.var/app',
        '/home/me/snap',
      ]);
    });
  });

  test('macOS compares bundle ids, vendors and app names', () {
    const root = '/Users/me/Library';
    final report = const PosixAppLeftoverFinder().find(
      listing: [
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.macContainers,
            '$root/Containers',
          ),
          <String>[
            'com.tinyspeck.slackmacgap',
            'com.google.Chrome.helper',
            'com.google.Drive',
            'com.oldvendor.Player',
            'com.apple.mail',
            'BB9C3FA1-1111-2222-3333-444455556666',
          ],
        ),
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.macGroupContainers,
            '$root/Group Containers',
          ),
          <String>[
            'group.com.apple.notes',
            'ABCDE12345.com.oldvendor.shared',
            'XYZ9876543.com.tinyspeck.slack',
          ],
        ),
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.macApplicationSupport,
            '$root/Application Support',
          ),
          <String>[
            'Google',
            'Slack',
            'MobileSync',
            'routined',
            'OldEditor',
            'git',
          ],
        ),
      ],
      inventory: const AppLeftoverInventory(apps: _mac),
    );

    expect(_names(report), <String>[
      'com.oldvendor.Player',
      'ABCDE12345.com.oldvendor.shared',
      'OldEditor',
    ]);
    expect(
      report.candidates.first.path,
      '/Users/me/Library/Containers/com.oldvendor.Player',
    );
    expect(report.candidates.first.location, AppLeftoverLocation.macContainers);
  });

  test('Linux compares Flatpak and snap lists exactly', () {
    final report = const PosixAppLeftoverFinder().find(
      listing: [
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.linuxFlatpak,
            '/home/me/.var/app',
          ),
          <String>['org.mozilla.firefox', 'com.spotify.Client'],
        ),
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.linuxSnap,
            '/home/me/snap',
          ),
          <String>['code', 'telegram-desktop', 'bin'],
        ),
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.linuxConfig,
            '/home/me/.config',
          ),
          <String>[
            'Code',
            'gnome-shell',
            'autostart',
            'htop',
            'OldTool',
            'org.gnome.Gedit',
            '.hidden',
          ],
        ),
      ],
      inventory: const AppLeftoverInventory(
        apps: <InstalledAppInfo>[
          InstalledAppInfo(
            id: 'desktop:code',
            displayName: 'Visual Studio Code',
            source: InstalledAppSource.linuxDesktop,
            packageFamilyName: 'code',
            executablePaths: <String>['/usr/bin/code'],
          ),
          InstalledAppInfo(
            id: 'desktop:org.gnome.TextEditor',
            displayName: 'Text Editor',
            source: InstalledAppSource.linuxDesktop,
            packageFamilyName: 'org.gnome.TextEditor',
          ),
          InstalledAppInfo(
            id: 'exe:htop',
            displayName: 'htop',
            source: InstalledAppSource.executable,
          ),
        ],
        flatpakApps: <String>{'org.mozilla.firefox'},
        snaps: <String>{'code'},
      ),
    );

    expect(_names(report), <String>[
      'com.spotify.Client',
      'telegram-desktop',
      'OldTool',
    ]);
  });

  test('skips Flatpak and snap folders when the lists are unknown', () {
    final report = const PosixAppLeftoverFinder().find(
      listing: [
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.linuxFlatpak,
            '/home/me/.var/app',
          ),
          <String>['com.spotify.Client'],
        ),
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.linuxSnap,
            '/home/me/snap',
          ),
          <String>['telegram-desktop'],
        ),
      ],
      inventory: const AppLeftoverInventory(
        apps: <InstalledAppInfo>[
          InstalledAppInfo(
            id: 'desktop:code',
            displayName: 'Code',
            source: InstalledAppSource.linuxDesktop,
          ),
        ],
      ),
    );
    expect(report.candidates, isEmpty);
  });

  test('reports nothing without real apps in the inventory', () {
    final report = const PosixAppLeftoverFinder().find(
      listing: [
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.linuxConfig,
            '/home/me/.config',
          ),
          <String>['OldTool'],
        ),
      ],
      inventory: const AppLeftoverInventory(
        apps: <InstalledAppInfo>[
          InstalledAppInfo(
            id: 'exe:ls',
            displayName: 'ls',
            source: InstalledAppSource.executable,
          ),
        ],
      ),
    );
    expect(report.inventoryUnavailable, isTrue);
    expect(report.candidates, isEmpty);
  });

  test('never reports excluded paths', () {
    final report = const PosixAppLeftoverFinder().find(
      listing: [
        (
          const PosixLeftoverBase(
            AppLeftoverLocation.linuxData,
            '/home/me/.local/share',
          ),
          <String>['com.coolbird.cb_file_manager', 'OldTool'],
        ),
      ],
      inventory: const AppLeftoverInventory(apps: _mac),
      excludedPaths: const <String>[
        '/home/me/.local/share/com.coolbird.cb_file_manager',
      ],
    );
    expect(_names(report), <String>['OldTool']);
  });

  test('recognises bundle-style and group container names', () {
    expect(PosixAppLeftoverFinder.isReverseDns('com.vendor.App'), isTrue);
    expect(PosixAppLeftoverFinder.isReverseDns('Google'), isFalse);
    expect(PosixAppLeftoverFinder.isReverseDns('gtk-3.0'), isFalse);
    expect(
      PosixAppLeftoverFinder.groupContainerBundleId('group.com.vendor.app'),
      'com.vendor.app',
    );
    expect(
      PosixAppLeftoverFinder.groupContainerBundleId('ABCDE12345.com.vendor.x'),
      'com.vendor.x',
    );
    expect(
      PosixAppLeftoverFinder.groupContainerBundleId('group.com.apple.notes'),
      isNull,
    );
  });
}

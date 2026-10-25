import 'dart:io';

import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_finder.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_scanner.dart';
import 'package:cb_file_manager/services/app_insights/posix_app_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads bundle values from an XML Info.plist', () {
    final values = parseXmlPlistStrings('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key>
  <string>com.tinyspeck.slackmacgap</string>
  <key>CFBundleName</key><string>Slack &amp; Co</string>
  <key>CFBundleExecutable</key><string>Slack</string>
  <key>LSRequiresNativeExecution</key><true/>
</dict></plist>
''');
    expect(values['CFBundleIdentifier'], 'com.tinyspeck.slackmacgap');
    expect(values['CFBundleName'], 'Slack & Co');

    final app = macAppFromInfoPlist('/Applications/Slack.app', values)!;
    expect(app.source, InstalledAppSource.macApp);
    expect(app.packageFamilyName, 'com.tinyspeck.slackmacgap');
    expect(app.publisher, 'tinyspeck');
    expect(app.executablePaths, <String>[
      '/Applications/Slack.app/Contents/MacOS/Slack',
    ]);
  });

  test('reads the Desktop Entry section of a .desktop file', () {
    final app = linuxAppFromDesktopEntry('org.gnome.TextEditor.desktop', '''
[Desktop Entry]
Name=Text Editor
Exec=gnome-text-editor %U
Icon=org.gnome.TextEditor
StartupWMClass=gnome-text-editor

[Desktop Action new-window]
Name=New Window
Exec=other-binary
''')!;
    expect(app.packageFamilyName, 'org.gnome.TextEditor');
    expect(app.displayName, 'Text Editor (gnome-text-editor)');
    expect(app.executablePaths, <String>['gnome-text-editor']);
    expect(app.displayIconPath, 'org.gnome.TextEditor');
  });

  test('discovers Linux leftovers from a home folder', () async {
    final home = Directory.systemTemp.createTempSync('cb_leftover_home_');
    addTearDown(() => home.deleteSync(recursive: true));
    for (final path in <String>[
      '.config/Code',
      '.config/OldTool',
      '.local/share/OldGame',
      '.var/app/com.spotify.Client',
    ]) {
      Directory('${home.path}/$path').createSync(recursive: true);
    }

    final report = await const AppLeftoverScanner().discover(
      inventory: const AppLeftoverInventory(
        apps: <InstalledAppInfo>[
          InstalledAppInfo(
            id: 'desktop:code',
            displayName: 'Visual Studio Code',
            source: InstalledAppSource.linuxDesktop,
            executablePaths: <String>['/usr/bin/code'],
          ),
        ],
        flatpakApps: <String>{},
        snaps: <String>{},
      ),
      environment: <String, String>{'HOME': home.path.replaceAll(r'\', '/')},
      operatingSystem: 'linux',
    );

    expect(report.candidates.map((c) => c.displayName).toSet(), <String>{
      'OldTool',
      'OldGame',
      'com.spotify.Client',
    });
    expect(
      report.candidates.firstWhere((c) => c.displayName == 'OldTool').location,
      AppLeftoverLocation.linuxConfig,
    );
  });
}

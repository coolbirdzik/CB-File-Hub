import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_uninstall_service.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_insights_platform.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_inventory_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const app = InstalledAppInfo(
  id: 'alpha',
  displayName: 'Alpha Editor',
  publisher: 'Acme',
  source: InstalledAppSource.win32,
  uninstallCommand: r'"C:\Apps\Alpha Editor\uninstall.exe" /remove',
  installLocation: r'C:\Apps\Alpha Editor',
);

class _Runner implements AppInsightsProcessRunner {
  int exitCode = 0;
  int calls = 0;
  String script = '';
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls++;
    expect(executable, endsWith(r'WindowsPowerShell\v1.0\powershell.exe'));
    expect(arguments, containsAll(['-NoProfile', '-NonInteractive', 'Hidden']));
    final bytes = base64Decode(arguments.last);
    script = String.fromCharCodes([
      for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
    ]);
    return ProcessResult(1, exitCode, '', exitCode == 0 ? '' : 'cancelled');
  }
}

void main() {
  test(
    'parser preserves interactive command, never substitutes quiet command',
    () {
      final parsed = const WindowsAppInventoryParser().parseWin32Entries([
        {
          'displayName': 'Alpha Editor',
          'registryKeyName': 'Alpha',
          'uninstallString': app.uninstallCommand,
          'quietUninstallString': 'quiet.exe /S',
        },
        {
          'displayName': 'Quiet only',
          'registryKeyName': 'Quiet',
          'quietUninstallString': 'quiet.exe /S',
        },
      ]);
      expect(parsed.first.uninstallCommand, app.uninstallCommand);
      expect(AppUninstallService.supports(parsed.last), isFalse);
      expect(app.copyWith(version: '2').uninstallCommand, app.uninstallCommand);
    },
  );

  test('uses fresh registry command and confirms app disappearance', () async {
    var reads = 0;
    final runner = _Runner();
    final service = AppUninstallService(
      processRunner: runner,
      loadInventory: () async => InstalledAppInventoryResult(
        apps: reads++ == 0
            ? [
                app.copyWith(
                  uninstallCommand: r'"C:\New Location\remove.exe" /remove',
                ),
              ]
            : [],
      ),
    );
    final result = await service.uninstall(app);
    expect(result.apps, isEmpty);
    expect(reads, 2);
    expect(runner.calls, 1);
    expect(runner.script, contains(r'C:\New Location\remove.exe'));
    expect(runner.script, isNot(contains(r'C:\Apps\Alpha Editor')));
    expect(runner.script, contains('Wait = \$true'));
  });

  test(
    'incomplete inventory blocks uninstall before launching any process',
    () async {
      final runner = _Runner();
      final service = AppUninstallService(
        processRunner: runner,
        loadInventory: () async =>
            const InstalledAppInventoryResult(apps: [app], isPartial: true),
      );
      await expectLater(
        service.uninstall(app),
        throwsA(isA<AppUninstallException>()),
      );
      expect(runner.calls, 0);
    },
  );

  test(
    'cancellation is reported without permitting leftover cleanup',
    () async {
      final runner = _Runner()..exitCode = 1602;
      var reads = 0;
      final service = AppUninstallService(
        processRunner: runner,
        loadInventory: () async {
          reads++;
          return const InstalledAppInventoryResult(apps: [app]);
        },
      );
      await expectLater(
        service.uninstall(app),
        throwsA(isA<AppUninstallException>()),
      );
      expect(reads, 1);
    },
  );

  test(
    'zero exit with app still installed is not treated as successful removal',
    () async {
      final service = AppUninstallService(
        processRunner: _Runner(),
        loadInventory: () async =>
            const InstalledAppInventoryResult(apps: [app]),
      );
      await expectLater(
        service.uninstall(app),
        throwsA(isA<AppUninstallException>()),
      );
    },
  );

  test(
    'reinstall and partial inventory block the post-uninstall scan',
    () async {
      var partial = false;
      final service = AppUninstallService(
        loadInventory: () async => InstalledAppInventoryResult(
          apps: partial ? [] : [app.copyWith(id: 'reinstalled')],
          isPartial: partial,
        ),
      );
      await expectLater(
        service.scan(const AppStorageProfile(app: app), excludedPaths: []),
        throwsA(isA<AppUninstallException>()),
      );
      partial = true;
      await expectLater(
        service.scan(const AppStorageProfile(app: app), excludedPaths: []),
        throwsA(isA<AppUninstallException>()),
      );
    },
  );

  test('MSI maintenance commands become interactive uninstall commands', () {
    final script = AppUninstallService.buildUninstallScript(
      app.copyWith(uninstallCommand: r'MsiExec.exe /I{1234-5678}'),
    );
    expect(script, contains("ArgumentList = '/X{1234-5678}'"));
    expect(script, isNot(contains('/quiet')));
    expect(script, isNot(contains('/qn')));
  });

  test('quotes and script-like argument text remain literal', () {
    final script = AppUninstallService.buildUninstallScript(
      app.copyWith(
        uninstallCommand:
            r'''"C:\O'Brien\uninstall.exe" /name "a'b"; $(Write-Output injected)''',
      ),
    );
    expect(script, contains(r"C:\O''Brien\uninstall.exe"));
    expect(
      script,
      contains(
        r'''ArgumentList = '/name "a''b"; $(Write-Output injected)' '''.trim(),
      ),
    );
    expect(script, isNot(contains('Invoke-Expression')));
  });

  test(
    'MSIX removes exact family for current user without wildcards or all-users',
    () {
      final script = AppUninstallService.buildUninstallScript(
        const InstalledAppInfo(
          id: 'store',
          displayName: 'Store App',
          source: InstalledAppSource.msix,
          packageFamilyName: 'Contoso.App_123',
        ),
      );
      expect(script, contains("PackageFamilyName -eq 'Contoso.App_123'"));
      expect(
        script,
        contains('Remove-AppxPackage -Package \$_.PackageFullName'),
      );
      expect(script, isNot(contains('-AllUsers')));
      expect(script, isNot(contains('-like')));
    },
  );

  group('targeted filesystem scan', () {
    late Directory temp;
    late String local;
    late String roaming;
    late Map<String, String> env;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('cb_uninstall_test_');
      local = p.join(temp.path, 'Local');
      roaming = p.join(temp.path, 'Roaming');
      Directory(local).createSync();
      Directory(roaming).createSync();
      env = {'LOCALAPPDATA': local, 'APPDATA': roaming};
    });
    tearDown(() => temp.deleteSync(recursive: true));

    String folder(String root, String name) {
      final dir = Directory(p.join(root, name))..createSync(recursive: true);
      File(
        p.join(dir.path, 'settings.json'),
      ).writeAsStringSync('personal data');
      return dir.path;
    }

    AppUninstallScan scan({
      List<InstalledAppInfo> remaining = const [],
      List<String> excluded = const [],
      AppStorageProfile? profile,
    }) => scanUninstalledAppSync(
      profile: profile ?? const AppStorageProfile(app: app),
      remainingApps: remaining,
      environment: env,
      excludedPaths: excluded,
    );

    test(
      'finds small recent folders, vendor children and collapses nested roots',
      () {
        final alpha = folder(local, 'Alpha Editor');
        folder(alpha, 'Cache');
        final vendorChild = folder(roaming, r'Acme\Alpha Editor');
        folder(local, 'Unrelated App');
        final result = scan(
          profile: AppStorageProfile(
            app: app,
            entries: [
              AppStorageEntry(
                path: p.join(alpha, 'Cache'),
                kind: AppStorageKind.cache,
                sizeBytes: 0,
                measurementQuality: MeasurementQuality.measured,
                attributionConfidence: AttributionConfidence.confirmed,
              ),
            ],
          ),
        );
        expect(result.folders.keys, unorderedEquals([alpha, vendorChild]));
        expect(result.folders[alpha]!.sizeBytes, greaterThan(0));
        expect(result.folders[alpha]!.sizeBytes, lessThan(1024 * 1024));
        expect(result.folders[alpha]!.lastModified, isNotNull);
        expect(File(p.join(alpha, 'settings.json')).existsSync(), isTrue);
      },
    );

    test(
      'retained app install roots and the Cleaner own paths are excluded',
      () {
        final alpha = folder(local, 'Alpha Editor');
        expect(
          scan(
            remaining: [
              const InstalledAppInfo(
                id: 'plugin',
                displayName: 'Plugin',
                source: InstalledAppSource.win32,
                installLocation: 'unused',
              ).copyWith(installLocation: p.join(alpha, 'Plugin')),
            ],
          ).folders,
          isEmpty,
        );
        expect(scan(excluded: [alpha]).folders, isEmpty);
      },
    );

    test(
      'does not infer ownership from just a publisher or shared brand word',
      () {
        folder(local, 'Acme');
        folder(local, 'Alpha Backup');
        final shared = folder(roaming, 'Acme');
        final profile = AppStorageProfile(
          app: app.copyWith(installLocation: shared),
        );
        expect(scan(profile: profile).folders, isEmpty);
      },
    );

    test('does not offer base folders from bad registry metadata', () {
      folder(local, 'Keep');
      expect(
        scan(
          profile: AppStorageProfile(app: app.copyWith(installLocation: local)),
        ).folders,
        isEmpty,
      );
    });

    test(
      'finds Store package data by complete family and exact executable names',
      () {
        final package = folder(local, r'Packages\Contoso.Editor_123');
        final msix = const InstalledAppInfo(
          id: 'store',
          displayName: 'Contoso Editor',
          source: InstalledAppSource.msix,
          packageFamilyName: 'Contoso.Editor_123',
        );
        expect(scan(profile: AppStorageProfile(app: msix)).folders.keys, [
          package,
        ]);
        final data = folder(local, 'alpha');
        final win32 = app.copyWith(
          executablePaths: [r'C:\Apps\Alpha Editor\alpha.exe'],
        );
        expect(scan(profile: AppStorageProfile(app: win32)).folders.keys, [
          data,
        ]);
      },
    );

    test('excludes directory links and candidates inside a linked parent', () {
      final real = folder(temp.path, 'Real');
      final nested = folder(real, 'Alpha Editor');
      final link = Link(p.join(local, 'Alpha Editor'))..createSync(real);
      try {
        expect(scan().folders, isEmpty);
        expect(
          scan(
            profile: AppStorageProfile(
              app: app.copyWith(
                installLocation: p.join(link.path, 'Alpha Editor'),
              ),
            ),
          ).folders,
          isEmpty,
        );
        expect(File(p.join(nested, 'settings.json')).existsSync(), isTrue);
      } finally {
        link.deleteSync();
      }
    });
  }, skip: !Platform.isWindows);
}

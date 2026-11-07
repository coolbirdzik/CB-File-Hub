import 'dart:io';

import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/mac_app_usage.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_insights.dart';
import 'package:cb_file_manager/services/disk_cleaner/app_storage/app_space_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/editor_storage/editor_storage_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _support = '/Users/me/Library/Application Support';

AppSpaceItem _item(
  String path,
  AppSpaceKind kind,
  AppSpaceTier tier,
  int bytes,
) => AppSpaceItem(path: path, kind: kind, tier: tier, bytes: bytes);

void main() {
  final chatter = AppSpaceEntry(
    app: const InstalledAppInfo(
      id: 'chatter',
      displayName: 'Chatter',
      source: InstalledAppSource.macApp,
      installLocation: '/Applications/Chatter.app',
    ),
    isRunning: false,
    unreadable: 1,
    items: [
      _item(
        '/Applications/Chatter.app',
        AppSpaceKind.install,
        AppSpaceTier.review,
        50,
      ),
      _item(
        '$_support/Chatter/Cache',
        AppSpaceKind.cache,
        AppSpaceTier.safe,
        30,
      ),
      _item(
        '/Users/me/Library/Caches/com.chatter',
        AppSpaceKind.cache,
        AppSpaceTier.optional,
        20,
      ),
      _item(
        '$_support/Chatter/logs/a',
        AppSpaceKind.logs,
        AppSpaceTier.safe,
        3,
      ),
      _item(
        '$_support/Chatter/Crashpad/x.dmp',
        AppSpaceKind.crashReports,
        AppSpaceTier.review,
        2,
      ),
      _item(
        '$_support/Chatter/IndexedDB',
        AppSpaceKind.webStorage,
        AppSpaceTier.review,
        9,
      ),
      _item(
        '/Users/me/Library/Group Containers/T.com.chatter',
        AppSpaceKind.sharedData,
        AppSpaceTier.review,
        4,
      ),
    ],
  );
  const tool = AppSpaceEntry(
    app: InstalledAppInfo(
      id: 'tool',
      displayName: 'tool',
      source: InstalledAppSource.executable,
    ),
    isRunning: false,
    items: [
      AppSpaceItem(
        path: '/Users/me/.cache/tool',
        kind: AppSpaceKind.cache,
        tier: AppSpaceTier.optional,
        bytes: 7,
      ),
    ],
  );
  final code = AppSpaceEntry(
    app: const InstalledAppInfo(
      id: 'vscode',
      displayName: 'Visual Studio Code',
      source: InstalledAppSource.macApp,
    ),
    isRunning: false,
    items: const [],
    editor: EditorStorageReport(
      editor: EditorProduct.all.first,
      dataRoot: '$_support/Code',
      extensionsRoot: '/Users/me/.vscode/extensions',
      isRunning: false,
      extensions: const [
        EditorExtensionUsage(
          id: 'pub.ext',
          version: '1.0.0',
          displayName: 'Ext',
          path: '/Users/me/.vscode/extensions/pub.ext-1.0.0',
          status: EditorExtensionStatus.installed,
          installBytes: 40,
          globalStorageBytes: 6,
        ),
      ],
      orphanedExtensionData: const [],
      workspaces: const [],
      data: const [
        EditorDataUsage(
          kind: EditorDataKind.cache,
          paths: ['$_support/Code/Cache'],
          bytes: 12,
          cleanable: [EditorCleanTarget('$_support/Code/Cache', 12)],
        ),
      ],
    ),
  );

  test('App storage entries become Apps profiles', () {
    final lastOpened = DateTime(2026, 9, 1);
    final report = AppSpaceInsights.toAppStorageReport(
      AppSpaceReport(
        entries: [chatter, tool, code],
        generatedAt: DateTime(2026, 11, 7),
      ),
      usageByAppId: {
        'chatter': AppUsageEvidence(
          lastOpenedAt: lastOpened,
          source: AppUsageSource.spotlight,
        ),
      },
    );
    expect(report.drivePath, '/');
    expect(report.isPartial, isFalse);
    // Commands on PATH stay on App storage only.
    expect(report.apps.map((p) => p.app.id), ['chatter', 'vscode']);

    final profile = report.findApp('chatter')!;
    expect(profile.usage.lastOpenedAt, lastOpened);
    Map<AppStorageKind, int> bytesByKind(AppStorageProfile p) => {
      for (final kind in AppStorageKind.values)
        if (p.entries.any((e) => e.kind == kind))
          kind: p.entries
              .where((e) => e.kind == kind)
              .fold(0, (sum, e) => sum + e.sizeBytes),
    };
    expect(bytesByKind(profile), {
      AppStorageKind.install: 50,
      AppStorageKind.cache: 50,
      AppStorageKind.logs: 5,
      AppStorageKind.localData: 9,
      AppStorageKind.shared: 4,
    });
    // Safe and opt-in items are cleanable; shared data is not confirmed.
    expect(profile.cleanableBytes, 30 + 20 + 3);
    expect(profile.confirmedSizeBytes, 50 + 50 + 5 + 9);
    expect(profile.possibleSizeBytes, 0);
    expect(
      profile.entries
          .singleWhere((e) => e.kind == AppStorageKind.shared)
          .attributionConfidence,
      AttributionConfidence.shared,
    );
    expect(profile.measurementQuality, MeasurementQuality.partial);

    final editor = report.findApp('vscode')!;
    expect(editor.entries.map((e) => (e.path, e.sizeBytes)), [
      ('$_support/Code', 6 + 12),
      ('/Users/me/.vscode/extensions', 40),
    ]);
    expect(editor.cleanableBytes, 18);
  });

  test('a report without app sizes is partial unless still measuring', () {
    final partial = AppSpaceReport(
      entries: [chatter],
      generatedAt: DateTime(2026, 11, 7),
      complete: false,
    );
    expect(AppSpaceInsights.toAppStorageReport(partial).isPartial, isTrue);
    expect(
      AppSpaceInsights.toAppStorageReport(partial, isPartial: false).isPartial,
      isFalse,
    );
  });

  test('Spotlight last-used dates', () {
    final usage = MacAppUsage.parse(
      '2026-11-06 13:36:16 +0000\u0000(null)\u00002026-01-02 03:04:05 -0130',
      ['a', 'b', 'c'],
      bundles: {'a': '/Applications/A.app'},
    );
    expect(usage.keys, ['a', 'c']);
    expect(
      usage['a']!.lastOpenedAt!.toUtc(),
      DateTime.utc(2026, 11, 6, 13, 36, 16),
    );
    expect(usage['a']!.source, AppUsageSource.spotlight);
    expect(usage['a']!.matchedTarget, '/Applications/A.app');
    expect(
      usage['c']!.lastOpenedAt!.toUtc(),
      DateTime.utc(2026, 1, 2, 4, 34, 5),
    );
    expect(MacAppUsage.parseDate('garbage'), isNull);
  });

  test('one mdls call for every bundle', () async {
    List<String>? called;
    final usage = await MacAppUsage.load(
      const [
        InstalledAppInfo(
          id: 'a',
          displayName: 'A',
          source: InstalledAppSource.macApp,
          installLocation: '/Applications/A.app',
        ),
        InstalledAppInfo(
          id: 'tool',
          displayName: 'tool',
          source: InstalledAppSource.executable,
          installLocation: '/usr/bin',
        ),
      ],
      run: (args) async {
        called = args;
        return ProcessResult(0, 0, '2026-11-06 13:36:16 +0000', '');
      },
    );
    expect(called, [
      '-name',
      'kMDItemLastUsedDate',
      '-raw',
      '/Applications/A.app',
    ]);
    expect(usage.keys, ['a']);
  });

  test('Apple apps and CB File Hub are never moved to the Trash', () {
    const own = '/Applications/CB File Hub.app/Contents/MacOS/CB File Hub';
    expect(
      macAppIsProtected('/System/Applications/Notes.app', ownExecutable: own),
      isTrue,
    );
    expect(
      macAppIsProtected(
        '/Applications/Safari.app',
        bundleId: 'com.apple.Safari',
        ownExecutable: own,
      ),
      isTrue,
    );
    expect(
      macAppIsProtected('/Applications/CB File Hub.app', ownExecutable: own),
      isTrue,
    );
    expect(
      macAppIsProtected(
        '/Applications/Chatter.app',
        bundleId: 'com.chatter.app',
        ownExecutable: own,
      ),
      isFalse,
    );
  });
}

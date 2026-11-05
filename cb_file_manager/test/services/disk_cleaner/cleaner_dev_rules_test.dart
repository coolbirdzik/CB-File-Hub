import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/cleaner_audited_rules.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_cache_rules.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_categories.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_item_origin.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_paths.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_quick_clean.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_safety.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_isolate.dart';
import 'package:cb_file_manager/services/disk_cleaner/windows_known_folders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final now = DateTime(2026, 11, 5, 12);
  const home = '/home/test';
  const env = {'HOME': home};
  const profile = r'C:\Users\test';
  const local = '$profile\\AppData\\Local';
  const roaming = '$profile\\AppData\\Roaming';

  JunkItem item(
    String categoryId,
    String path, {
    Duration age = const Duration(days: 30),
  }) => JunkItem(
    path: path,
    sizeBytes: 100,
    categoryId: categoryId,
    lastModified: now.subtract(age),
  );

  bool eligible(String categoryId, String path, {Duration? age}) =>
      CleanerQuickClean.isEligible(
        item(categoryId, path, age: age ?? const Duration(days: 30)),
        now,
      );

  test('Linux has Smart Clean junk scans but not the disk tools', () {
    expect(CleanerPaths.supportsJunkScan('linux'), isTrue);
    expect(CleanerPaths.supports('linux'), isFalse);
    expect(CleanerPaths.supportsJunkScan('android'), isFalse);
    expect(CleanerCategories.all(operatingSystem: 'linux').map((c) => c.id), [
      'package_download_cache',
      'electron_cache',
      'developer_analysis_cache',
      'developer_download_cache',
      'developer_logs',
      'electron_crash_reports',
      'old_downloads_review',
    ]);
    expect(CleanerQuickClean.categoryIds(operatingSystem: 'linux'), [
      'package_download_cache',
      'electron_cache',
      'developer_analysis_cache',
      'developer_download_cache',
      'developer_logs',
      'electron_crash_reports',
    ]);
  });

  test('every Linux rule resolves inside HOME and only there is cleanable', () {
    for (final category in CleanerCategories.all(operatingSystem: 'linux')) {
      for (final rule in category.rules) {
        expect(rule.source.kind, PathSourceKind.env);
        expect(rule.source.envVar, 'HOME');
        if (!category.reviewOnly) {
          expect(rule.minAge, isNotNull, reason: rule.source.relative);
        }
        final base = WindowsKnownFolders.resolvePosix(rule.source, env)!;
        expect(base, startsWith('$home/'));
        expect(
          CleanerPathSafety.isPosixPathSafeToDelete(
            '$base/item',
            env,
            operatingSystem: 'linux',
          ),
          category.reviewOnly ? isFalse : isTrue,
          reason: base,
        );
      }
    }
    for (final path in [
      '$home/Documents/a',
      '$home/.config/Code/User/settings.json',
      '$home/.config/Code/User/globalStorage/state.vscdb',
      '$home/.m2/repository/local-only.jar',
      '$home/.pub-cache/hosted/pub.dev/a/lib/a.dart',
      '$home/go/pkg/mod/example.com/a@v1/a.go',
      '$home/.gradle/caches/modules-2/files-2.1/a.jar',
      '$home/.cache/pip/../../Documents/a',
      '$home/.cache/pip-other/a',
      '/home/other/.cache/pip/a',
      '/etc/passwd',
      '/usr/lib/a.so',
      '.cache/pip/a',
    ]) {
      expect(
        CleanerPathSafety.isPosixPathSafeToDelete(
          path,
          env,
          operatingSystem: 'linux',
        ),
        isFalse,
        reason: path,
      );
    }
  });

  test('Linux system roots are protected', () {
    for (final path in [
      '/etc',
      '/etc/fstab',
      '/boot/vmlinuz',
      '/proc/1/mem',
      '/sys/kernel',
      '/var/lib/dpkg/status',
      '/lib64/ld-linux-x86-64.so.2',
      '/snap/core/1',
      '/',
      '/home',
    ]) {
      expect(
        CleanerPathSafety.isPosixPathSafeToDelete(
          path,
          env,
          operatingSystem: 'linux',
        ),
        isFalse,
        reason: path,
      );
    }
  });

  test('quick clean takes old Linux developer junk only', () {
    for (final (id, path) in [
      ('package_download_cache', '$home/.cache/pip/http-v2/a/b'),
      ('package_download_cache', '$home/.npm/_cacache/content-v2/sha512/x'),
      ('package_download_cache', '$home/.cargo/registry/cache/index/a.crate'),
      ('package_download_cache', '$home/.cache/composer/files/vendor/a.zip'),
      ('electron_cache', '$home/.config/discord/Cache/Cache_Data/f_01'),
      ('electron_cache', '$home/.config/Code/CachedData/abc/chrome/js/x'),
      ('developer_analysis_cache', '$home/.cache/go-build/ab/abc-d'),
      ('developer_analysis_cache', '$home/.dartServer/.analysis-driver/ab'),
      ('developer_analysis_cache', '$home/.gradle/caches/build-cache-1/abc'),
      ('developer_download_cache', '$home/.android/cache/sdkbin-1_abc'),
      ('developer_download_cache', '$home/.cache/electron/abc/electron.zip'),
      (
        'developer_download_cache',
        '$home/.gradle/wrapper/dists/gradle-8.5-bin/h/gradle-8.5-bin.zip',
      ),
      ('developer_download_cache', '$home/.rustup/downloads/abc'),
      ('developer_logs', '$home/.config/Code/logs/20261001T101010/main.log'),
      ('developer_logs', '$home/.npm/_logs/2026-10-01T10_00_00-debug-0.log'),
      ('developer_logs', '$home/.gradle/daemon/8.5/daemon-123.out.log'),
      ('developer_logs', '$home/.local/share/kotlin/daemon/daemon.0.log'),
      ('electron_crash_reports', '$home/.config/Slack/Crashpad/pending/a.dmp'),
    ]) {
      expect(eligible(id, path), isTrue, reason: path);
    }
    for (final (id, path) in [
      // Unpacked Gradle distribution and its marker stay.
      (
        'developer_download_cache',
        '$home/.gradle/wrapper/dists/gradle-8.5-bin/h/gradle-8.5/lib/a.jar',
      ),
      (
        'developer_download_cache',
        '$home/.gradle/wrapper/dists/gradle-8.5-bin/h/gradle-8.5-bin.zip.ok',
      ),
      ('developer_logs', '$home/.gradle/daemon/8.5/registry.bin'),
      ('developer_logs', '$home/.npm/_logs/notes.txt'),
      ('electron_crash_reports', '$home/.config/Slack/Crashpad/settings.dat'),
      ('developer_analysis_cache', '$home/.gradle/caches/modules-2/a.jar'),
      ('developer_analysis_cache', '$home/.gradle/caches/build-cache-1.lock'),
      ('developer_download_cache', '$home/.cache/node-gyp/20.0.0/include/a.h'),
      ('package_download_cache', '$home/.cache/yarn/v6/npm-a/index.js'),
      ('electron_cache', '$home/.config/discord/Local Storage/leveldb/1.log'),
    ]) {
      expect(eligible(id, path), isFalse, reason: path);
    }
    expect(
      eligible(
        'developer_logs',
        '$home/.config/Code/logs/today/main.log',
        age: const Duration(days: 2),
      ),
      isFalse,
    );
  });

  test('quick clean takes the new Windows developer junk', () {
    for (final (id, path) in [
      (
        'developer_analysis_cache',
        '$profile\\.gradle\\caches\\build-cache-1\\abc',
      ),
      ('developer_download_cache', '$profile\\.android\\cache\\sdkbin-1_abc'),
      (
        'developer_download_cache',
        '$profile\\.gradle\\wrapper\\dists\\gradle-8.5-bin\\h\\gradle-8.5-bin.zip',
      ),
      ('developer_download_cache', '$profile\\.rustup\\tmp\\abc'),
      ('developer_logs', '$roaming\\Code\\logs\\20261001T101010\\main.log'),
      ('developer_logs', '$roaming\\Cursor\\logs\\20261001T101010\\a.log'),
      ('developer_logs', '$local\\npm-cache\\_logs\\debug-0.log'),
      ('developer_logs', '$profile\\.gradle\\daemon\\8.5\\daemon-1.out.log'),
      ('developer_logs', '$local\\kotlin\\daemon\\daemon.0.log'),
      // Existing name-limited rules still work through the shared check.
      ('electron_crash_reports', '$roaming\\Slack\\Crashpad\\reports\\a.dmp'),
      (
        'developer_download_cache',
        '$roaming\\Comfy Desktop\\download-cache\\uv.tar.gz',
      ),
    ]) {
      expect(eligible(id, path), isTrue, reason: path);
    }
    for (final (id, path) in [
      (
        'developer_download_cache',
        '$profile\\.gradle\\wrapper\\dists\\gradle-8.5-bin\\h\\gradle-8.5\\lib\\a.jar',
      ),
      ('developer_logs', '$profile\\.gradle\\daemon\\8.5\\registry.bin'),
      ('electron_crash_reports', '$roaming\\Slack\\Crashpad\\settings.dat'),
      (
        'developer_download_cache',
        '$roaming\\Comfy Desktop\\download-cache\\models\\a.safetensors',
      ),
    ]) {
      expect(eligible(id, path), isFalse, reason: path);
    }
  });

  test('developer logs are labelled as logs of their tool', () {
    final daemon = CleanerItemOrigins.of(
      item('developer_logs', '$home/.gradle/daemon/8.5/daemon-1.out.log'),
    );
    expect(daemon.kind, CleanerItemKind.log);
    expect(daemon.app, 'Gradle');
    final editor = CleanerItemOrigins.of(
      item('developer_logs', '$roaming\\Code\\logs\\1\\main.log'),
    );
    expect(editor.kind, CleanerItemKind.log);
    expect(editor.app, 'Code');
  });

  test(
    'real scan of a Linux home keeps installed dependencies and trees',
    () async {
      final root = await Directory.systemTemp.createTemp('cb-linux-dev-');
      addTearDown(() => root.delete(recursive: true));
      final old = DateTime.now().subtract(const Duration(days: 30));
      final expected = <String>{};
      final preserved = <String>{};

      Future<void> file(String relative, {bool eligible = false}) async {
        final path = p.joinAll([root.path, ...relative.split('/')]);
        final entry = File(path);
        await entry.parent.create(recursive: true);
        await entry.writeAsString(relative);
        await entry.setLastModified(old);
        (eligible ? expected : preserved).add(path);
      }

      await file('.cache/pip/http-v2/a/b', eligible: true);
      await file('.cache/go-build/ab/abc-d', eligible: true);
      await file('.gradle/caches/build-cache-1/abc', eligible: true);
      await file(
        '.gradle/wrapper/dists/gradle-8.5-bin/h/gradle-8.5-bin.zip',
        eligible: true,
      );
      await file('.gradle/daemon/8.5/daemon-1.out.log', eligible: true);
      await file('.config/Code/logs/20261001T101010/main.log', eligible: true);
      await file('.config/Slack/Crashpad/reports/a.dmp', eligible: true);
      await file('.gradle/wrapper/dists/gradle-8.5-bin/h/gradle-8.5/a.jar');
      await file(
        '.gradle/wrapper/dists/gradle-8.5-bin/h/gradle-8.5-bin.zip.ok',
      );
      await file(
        '.gradle/wrapper/dists/gradle-8.5-bin/h/gradle-8.5-bin.zip.lck',
      );
      await file('.gradle/daemon/8.5/registry.bin');
      await file('.gradle/caches/modules-2/files-2.1/a.jar');
      await file('.config/Code/User/settings.json');
      await file('.config/Slack/Crashpad/settings.dat');
      await file('.m2/repository/local-only.jar');
      await file('.pub-cache/hosted/pub.dev/a/lib/a.dart');

      final rules = <ResolvedRule>[
        for (final category in [
          ...CleanerCacheRules.linux,
          ...CleanerAuditedRules.linux,
        ])
          for (final rule in category.rules)
            if (CleanerQuickClean.includesRule(category.id, rule))
              ResolvedRule(
                categoryId: category.id,
                basePath: p.joinAll([
                  root.path,
                  ...rule.source.relative.split('/'),
                ]),
                includeGlobs: rule.includeGlobs,
                excludeGlobs: rule.excludeGlobs,
                minAge: rule.minAge,
                recursive: rule.recursive,
                emptyOnly: rule.emptyOnly,
              ),
      ];
      final handle = await spawnScanWithResolvedRules(
        drivesScanned: [root.path],
        rules: rules,
      );
      final report = CleanerQuickClean.select(await handle.future);
      expect(report.allItems.map((i) => i.path).toSet(), expected);
      for (final path in preserved) {
        expect(await File(path).exists(), isTrue, reason: path);
      }
    },
  );
}

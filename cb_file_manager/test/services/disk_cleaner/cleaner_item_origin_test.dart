import 'package:cb_file_manager/services/disk_cleaner/cleaner_item_origin.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:flutter_test/flutter_test.dart';

const String _local = r'C:\Users\me\AppData\Local';
const String _roaming = r'C:\Users\me\AppData\Roaming';

CleanerItemOrigin _of(String categoryId, String path) => CleanerItemOrigins.of(
  JunkItem(
    path: path,
    sizeBytes: 1,
    categoryId: categoryId,
    isRecycleBinItem: categoryId == 'recycle_bin',
  ),
);

void main() {
  group('crash reports name the executable', () {
    test('CrashDumps file name, mapped through the rule hints', () {
      final origin = _of(
        'crash_dumps_logs',
        '$_local\\CrashDumps\\chrome.exe.12345.dmp',
      );
      expect(origin.app, 'Google Chrome');
      expect(origin.kind, CleanerItemKind.crashReport);
      expect(origin.impact, CleanerItemImpact.diagnostic);
    });

    test('an unknown executable keeps its own name', () {
      final origin = _of(
        'crash_dumps_logs',
        '$_local\\CrashDumps\\Notepad++.exe.40.dmp',
      );
      expect(origin.app, 'Notepad++.exe');
      expect(origin.appIsFolder, isFalse);
    });

    test('WER report folders', () {
      final origin = _of(
        'crash_dumps_logs',
        '$_local\\Microsoft\\Windows\\WER\\ReportArchive\\'
            'AppCrash_explorer.exe_6c3f1a_cab_1234\\Report.wer',
      );
      expect(origin.app, 'Windows Explorer');
      expect(origin.kind, CleanerItemKind.crashReport);

      final kernel = _of(
        'crash_dumps_logs',
        '$_local\\Microsoft\\Windows\\WER\\ReportQueue\\'
            'Kernel_141_abc\\memory.dmp',
      );
      expect(kernel.app, 'Windows');
    });

    test('macOS diagnostic reports', () {
      final origin = _of(
        'crash_dumps_logs',
        '/Users/me/Library/Logs/DiagnosticReports/Safari-2026-10-01-120000.ips',
      );
      expect(origin.app, 'Safari');
      expect(origin.kind, CleanerItemKind.crashReport);
    });
  });

  group('caches', () {
    test(
      'package downloads name the tool and explain that it may download again',
      () {
        for (final (path, app) in [
          ('$_local\\npm-cache\\_cacache\\content-v2\\blob', 'npm'),
          ('$_local\\pip\\Cache\\wheels\\a.whl', 'pip'),
          (r'C:\Users\me\.cargo\registry\cache\index\a.crate', 'Cargo'),
          ('$_local\\NuGet\\v3-cache\\a.dat', 'NuGet'),
          ('$_local\\Composer\\files\\vendor\\a.zip', 'Composer'),
          ('/Users/me/.npm/_cacache/blob', 'npm'),
        ]) {
          final origin = _of('package_download_cache', path);
          expect(origin.app, app, reason: path);
          expect(origin.kind, CleanerItemKind.packageDownload);
          expect(origin.impact, CleanerItemImpact.redownload);
        }
      },
    );

    test(
      'system shaders and additional Electron caches keep their source and kind',
      () {
        final shader = _of('system_cache', '$_local\\D3DSCache\\shader.bin');
        expect(shader.app, 'Windows');
        expect(shader.kind, CleanerItemKind.gpuCache);
        expect(shader.impact, CleanerItemImpact.rebuilt);
        final web = _of(
          'electron_cache',
          '$_roaming\\Notion\\Cache\\Cache_Data\\blob',
        );
        expect(web.app, 'Notion');
        expect(web.kind, CleanerItemKind.webCache);
        final code = _of(
          'electron_cache',
          '$_roaming\\Cursor\\Code Cache\\js\\blob',
        );
        expect(code.app, 'Cursor');
        expect(code.kind, CleanerItemKind.codeCache);
        final mac = _of(
          'electron_cache',
          '/Users/me/Library/Application Support/Signal/GPUCache/data_1',
        );
        expect(mac.app, 'Signal');
        expect(mac.kind, CleanerItemKind.gpuCache);
      },
    );

    test('Chrome caches split by kind through the rule table', () {
      const profile = '$_local\\Google\\Chrome\\User Data\\Default';
      expect(
        _of('browser_cache', '$profile\\Cache\\Cache_Data\\f_000001'),
        const CleanerItemOrigin(
          app: 'Google Chrome',
          kind: CleanerItemKind.webCache,
        ),
      );
      expect(
        _of('browser_cache', '$profile\\Code Cache\\js\\abc_0').kind,
        CleanerItemKind.codeCache,
      );
      expect(
        _of('browser_cache', '$profile\\GPUCache\\data_1').kind,
        CleanerItemKind.gpuCache,
      );
    });

    test('mixed case and forward slashes match the same rule', () {
      final origin = _of(
        'app_cache',
        'c:/users/me/appdata/roaming/DISCORD/cache/Cache_Data/f_1',
      );
      expect(origin.app, 'Discord');
      expect(origin.kind, CleanerItemKind.appCache);
      expect(origin.impact, CleanerItemImpact.rebuilt);
    });

    test('Firefox has no owner hint, so its vendor folder names it', () {
      final origin = _of(
        'browser_cache',
        '$_local\\Mozilla\\Firefox\\Profiles\\x1y2.default-release\\'
            'cache2\\entries\\ABCDEF',
      );
      expect(origin.app, 'Firefox');
      expect(origin.kind, CleanerItemKind.webCache);
    });

    test('a second Chrome profile is still Chrome', () {
      expect(
        _of(
          'browser_cache',
          '$_local\\Google\\Chrome\\User Data\\Profile 1\\Cache\\f_1',
        ).app,
        'Google Chrome',
      );
    });

    test('an unknown app is named by its AppData folder', () {
      final origin = _of('app_cache', '$_roaming\\SomeTool\\Cache\\blob');
      expect(origin.app, 'SomeTool');
      expect(origin.appIsFolder, isTrue);
    });

    test('macOS caches by bundle id', () {
      expect(
        _of(
          'browser_cache',
          '/Users/me/Library/Caches/com.apple.Safari/WebKitCache/x',
        ).app,
        'Safari',
      );
    });

    test('thumbnail databases belong to Explorer', () {
      final origin = _of(
        'thumbnail_cache',
        '$_local\\Microsoft\\Windows\\Explorer\\thumbcache_256.db',
      );
      expect(origin.app, 'Windows Explorer');
      expect(origin.kind, CleanerItemKind.thumbnailCache);
    });
  });

  group('%TEMP%', () {
    const temp = '$_local\\Temp';

    test('a named subfolder is shown as that folder', () {
      final origin = _of('windows_temp', '$temp\\SomeVendorSetup\\data.bin');
      expect(origin.app, 'SomeVendorSetup');
      expect(origin.appIsFolder, isTrue);
      expect(origin.kind, CleanerItemKind.tempFile);
      expect(origin.impact, CleanerItemImpact.leftover);
    });

    test('random folder names are not attributed', () {
      for (final folder in [
        '{3F2504E0-4F89-11D3-9A0C-0305E82C3301}',
        '3f2504e04f89',
        'tmpA1B2',
        'scoped_dir1234_5678',
        '123456',
      ]) {
        final origin = _of('windows_temp', '$temp\\$folder\\file.bin');
        expect(origin.app, isNull, reason: folder);
        expect(origin.appIsFolder, isFalse, reason: folder);
      }
    });

    test('known scratch folders name their tool', () {
      expect(
        _of('windows_temp', '$temp\\_MEI12345\\python3.dll').app,
        'PyInstaller',
      );
      final inno = _of('windows_temp', '$temp\\is-AB12C.tmp\\setup.dat');
      expect(inno.app, 'Inno Setup');
      expect(inno.kind, CleanerItemKind.installer);
    });

    test('file kinds by extension', () {
      expect(
        _of('windows_temp', '$temp\\Pkg\\setup.msi').kind,
        CleanerItemKind.installer,
      );
      expect(
        _of('windows_temp', '$temp\\Pkg\\install.log').kind,
        CleanerItemKind.log,
      );
      expect(
        _of('windows_temp', '$temp\\loose.tmp'),
        const CleanerItemOrigin(kind: CleanerItemKind.tempFile),
      );
    });

    test('files directly in %TEMP% with a known name', () {
      final origin = _of('windows_temp', '$temp\\MSI3a7b2.LOG');
      expect(origin.app, 'Windows Installer');
      expect(origin.kind, CleanerItemKind.log);
    });
  });

  test('Recycle Bin entries are deleted files from no particular app', () {
    final origin = _of('recycle_bin', r'C:\$Recycle.Bin\S-1-5\$R1.txt');
    expect(origin.app, isNull);
    expect(origin.kind, CleanerItemKind.deletedFile);
    expect(origin.impact, CleanerItemImpact.permanent);
  });
}

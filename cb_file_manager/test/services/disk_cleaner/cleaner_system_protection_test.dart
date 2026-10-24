import 'package:cb_file_manager/services/disk_cleaner/cleaner_system_protection.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_safety.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_agent_review.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'system protection takes priority over Recycle Bin and AI junk metadata',
    () {
      const path = r'C:\Windows\System32\kernel32.dll';
      expect(
        CleanerPathSafety.isPathSafeToDelete(path, recycleBinItem: true),
        isFalse,
      );
      final group = CleanerReviewGroup(
        id: 'bad-rule',
        scope: 'C:',
        categoryId: 'windows_temp',
        cause: null,
        type: 'file',
      );
      group.add(
        DiskTreeNode(
          name: 'kernel32.dll',
          fullPath: path,
          isFile: true,
          junkCategoryId: 'windows_temp',
        ),
      );
      expect(group.canClean, isFalse);
    },
  );

  test(
    'protects system files, stores, profiles and their critical ancestors',
    () {
      for (final path in [
        r'C:\',
        r'D:\pagefile.sys',
        r'C:\hiberfil.sys',
        r'C:\swapfile.sys',
        r'C:\bootmgr',
        r'C:\EFI\Microsoft\Boot\BCD',
        r'C:\Boot\BCD',
        r'C:\Recovery\WindowsRE\winre.wim',
        r'D:\System Volume Information\restore',
        r'C:\$Extend\$UsnJrnl',
        r'C:\Windows',
        r'D:\Windows\System32\kernel32.dll',
        r'C:\Windows\SysWOW64\example.dll',
        r'C:\Windows\WinSxS\manifest',
        r'C:\Windows\Installer\package.msi',
        r'C:\ProgramData',
        r'C:\ProgramData\Microsoft',
        r'C:\ProgramData\Microsoft\Crypto\keys',
        r'C:\ProgramData\Package Cache\installer',
        r'C:\Program Files',
        r'C:\Program Files\WindowsApps\package',
        r'C:\Users',
        r'C:\Users\person',
        r'C:\Users\person\NTUSER.DAT',
        r'C:\Users\person\NTUSER.DAT.LOG1',
        r'C:\Users\person\AppData\Local\Microsoft\Windows\UsrClass.dat',
        '/System/Library/CoreServices',
        '/usr/bin/env',
        '/private/etc/hosts',
        '/',
      ]) {
        expect(CleanerSystemProtection.isProtected(path), isTrue, reason: path);
      }
    },
  );

  test('keeps junk caches and ordinary manually selected files eligible', () {
    for (final path in [
      r'C:\Windows\Temp',
      r'C:\Windows\Temp\cache.tmp',
      r'C:\Windows\Prefetch\app.pf',
      r'C:\Windows\SoftwareDistribution\Download\update',
      r'C:\Windows\SoftwareDistribution\DeliveryOptimization\cache',
      r'C:\Windows\Minidump\crash.dmp',
      r'C:\Windows\MEMORY.DMP',
      r'C:\Windows\Logs\CBS\log',
      r'C:\Users\person\Downloads\driver.sys',
      r'C:\Backup\hiberfil.sys',
      r'C:\Windows.old',
      r'C:\WindowsBackup\System32\file',
      r'C:\ProgramData\Package Cache Backup\file',
      '/Users/person/Library/Caches/app',
      '/private/var/tmp/cache',
      '',
    ]) {
      expect(CleanerSystemProtection.isProtected(path), isFalse, reason: path);
    }
  });

  test('normalizes Windows aliases before applying cache exceptions', () {
    for (final path in [
      'c:/WINDOWS/system32/kernel32.dll',
      r'C:\Windows\Temp\..\System32\file',
      r'C:\Windows\Temp\.. \System32\file',
      r'\\?\C:\Windows\System32\file',
      r'C:\Windows. \System32\file',
      r'C:\pagefile.sys:stream',
    ]) {
      expect(CleanerSystemProtection.isProtected(path), isTrue, reason: path);
    }
    expect(
      CleanerSystemProtection.isProtected(
        r'E:\Install\WinNT\System32\file',
        environment: {'SystemRoot': r'E:\Install\WinNT'},
      ),
      isTrue,
    );
    expect(
      CleanerSystemProtection.isProtected(
        r'E:\Install',
        environment: {'SystemRoot': r'E:\Install\WinNT'},
      ),
      isTrue,
    );
  });
}

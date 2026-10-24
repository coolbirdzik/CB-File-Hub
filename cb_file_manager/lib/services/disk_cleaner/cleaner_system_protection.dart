import 'dart:io';

import 'package:path/path.dart' as p;

import 'cleaner_paths.dart';

/// Known operating-system data that Cleaner must never delete, even manually
/// selected or with administrator access. This is separate from junk allowlists:
/// ordinary user files remain eligible for explicit, confirmed deletion.
abstract final class CleanerSystemProtection {
  static final _environment = Platform.environment;
  static final _aliasEnding = RegExp(r'[ .]+$');
  static final _trailingSpaces = RegExp(r' +$');

  static bool isProtected(String path, {Map<String, String>? environment}) {
    if (path.isEmpty) return false;
    if (CleanerPaths.isPosix(path)) {
      final value = CleanerPaths.key(path);
      return const [
        '/System',
        '/bin',
        '/sbin',
        '/usr',
        '/private/etc',
        '/private/var/db',
      ].any(
        (root) =>
            CleanerPaths.contains(root, value) ||
            CleanerPaths.contains(value, root),
      );
    }
    final value = _windowsKey(path);
    if (value.length < 3 ||
        value.codeUnitAt(0) < 65 ||
        value.codeUnitAt(0) > 90 ||
        value[1] != ':' ||
        value[2] != r'\') {
      return false;
    }
    final drive = value.substring(0, 3);
    if (value == drive) return true;
    final relative = value.substring(3);
    final env = environment ?? _environment;
    final windowsRoots = <String>{
      '${drive}WINDOWS',
      if (env['SystemRoot'] case final String root) _windowsKey(root),
      if (env['WINDIR'] case final String root) _windowsKey(root),
    };
    for (final root in windowsRoots) {
      if (_contains(value, root)) return true;
      if (!_contains(root, value)) continue;
      // Cache/dump locations already supported by Cleaner remain reviewable.
      // Resolve dot segments before checking these exceptions.
      if (_windowsCleanupLocations.any(
        (suffix) => _contains('$root\\$suffix', value),
      )) {
        return false;
      }
      return true;
    }
    final top = relative.split(r'\').first.split(':').first;
    if (_volumeFiles.contains(top) || _volumeFolders.contains(top)) return true;
    for (final suffix in const [
      r'PROGRAMDATA\MICROSOFT\CRYPTO',
      r'PROGRAMDATA\PACKAGE CACHE',
      r'PROGRAM FILES\WINDOWSAPPS',
    ]) {
      final root = '$drive$suffix';
      if (_contains(root, value) || _contains(value, root)) return true;
    }
    // Profile roots contain registry hives; browsing their contents is allowed.
    final parts = relative.split(r'\');
    if (parts.first == 'USERS') {
      if (parts.length <= 2) return true;
      final name = parts.last.split(':').first;
      if (parts.length == 3 &&
          (name == 'NTUSER.DAT' || name.startsWith('NTUSER.DAT.'))) {
        return true;
      }
      final profile = parts.take(2).join(r'\');
      final hive =
          '$drive$profile\\APPDATA\\LOCAL\\MICROSOFT\\WINDOWS\\USRCLASS.DAT';
      if (_contains(value, hive) || value.startsWith('$hive.')) {
        return true;
      }
    }
    return false;
  }

  static String _windowsKey(String path) {
    var value = path.trim().replaceAll('/', r'\');
    if (value.startsWith('\\\\?\\')) value = value.substring(4);
    final stream = value.indexOf(':', 2);
    if (stream >= 0) value = value.substring(0, stream);
    // Win32 treats trailing spaces/dots in path segments as aliases.
    if (value.contains('.\\') ||
        value.contains(' \\') ||
        value.endsWith('.') ||
        value.endsWith(' ')) {
      value = value
          .split(r'\')
          .map((part) {
            final trimmed = part.replaceFirst(_trailingSpaces, '');
            // Keep parent/current segments for the normalization step below.
            return trimmed == '.' || trimmed == '..'
                ? trimmed
                : trimmed.replaceFirst(_aliasEnding, '');
          })
          .join(r'\');
    }
    if (value.contains(r'\.') || value.contains(r'\\')) {
      value = p.windows.normalize(value);
    }
    return value.toUpperCase();
  }

  static bool _contains(String root, String value) =>
      value == root || value.startsWith('$root\\');

  static const _windowsCleanupLocations = [
    'TEMP',
    'PREFETCH',
    r'SOFTWAREDISTRIBUTION\DOWNLOAD',
    r'SOFTWAREDISTRIBUTION\DELIVERYOPTIMIZATION',
    'MEMORY.DMP',
    'MINIDUMP',
    'LIVEKERNELREPORTS',
    'LOGS',
  ];
  static const _volumeFiles = {
    'HIBERFIL.SYS',
    'PAGEFILE.SYS',
    'SWAPFILE.SYS',
    'BOOTMGR',
    'BOOTNXT',
    'BOOTSECT.BAK',
    'NTLDR',
    'NTDETECT.COM',
    'IO.SYS',
    'MSDOS.SYS',
    r'$MFT',
    r'$MFTMIRR',
    r'$LOGFILE',
    r'$BITMAP',
    r'$SECURE',
    r'$BOOT',
    r'$BADCLUS',
    r'$UPCASE',
    r'$VOLUME',
    r'$ATTRDEF',
  };
  static const _volumeFolders = {
    'BOOT',
    'EFI',
    'RECOVERY',
    'SYSTEM VOLUME INFORMATION',
    r'$EXTEND',
  };
}

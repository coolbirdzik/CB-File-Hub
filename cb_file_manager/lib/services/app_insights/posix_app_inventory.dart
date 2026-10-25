import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'app_insights_models.dart';
import 'app_leftover_finder.dart';

/// Lists installed apps on macOS and Linux for the leftover scan.
///
/// macOS: every `.app` bundle in the usual folders plus whatever Spotlight
/// knows about. Linux: desktop entries, `flatpak list`, `snap list` and the
/// installed packages. Both add the commands on `PATH`, since CLI tools keep
/// config folders too.
class PosixAppInventoryLoader {
  final Map<String, String> environment;
  final String operatingSystem;

  const PosixAppInventoryLoader({
    required this.environment,
    required this.operatingSystem,
  });

  Future<AppLeftoverInventory> load() {
    final env = environment;
    final os = operatingSystem;
    return Isolate.run(() => os == 'macos' ? _loadMacos(env) : _loadLinux(env));
  }
}

Future<AppLeftoverInventory> _loadMacos(Map<String, String> env) async {
  final home = env['HOME'] ?? '';
  final bundles = <String>{};

  void collect(String directory, int depth) {
    List<FileSystemEntity> entries;
    try {
      entries = Directory(directory).listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in entries) {
      if (entity is! Directory) continue;
      if (entity.path.endsWith('.app')) {
        bundles.add(entity.path);
      } else if (depth > 0) {
        collect(entity.path, depth - 1);
      }
    }
  }

  for (final root in <String>[
    '/Applications',
    '/System/Applications',
    '/System/Library/CoreServices',
    if (home.isNotEmpty) '$home/Applications',
  ]) {
    collect(root, 2);
  }
  // Spotlight also finds apps run from Downloads or external folders.
  final spotlight = await _run('mdfind', <String>[
    'kMDItemContentType == "com.apple.application-bundle"',
  ]);
  if (spotlight != null) {
    for (final line in spotlight.split('\n')) {
      final path = line.trim();
      if (path.endsWith('.app')) bundles.add(path);
    }
  }

  final apps = <InstalledAppInfo>[];
  for (final bundle in bundles) {
    final info = await _readInfoPlist('$bundle/Contents/Info.plist');
    if (info == null) continue;
    final app = macAppFromInfoPlist(bundle, info);
    if (app != null) apps.add(app);
  }
  apps.addAll(
    _executables(<String>[
      ...?env['PATH']?.split(':'),
      '/usr/libexec',
      '/usr/sbin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
    ]),
  );
  return AppLeftoverInventory(apps: apps);
}

Future<AppLeftoverInventory> _loadLinux(Map<String, String> env) async {
  final home = env['HOME'] ?? '';
  final dataHome = env['XDG_DATA_HOME'] ?? '$home/.local/share';
  final dataDirs = (env['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
      .split(':')
      .where((dir) => dir.isNotEmpty);
  final applicationDirs = <String>{
    for (final dir in <String>[
      dataHome,
      ...dataDirs,
      '/var/lib/flatpak/exports/share',
      '$dataHome/flatpak/exports/share',
    ])
      '$dir/applications',
    '/var/lib/snapd/desktop/applications',
  };

  final apps = <InstalledAppInfo>[];
  final seen = <String>{};
  for (final dir in applicationDirs) {
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(recursive: true, followLinks: true);
    } on FileSystemException {
      continue;
    }
    for (final entity in entries) {
      if (entity is! File || !entity.path.endsWith('.desktop')) continue;
      final id = p.basename(entity.path);
      if (!seen.add(id)) continue;
      try {
        final app = linuxAppFromDesktopEntry(id, entity.readAsStringSync());
        if (app != null) apps.add(app);
      } on FileSystemException {
        // Unreadable entries are skipped.
      }
    }
  }

  final flatpak = await _listOrNull('flatpak', <String>[
    'list',
    '--app',
    '--columns=application',
  ]);
  final snapOutput = await _listOrNull('snap', <String>['list']);
  final snaps = snapOutput?.skip(1).map((line) => line.split(' ').first);

  final packages =
      await _listOrNull('dpkg-query', <String>[
        '-W',
        r'--showformat=${Package}\n',
      ]) ??
      await _listOrNull('rpm', <String>['-qa', '--qf', r'%{NAME}\n']) ??
      await _listOrNull('pacman', <String>['-Qq']) ??
      const <String>[];

  apps.addAll(
    _executables(<String>[
      ...?env['PATH']?.split(':'),
      '/usr/libexec',
      '/usr/lib/systemd/user',
    ]),
  );
  for (final name in packages.toSet()) {
    apps.add(
      InstalledAppInfo(
        id: 'pkg:$name',
        displayName: name,
        source: InstalledAppSource.executable,
      ),
    );
  }
  for (final id in flatpak ?? const <String>[]) {
    apps.add(
      InstalledAppInfo(
        id: 'flatpak:$id',
        displayName: id.substring(id.lastIndexOf('.') + 1),
        source: InstalledAppSource.linuxDesktop,
        packageFamilyName: id,
      ),
    );
  }
  return AppLeftoverInventory(
    apps: apps,
    flatpakApps: flatpak?.toSet(),
    snaps: snaps?.where((name) => name.isNotEmpty).toSet(),
  );
}

/// Builds an app from a bundle's `Info.plist` values.
InstalledAppInfo? macAppFromInfoPlist(
  String bundlePath,
  Map<String, String> info,
) {
  final bundleName = bundlePath
      .substring(bundlePath.lastIndexOf('/') + 1)
      .replaceFirst(RegExp(r'\.app$'), '');
  final id = info['CFBundleIdentifier'];
  final name =
      info['CFBundleDisplayName'] ?? info['CFBundleName'] ?? bundleName;
  if (name.isEmpty) return null;
  final executable = info['CFBundleExecutable'];
  final idParts = id?.split('.') ?? const <String>[];
  return InstalledAppInfo(
    id: 'mac:${id ?? bundlePath}',
    displayName: name == bundleName ? name : '$name ($bundleName)',
    // `com.google.Chrome` → `google`, so vendor folders match.
    publisher: idParts.length >= 3 ? idParts[1] : null,
    version: info['CFBundleShortVersionString'],
    source: InstalledAppSource.macApp,
    installLocation: bundlePath,
    packageFamilyName: id,
    executablePaths: <String>[
      if (executable != null && executable.isNotEmpty)
        '$bundlePath/Contents/MacOS/$executable',
    ],
  );
}

/// Parses the string values of an XML property list.
Map<String, String> parseXmlPlistStrings(String xml) {
  final values = <String, String>{};
  final pattern = RegExp(r'<key>([^<]+)</key>\s*<string>([^<]*)</string>');
  for (final match in pattern.allMatches(xml)) {
    values.putIfAbsent(match.group(1)!, () => _unescapeXml(match.group(2)!));
  }
  return values;
}

String _unescapeXml(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

Future<Map<String, String>?> _readInfoPlist(String path) async {
  try {
    final bytes = File(path).readAsBytesSync();
    final isBinary =
        bytes.length > 6 && String.fromCharCodes(bytes.take(6)) == 'bplist';
    if (!isBinary) {
      return parseXmlPlistStrings(utf8.decode(bytes, allowMalformed: true));
    }
    final xml = await _run('plutil', <String>[
      '-convert',
      'xml1',
      '-o',
      '-',
      path,
    ]);
    return xml == null ? null : parseXmlPlistStrings(xml);
  } on FileSystemException {
    return null;
  }
}

/// Builds an app from a `.desktop` file. Hidden and non-application entries
/// still count: they name the app that owns a config folder.
InstalledAppInfo? linuxAppFromDesktopEntry(String fileName, String content) {
  final values = <String, String>{};
  var inEntry = false;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inEntry = line == '[Desktop Entry]';
      continue;
    }
    if (!inEntry) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values.putIfAbsent(
      line.substring(0, separator).trim(),
      () => line.substring(separator + 1).trim(),
    );
  }
  final id = fileName.replaceFirst(RegExp(r'\.desktop$'), '');
  final name = values['Name'] ?? id;
  final exec = values['Exec']
      ?.split(RegExp(r'\s+'))
      .firstWhere(
        (part) => part.isNotEmpty && !part.contains('='),
        orElse: () => '',
      );
  final wmClass = values['StartupWMClass'];
  return InstalledAppInfo(
    id: 'desktop:$id',
    displayName: wmClass == null || wmClass.isEmpty ? name : '$name ($wmClass)',
    source: InstalledAppSource.linuxDesktop,
    packageFamilyName: id,
    displayIconPath: values['Icon'],
    executablePaths: <String>[
      if (exec != null && exec.isNotEmpty) exec.replaceAll('"', ''),
    ],
  );
}

List<InstalledAppInfo> _executables(Iterable<String> directories) {
  final names = <String, String>{};
  for (final directory in directories.toSet()) {
    if (directory.isEmpty) continue;
    List<FileSystemEntity> entries;
    try {
      entries = Directory(directory).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final entity in entries) {
      final name = p.basename(entity.path);
      if (name.isEmpty || name.startsWith('.')) continue;
      names.putIfAbsent(name, () => entity.path);
    }
  }
  return <InstalledAppInfo>[
    for (final entry in names.entries)
      InstalledAppInfo(
        id: 'exe:${entry.key}',
        displayName: entry.key,
        source: InstalledAppSource.executable,
        executablePaths: <String>[entry.value],
      ),
  ];
}

/// Output lines, or null when the command is missing or fails. A command
/// that does not exist at all yields an empty list: nothing is installed.
Future<List<String>?> _listOrNull(String command, List<String> args) async {
  try {
    final result = await Process.run(
      command,
      args,
    ).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) return null;
    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  } on ProcessException {
    return command == 'flatpak' || command == 'snap' ? const <String>[] : null;
  } on TimeoutException {
    return null;
  }
}

Future<String?> _run(String command, List<String> args) async {
  try {
    final result = await Process.run(
      command,
      args,
    ).timeout(const Duration(seconds: 20));
    return result.exitCode == 0 ? result.stdout.toString() : null;
  } on ProcessException {
    return null;
  } on TimeoutException {
    return null;
  }
}

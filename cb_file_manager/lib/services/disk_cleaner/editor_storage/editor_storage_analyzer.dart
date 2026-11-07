import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_storage/chromium_layout.dart';
import 'editor_root_sizes.dart';
import 'editor_storage_models.dart';

/// Reads what VS Code family editors keep on disk: each extension's install
/// folder and storage, per-workspace state and the data folder by kind.
///
/// Only reads. The editor's own registries (`extensions.json`, `.obsolete`,
/// `state.vscdb`, `storage.json`) are never written; cleanup goes through
/// the Cleaner's Trash pipeline as whole folders.
///
/// All folders are collected first and sized in one [EditorRootSizer] call
/// (one Rust walk when the native library is present). Roots never overlap,
/// so no folder is read twice.
class EditorStorageAnalyzer {
  /// Logs and downloaded installers younger than this may be in use.
  static const minAge = Duration(days: 1);

  static const _cacheFolders = ChromiumLayout.cacheFolders;
  static const _webStorageFolders = ChromiumLayout.webStorageFolders;
  static const _crashReportFolders = ChromiumLayout.crashReportFolders;

  final EditorStorageEnvironment environment;
  final EditorRootSizer sizer;
  final DateTime Function() now;

  /// Whether a process id from the editor's `code.lock` is running.
  final bool Function(int pid) isProcessAlive;

  EditorStorageAnalyzer({
    required this.environment,
    EditorRootSizer? sizer,
    DateTime Function()? now,
    bool Function(int pid)? isProcessAlive,
  }) : sizer = sizer ?? editorRootSizes,
       now = now ?? DateTime.now,
       isProcessAlive = isProcessAlive ?? defaultProcessAlive;

  /// The current user's folders, or null on an unsupported platform.
  static EditorStorageEnvironment? currentEnvironment() {
    final env = Platform.environment;
    final os = Platform.operatingSystem;
    final home = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
    if (home == null || home.isEmpty) return null;
    if (os != 'macos' && os != 'linux' && os != 'windows') return null;
    return EditorStorageEnvironment(
      operatingSystem: os,
      home: home,
      appData: env['APPDATA'],
    );
  }

  static bool defaultProcessAlive(int pid) {
    try {
      if (Platform.isLinux) return Directory('/proc/$pid').existsSync();
      if (Platform.isMacOS) {
        final result = Process.runSync('ps', ['-p', '$pid', '-o', 'pid=']);
        return result.exitCode == 0 &&
            result.stdout.toString().trim().isNotEmpty;
      }
      if (Platform.isWindows) {
        final result = Process.runSync('tasklist', [
          '/FI',
          'PID eq $pid',
          '/NH',
          '/FO',
          'CSV',
        ]);
        return result.stdout.toString().contains('"$pid"');
      }
    } on ProcessException {
      // Unknown: treat as running so caches are left alone.
      return true;
    }
    return false;
  }

  Future<List<EditorStorageReport>> analyze({
    List<EditorProduct> editors = EditorProduct.all,
  }) async {
    final roots = _Roots();
    final plans = [for (final editor in editors) ?_plan(editor, roots)];
    final sizes = await sizer(roots.paths);
    return [
      for (final plan in plans)
        if (plan.build(sizes) case final report when !report.isEmpty) report,
    ];
  }

  _EditorPlan? _plan(EditorProduct editor, _Roots roots) {
    final path = environment.path;
    final dataRoot = environment.dataRoot(editor);
    final extensionsRoot = environment.extensionsRoot(editor);
    final hasData = dataRoot != null && _isDirectory(dataRoot);
    final hasExtensions = _isDirectory(extensionsRoot);
    if (!hasData && !hasExtensions) return null;

    final plan = _EditorPlan(
      editor: editor,
      dataRoot: hasData ? dataRoot : null,
      extensionsRoot: hasExtensions ? extensionsRoot : null,
      isRunning: hasData && _isRunning(dataRoot),
    );
    final user = hasData ? path.join(dataRoot, 'User') : null;
    final profiles = user == null
        ? const <String>[]
        : _children(path.join(user, 'profiles'))
              .where((child) => child.isDirectory)
              .map((child) => child.path)
              .toList();

    // Extensions: listed by any profile, or obsolete, or neither.
    if (hasExtensions) {
      final listed = _listedExtensionFolders(extensionsRoot, profiles);
      final obsolete = _jsonKeys(path.join(extensionsRoot, '.obsolete'));
      for (final child in _children(extensionsRoot)) {
        if (!child.isDirectory || child.name.startsWith('.')) continue;
        final manifest = _manifest(child.path, child.name);
        if (manifest == null) continue;
        final status = listed == null || listed.contains(child.name)
            ? EditorExtensionStatus.installed
            : obsolete.contains(child.name)
            ? EditorExtensionStatus.obsolete
            : EditorExtensionStatus.unregistered;
        plan.extensions.add(
          _ExtensionPlan(
            manifest: manifest,
            path: child.path,
            status: status,
            root: roots.add(child.path),
          ),
        );
      }
    }
    final extensionIds = {for (final e in plan.extensions) e.manifest.id};

    if (!hasData) return plan;
    for (final child in _children(dataRoot)) {
      final name = child.name.toLowerCase();
      if (name == 'user' && child.isDirectory) {
        _planUser(plan, roots, child.path, profiles, extensionIds);
      } else if (name == 'code.lock' || name.endsWith('.sock')) {
        continue;
      } else if (_cacheFolders.contains(name) && child.isDirectory) {
        final root = roots.add(child.path);
        plan.data(EditorDataKind.cache, child.path, root);
        if (!plan.isRunning) plan.cleanable(EditorDataKind.cache, root);
      } else if (name == 'cachedextensionvsixs' && child.isDirectory) {
        _planAged(plan, roots, child.path, EditorDataKind.extensionDownloads);
      } else if (name == 'logs' && child.isDirectory) {
        _planAged(
          plan,
          roots,
          child.path,
          EditorDataKind.logs,
          keepNewest: true,
        );
      } else if (name == 'crashpad' && child.isDirectory) {
        _planCrashpad(plan, roots, child.path);
      } else {
        final kind = _webStorageFolders.contains(name)
            ? EditorDataKind.webStorage
            : EditorDataKind.other;
        plan.data(kind, child.path, roots.add(child.path));
      }
    }
    return plan;
  }

  void _planUser(
    _EditorPlan plan,
    _Roots roots,
    String user,
    List<String> profiles,
    Set<String> extensionIds,
  ) {
    for (final child in _children(user)) {
      switch (child.name) {
        case 'globalStorage' when child.isDirectory:
          _planGlobalStorage(plan, roots, child.path, extensionIds);
        case 'workspaceStorage' when child.isDirectory:
          for (final workspace in _children(child.path)) {
            if (workspace.isDirectory) {
              _planWorkspace(plan, roots, workspace.path, extensionIds);
            }
          }
        case 'History' when child.isDirectory:
          plan.data(
            EditorDataKind.localHistory,
            child.path,
            roots.add(child.path),
          );
        case 'profiles' when child.isDirectory:
          for (final profile in profiles) {
            for (final entry in _children(profile)) {
              if (entry.name == 'globalStorage' && entry.isDirectory) {
                _planGlobalStorage(plan, roots, entry.path, extensionIds);
              } else {
                plan.data(
                  EditorDataKind.settings,
                  entry.path,
                  roots.add(entry.path),
                );
              }
            }
          }
          // Files next to the profile folders (the profile index).
          for (final entry in _children(child.path)) {
            if (!entry.isDirectory) {
              plan.data(
                EditorDataKind.settings,
                entry.path,
                roots.add(entry.path),
              );
            }
          }
        default:
          plan.data(EditorDataKind.settings, child.path, roots.add(child.path));
      }
    }
  }

  void _planGlobalStorage(
    _EditorPlan plan,
    _Roots roots,
    String globalStorage,
    Set<String> extensionIds,
  ) {
    for (final child in _children(globalStorage)) {
      final root = roots.add(child.path);
      final id = child.name.toLowerCase();
      if (child.isDirectory && extensionIds.contains(id)) {
        plan.globalStorage.putIfAbsent(id, () => []).add(root);
      } else if (child.isDirectory && _looksLikeExtensionId(id)) {
        plan.orphanData.putIfAbsent(id, () => []).add((child.path, root));
      } else {
        // `state.vscdb`, `storage.json` and editor-owned folders.
        plan.data(EditorDataKind.settings, child.path, root);
      }
    }
  }

  void _planWorkspace(
    _EditorPlan plan,
    _Roots roots,
    String folder,
    Set<String> extensionIds,
  ) {
    final (target, status) = _workspaceTarget(folder);
    final workspace = _WorkspacePlan(
      path: folder,
      target: target,
      status: status,
    );
    for (final child in _children(folder)) {
      final root = roots.add(child.path);
      workspace.roots.add(root);
      final id = child.name.toLowerCase();
      if (child.isDirectory && extensionIds.contains(id)) {
        plan.workspaceStorage.putIfAbsent(id, () => []).add(root);
      }
    }
    plan.workspaces.add(workspace);
  }

  /// Children unchanged for [minAge] are cleanable, except the newest one
  /// when [keepNewest]: log sessions are named by start time, so that is the
  /// session a running editor writes to.
  void _planAged(
    _EditorPlan plan,
    _Roots roots,
    String folder,
    EditorDataKind kind, {
    bool keepNewest = false,
  }) {
    final children = _children(folder).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final cutoff = now().subtract(minAge);
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final root = roots.add(child.path);
      plan.data(kind, child.path, root);
      final newest = keepNewest && i == children.length - 1;
      final modified = child.modified;
      if (newest || modified == null || modified.isAfter(cutoff)) continue;
      plan.cleanable(kind, root);
    }
  }

  void _planCrashpad(_EditorPlan plan, _Roots roots, String crashpad) {
    final cutoff = now().subtract(minAge);
    for (final child in _children(crashpad)) {
      if (child.isDirectory &&
          _crashReportFolders.contains(child.name.toLowerCase())) {
        for (final report in _children(child.path)) {
          final root = roots.add(report.path);
          plan.data(EditorDataKind.crashReports, report.path, root);
          final modified = report.modified;
          if (!report.isDirectory &&
              report.name.toLowerCase().endsWith('.dmp') &&
              modified != null &&
              !modified.isAfter(cutoff)) {
            plan.cleanable(EditorDataKind.crashReports, root);
          }
        }
      } else {
        // `settings.dat`, `attachments`, the client id: kept.
        plan.data(
          EditorDataKind.crashReports,
          child.path,
          roots.add(child.path),
        );
      }
    }
  }

  bool _isRunning(String dataRoot) {
    final lock = File(environment.path.join(dataRoot, 'code.lock'));
    try {
      final pid = int.tryParse(lock.readAsStringSync().trim());
      return pid != null && isProcessAlive(pid);
    } on FileSystemException {
      return false;
    }
  }

  /// Folder names of installed extensions across every profile, or null
  /// when the default registry cannot be read (then nothing is judged).
  Set<String>? _listedExtensionFolders(
    String extensionsRoot,
    List<String> profiles,
  ) {
    final path = environment.path;
    final main = _jsonList(path.join(extensionsRoot, 'extensions.json'));
    if (main == null) return null;
    final listed = <String>{};
    for (final list in [
      main,
      for (final profile in profiles)
        ?_jsonList(path.join(profile, 'extensions.json')),
    ]) {
      for (final entry in list) {
        if (entry is! Map) continue;
        final relative = entry['relativeLocation'];
        if (relative is String && relative.isNotEmpty) {
          listed.add(relative);
          continue;
        }
        final location = entry['location'];
        final locationPath = location is Map
            ? (location['fsPath'] ?? location['path'])
            : location;
        if (locationPath is String && locationPath.isNotEmpty) {
          listed.add(_lastSegment(locationPath));
        }
      }
    }
    return listed;
  }

  _Manifest? _manifest(String folder, String folderName) {
    final path = environment.path;
    final json = _jsonMap(path.join(folder, 'package.json'));
    final publisher = json?['publisher'];
    final name = json?['name'];
    final version = json?['version'];
    if (publisher is String && name is String) {
      var displayName = json?['displayName'];
      if (displayName is String &&
          displayName.length > 2 &&
          displayName.startsWith('%') &&
          displayName.endsWith('%')) {
        final nls = _jsonMap(path.join(folder, 'package.nls.json'));
        final localized =
            nls?[displayName.substring(1, displayName.length - 1)];
        displayName = localized is String
            ? localized
            : localized is Map && localized['message'] is String
            ? localized['message']
            : null;
      }
      final icon = json?['icon'];
      final iconPath = icon is String && icon.isNotEmpty
          ? path.normalize(path.join(folder, icon))
          : null;
      return _Manifest(
        id: '$publisher.$name'.toLowerCase(),
        version: version is String ? version : '',
        // Only an image inside the extension's own folder.
        iconPath:
            iconPath != null &&
                path.isWithin(folder, iconPath) &&
                File(iconPath).existsSync()
            ? iconPath
            : null,
        displayName: displayName is String && displayName.trim().isNotEmpty
            ? displayName.trim()
            : name,
      );
    }
    // No readable manifest: `publisher.name-1.2.3[-platform]`.
    final match = RegExp(
      r'^([^.\s]+\.[^\s]+?)-(\d+\.\d+[^-]*)(?:-.+)?$',
    ).firstMatch(folderName);
    if (match == null) return null;
    final id = match.group(1)!.toLowerCase();
    return _Manifest(
      id: id,
      version: match.group(2)!,
      displayName: id.substring(id.indexOf('.') + 1),
    );
  }

  (String, EditorWorkspaceStatus) _workspaceTarget(String folder) {
    final json = _jsonMap(environment.path.join(folder, 'workspace.json'));
    final value = json?['folder'] ?? json?['workspace'];
    if (value is! String || value.isEmpty) {
      return ('', EditorWorkspaceStatus.unknown);
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'file') {
      return (value, EditorWorkspaceStatus.unknown);
    }
    final windows =
        environment.operatingSystem == 'windows' ||
        (environment.path.style == p.Style.windows &&
            RegExp(r'^/[A-Za-z]:/').hasMatch(uri.path));
    final String target;
    try {
      target = uri.toFilePath(windows: windows);
    } on UnsupportedError {
      return (value, EditorWorkspaceStatus.unknown);
    }
    // A network share may take seconds to time out; do not probe it.
    if (windows && target.startsWith(r'\\')) {
      return (target, EditorWorkspaceStatus.unknown);
    }
    if (_exists(target)) return (target, EditorWorkspaceStatus.present);
    final volume = _volumeRoot(target);
    if (volume != null && !_isMounted(volume)) {
      return (target, EditorWorkspaceStatus.offline);
    }
    return (target, EditorWorkspaceStatus.missing);
  }

  /// The drive or removable-volume root holding [target], when it has one.
  String? _volumeRoot(String target) {
    if (environment.operatingSystem == 'windows') {
      final match = RegExp(r'^[A-Za-z]:\\').firstMatch(target);
      return match?.group(0);
    }
    final parts = target.split('/');
    // ['', 'Volumes', 'Disk', ...] and the Linux mount points.
    if (environment.operatingSystem == 'macos') {
      return parts.length > 2 && parts[1] == 'Volumes'
          ? parts.take(3).join('/')
          : null;
    }
    if (parts.length > 3 && parts[1] == 'run' && parts[2] == 'media') {
      return parts.length > 4 ? parts.take(5).join('/') : null;
    }
    if (parts.length > 2 && (parts[1] == 'media' || parts[1] == 'mnt')) {
      final depth = parts[1] == 'media' ? 4 : 3;
      return parts.length >= depth ? parts.take(depth).join('/') : null;
    }
    return null;
  }

  /// A mount point left behind empty is not mounted.
  bool _isMounted(String volume) {
    if (!_isDirectory(volume)) return false;
    if (environment.operatingSystem == 'windows') return true;
    try {
      return Directory(volume).listSync().isNotEmpty;
    } on FileSystemException {
      return false;
    }
  }

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  static bool _isDirectory(String path) =>
      FileSystemEntity.isDirectorySync(path);

  static bool _looksLikeExtensionId(String name) {
    final dot = name.indexOf('.');
    return dot > 0 && dot < name.length - 1 && !name.contains(' ');
  }

  String _lastSegment(String location) {
    final trimmed = location.replaceAll(RegExp(r'[\\/]+$'), '');
    final index = trimmed.lastIndexOf(RegExp(r'[\\/]'));
    return index < 0 ? trimmed : trimmed.substring(index + 1);
  }

  Iterable<_Entry> _children(String folder) sync* {
    final List<FileSystemEntity> entities;
    try {
      entities = Directory(folder).listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    final path = environment.path;
    for (final entity in entities) {
      DateTime? modified;
      try {
        modified = entity.statSync().modified;
      } on FileSystemException {
        modified = null;
      }
      yield _Entry(
        path: entity.path,
        name: path.basename(entity.path),
        isDirectory: entity is Directory,
        modified: modified,
      );
    }
  }

  static Object? _json(String file) {
    try {
      return jsonDecode(File(file).readAsStringSync());
    } on Object {
      return null;
    }
  }

  static Map<String, Object?>? _jsonMap(String file) {
    final value = _json(file);
    return value is Map<String, Object?> ? value : null;
  }

  static List<Object?>? _jsonList(String file) {
    final value = _json(file);
    return value is List<Object?> ? value : null;
  }

  static Set<String> _jsonKeys(String file) =>
      _jsonMap(file)?.keys.toSet() ?? const <String>{};
}

class _Entry {
  final String path;
  final String name;
  final bool isDirectory;
  final DateTime? modified;

  const _Entry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.modified,
  });
}

class _Roots {
  final paths = <String>[];

  int add(String path) {
    paths.add(path);
    return paths.length - 1;
  }
}

class _Manifest {
  final String id;
  final String version;
  final String displayName;
  final String? iconPath;

  const _Manifest({
    required this.id,
    required this.version,
    required this.displayName,
    this.iconPath,
  });
}

class _ExtensionPlan {
  final _Manifest manifest;
  final String path;
  final EditorExtensionStatus status;
  final int root;

  const _ExtensionPlan({
    required this.manifest,
    required this.path,
    required this.status,
    required this.root,
  });
}

class _WorkspacePlan {
  final String path;
  final String target;
  final EditorWorkspaceStatus status;
  final roots = <int>[];

  _WorkspacePlan({
    required this.path,
    required this.target,
    required this.status,
  });
}

class _EditorPlan {
  final EditorProduct editor;
  final String? dataRoot;
  final String? extensionsRoot;
  final bool isRunning;
  final extensions = <_ExtensionPlan>[];
  final globalStorage = <String, List<int>>{};
  final workspaceStorage = <String, List<int>>{};
  final orphanData = <String, List<(String, int)>>{};
  final workspaces = <_WorkspacePlan>[];
  final _data = <EditorDataKind, List<(String, int)>>{};
  final _cleanable = <EditorDataKind, List<int>>{};

  _EditorPlan({
    required this.editor,
    required this.dataRoot,
    required this.extensionsRoot,
    required this.isRunning,
  });

  void data(EditorDataKind kind, String path, int root) =>
      _data.putIfAbsent(kind, () => []).add((path, root));

  void cleanable(EditorDataKind kind, int root) =>
      _cleanable.putIfAbsent(kind, () => []).add(root);

  EditorStorageReport build(List<EditorRootSize> sizes) {
    final paths = <int, String>{
      for (final entries in _data.values)
        for (final (path, root) in entries) root: path,
    };
    int bytes(Iterable<int> roots) =>
        roots.fold<int>(0, (sum, root) => sum + sizes[root].bytes);

    final extensionList = [
      for (final e in extensions)
        EditorExtensionUsage(
          id: e.manifest.id,
          version: e.manifest.version,
          displayName: e.manifest.displayName,
          path: e.path,
          iconPath: e.manifest.iconPath,
          status: e.status,
          installBytes: sizes[e.root].bytes,
          // Storage belongs to the id; older versions of the same id share
          // it, so only the listed (or newest) folder carries it.
          globalStorageBytes: _ownsStorage(e)
              ? bytes(globalStorage[e.manifest.id] ?? const [])
              : 0,
          workspaceStorageBytes: _ownsStorage(e)
              ? bytes(workspaceStorage[e.manifest.id] ?? const [])
              : 0,
        ),
    ]..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    final data = [
      for (final MapEntry(key: kind, value: entries) in _data.entries)
        EditorDataUsage(
          kind: kind,
          paths: [for (final (path, _) in entries) path],
          bytes: bytes(entries.map((entry) => entry.$2)),
          cleanable: [
            for (final root in _cleanable[kind] ?? const <int>[])
              if (sizes[root].exists)
                EditorCleanTarget(paths[root]!, sizes[root].bytes),
          ],
        ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));

    return EditorStorageReport(
      editor: editor,
      dataRoot: dataRoot,
      extensionsRoot: extensionsRoot,
      isRunning: isRunning,
      extensions: extensionList,
      orphanedExtensionData: [
        for (final MapEntry(key: id, value: entries) in orphanData.entries)
          EditorExtensionData(
            id: id,
            paths: [for (final (path, _) in entries) path],
            bytes: bytes(entries.map((entry) => entry.$2)),
          ),
      ]..sort((a, b) => b.bytes.compareTo(a.bytes)),
      workspaces: [
        for (final w in workspaces)
          EditorWorkspaceUsage(
            path: w.path,
            target: w.target,
            status: w.status,
            bytes: bytes(w.roots),
          ),
      ]..sort((a, b) => b.bytes.compareTo(a.bytes)),
      data: data,
      unreadable: sizes.fold<int>(0, (sum, size) => sum + size.unreadable),
    );
  }

  /// The installed folder of an id owns its storage; without one, the
  /// first folder found does.
  bool _ownsStorage(_ExtensionPlan plan) {
    final sameId = extensions.where((e) => e.manifest.id == plan.manifest.id);
    final installed = sameId.where(
      (e) => e.status == EditorExtensionStatus.installed,
    );
    return identical(
      installed.isNotEmpty ? installed.first : sameId.first,
      plan,
    );
  }
}

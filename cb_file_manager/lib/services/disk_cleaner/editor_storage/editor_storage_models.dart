import 'package:path/path.dart' as p;
import '../storage_path_context.dart';

/// A VS Code family editor: where it keeps its data and its extensions.
class EditorProduct {
  /// Shown to the user.
  final String name;

  /// Folder under Application Support (macOS), `%APPDATA%` (Windows) or
  /// `~/.config` (Linux).
  final String dataFolder;

  /// Dot-folder under the home folder holding `extensions/`.
  final String homeFolder;

  const EditorProduct(this.name, this.dataFolder, this.homeFolder);

  static const all = <EditorProduct>[
    EditorProduct('Visual Studio Code', 'Code', '.vscode'),
    EditorProduct('VS Code Insiders', 'Code - Insiders', '.vscode-insiders'),
    EditorProduct('VSCodium', 'VSCodium', '.vscode-oss'),
    EditorProduct('Cursor', 'Cursor', '.cursor'),
    EditorProduct('Windsurf', 'Windsurf', '.windsurf'),
    EditorProduct('Antigravity', 'Antigravity', '.antigravity'),
    EditorProduct('Kiro', 'Kiro', '.kiro'),
  ];
}

/// Where the current user's editor folders are.
class EditorStorageEnvironment {
  /// `macos`, `windows` or `linux`.
  final String operatingSystem;
  final String home;

  /// `%APPDATA%` on Windows.
  final String? appData;

  const EditorStorageEnvironment({
    required this.operatingSystem,
    required this.home,
    this.appData,
  });

  p.Context get path => storagePathContext(home);

  String? dataRoot(EditorProduct editor) => switch (operatingSystem) {
    'macos' => path.join(
      home,
      'Library',
      'Application Support',
      editor.dataFolder,
    ),
    'linux' => path.join(home, '.config', editor.dataFolder),
    'windows' =>
      appData == null ? null : path.join(appData!, editor.dataFolder),
    _ => null,
  };

  String extensionsRoot(EditorProduct editor) =>
      path.join(home, editor.homeFolder, 'extensions');
}

/// What a folder in the editor's data folder holds.
enum EditorDataKind {
  /// Web, script and GPU caches; rebuilt on the next launch.
  cache,

  /// Downloaded VSIX installers.
  extensionDownloads,

  /// Session logs.
  logs,

  /// Crashpad minidumps and their bookkeeping.
  crashReports,

  /// Web storage of extension views, service workers, cookies and similar.
  webStorage,

  /// Local History: earlier versions of the user's own files.
  localHistory,

  /// Settings, keybindings, snippets, profiles and editor state.
  settings,

  /// Everything else in the data folder.
  other,
}

/// One kind of data folder, with what of it can be cleaned.
class EditorDataUsage {
  final EditorDataKind kind;

  /// The folders and files of this kind, for opening them.
  final List<String> paths;
  final int bytes;

  /// What can go to the Trash. Empty for review-only kinds.
  final List<EditorCleanTarget> cleanable;

  const EditorDataUsage({
    required this.kind,
    required this.paths,
    required this.bytes,
    this.cleanable = const [],
  });

  int get cleanableBytes =>
      cleanable.fold<int>(0, (sum, target) => sum + target.bytes);
}

/// A file or folder the page can move to the Trash as a whole.
class EditorCleanTarget {
  final String path;
  final int bytes;

  const EditorCleanTarget(this.path, this.bytes);
}

enum EditorExtensionStatus {
  /// Listed by the editor (default profile or another profile).
  installed,

  /// Not listed by any profile and marked in `.obsolete`: an uninstalled or
  /// replaced version the editor deletes on its next start.
  obsolete,

  /// Not listed by any profile and not marked obsolete. Left alone: it may
  /// be an install in progress.
  unregistered,
}

/// An extension folder and the storage it uses.
class EditorExtensionUsage {
  /// `publisher.name`, lower case.
  final String id;
  final String version;
  final String displayName;
  final String path;

  /// The PNG named by the manifest's `icon`, when it exists.
  final String? iconPath;
  final EditorExtensionStatus status;
  final int installBytes;

  /// `User/globalStorage/<id>` in every profile.
  final int globalStorageBytes;

  /// `User/workspaceStorage/*/<id>`.
  final int workspaceStorageBytes;

  const EditorExtensionUsage({
    required this.id,
    required this.version,
    required this.displayName,
    required this.path,
    this.iconPath,
    required this.status,
    required this.installBytes,
    this.globalStorageBytes = 0,
    this.workspaceStorageBytes = 0,
  });

  int get totalBytes =>
      installBytes + globalStorageBytes + workspaceStorageBytes;

  bool get isCleanable => status == EditorExtensionStatus.obsolete;
}

/// Storage kept for an extension id with no extension folder: a built-in
/// extension or an uninstalled one. Never offered for cleanup.
class EditorExtensionData {
  final String id;
  final List<String> paths;
  final int bytes;

  const EditorExtensionData({
    required this.id,
    required this.paths,
    required this.bytes,
  });
}

enum EditorWorkspaceStatus {
  /// The folder or `.code-workspace` file still exists.
  present,

  /// A local folder or workspace file that no longer exists.
  missing,

  /// On a drive or volume that is not connected now.
  offline,

  /// A remote, virtual or untitled workspace, or one that cannot be read.
  unknown,
}

/// One `User/workspaceStorage/<hash>` folder.
class EditorWorkspaceUsage {
  final String path;

  /// The workspace as the editor names it: a local path when there is one,
  /// otherwise the URI.
  final String target;
  final EditorWorkspaceStatus status;

  /// The whole folder, including extension storage inside it.
  final int bytes;

  const EditorWorkspaceUsage({
    required this.path,
    required this.target,
    required this.status,
    required this.bytes,
  });

  bool get isCleanable => status == EditorWorkspaceStatus.missing;
}

/// Everything found for one editor.
class EditorStorageReport {
  final EditorProduct editor;
  final String? dataRoot;
  final String? extensionsRoot;

  /// The editor's main process holds its data folder right now; caches and
  /// the current logs are then left alone.
  final bool isRunning;

  /// Sorted largest first.
  final List<EditorExtensionUsage> extensions;
  final List<EditorExtensionData> orphanedExtensionData;
  final List<EditorWorkspaceUsage> workspaces;

  /// One entry per [EditorDataKind] present, largest first.
  final List<EditorDataUsage> data;

  /// Folders some sizes could not be read from.
  final int unreadable;

  const EditorStorageReport({
    required this.editor,
    required this.dataRoot,
    required this.extensionsRoot,
    required this.isRunning,
    required this.extensions,
    required this.orphanedExtensionData,
    required this.workspaces,
    required this.data,
    this.unreadable = 0,
  });

  int get extensionInstallBytes =>
      extensions.fold<int>(0, (sum, e) => sum + e.installBytes);

  int get extensionStorageBytes =>
      extensions.fold<int>(
        0,
        (sum, e) => sum + e.globalStorageBytes + e.workspaceStorageBytes,
      ) +
      orphanedExtensionData.fold<int>(0, (sum, e) => sum + e.bytes);

  int get workspaceBytes => workspaces.fold<int>(0, (sum, w) => sum + w.bytes);

  int get dataBytes => data.fold<int>(0, (sum, d) => sum + d.bytes);

  /// Every byte found. Extension storage inside a workspace folder is part
  /// of [workspaceBytes] and is not added again.
  int get totalBytes =>
      extensionInstallBytes +
      extensions.fold<int>(0, (sum, e) => sum + e.globalStorageBytes) +
      orphanedExtensionData.fold<int>(0, (sum, e) => sum + e.bytes) +
      workspaceBytes +
      dataBytes;

  /// Safe by default: obsolete extensions and the data kinds with
  /// [EditorDataUsage.cleanable] targets.
  int get safeBytes =>
      extensions
          .where((e) => e.isCleanable)
          .fold<int>(0, (sum, e) => sum + e.installBytes) +
      data.fold<int>(0, (sum, d) => sum + d.cleanableBytes);

  bool get isEmpty =>
      extensions.isEmpty &&
      orphanedExtensionData.isEmpty &&
      workspaces.isEmpty &&
      data.isEmpty;

  /// This report after [removed] (exact paths of cleaned targets) went to
  /// the Trash.
  EditorStorageReport withoutPaths(Set<String> removed) {
    if (removed.isEmpty) return this;
    return EditorStorageReport(
      editor: editor,
      dataRoot: dataRoot,
      extensionsRoot: extensionsRoot,
      isRunning: isRunning,
      extensions: [
        for (final e in extensions)
          if (!removed.contains(e.path)) e,
      ],
      orphanedExtensionData: orphanedExtensionData,
      workspaces: [
        for (final w in workspaces)
          if (!removed.contains(w.path)) w,
      ],
      data: [
        for (final d in data)
          if (d.cleanable.any((t) => removed.contains(t.path)))
            EditorDataUsage(
              kind: d.kind,
              paths: [
                for (final path in d.paths)
                  if (!removed.contains(path)) path,
              ],
              bytes:
                  d.bytes -
                  d.cleanable
                      .where((t) => removed.contains(t.path))
                      .fold<int>(0, (sum, t) => sum + t.bytes),
              cleanable: [
                for (final t in d.cleanable)
                  if (!removed.contains(t.path)) t,
              ],
            )
          else
            d,
      ],
      unreadable: unreadable,
    );
  }
}

enum EditorCleanGroupKind {
  obsoleteExtensions,
  cache,
  extensionDownloads,
  logs,
  crashReports,
  missingWorkspaces;

  /// Checked when results arrive. Workspace data of deleted folders can hold
  /// chat history, so the user opts in.
  bool get selectedByDefault => this != missingWorkspaces;
}

/// Targets of one kind in one editor, checked or unchecked together.
class EditorCleanGroup {
  final String id;
  final EditorProduct editor;
  final EditorCleanGroupKind kind;
  final List<EditorCleanTarget> targets;

  const EditorCleanGroup({
    required this.id,
    required this.editor,
    required this.kind,
    required this.targets,
  });

  int get bytes => targets.fold<int>(0, (sum, t) => sum + t.bytes);

  static List<EditorCleanGroup> of(EditorStorageReport report) {
    EditorCleanGroup group(
      EditorCleanGroupKind kind,
      Iterable<EditorCleanTarget> targets,
    ) => EditorCleanGroup(
      id: '${report.editor.dataFolder}/${kind.name}',
      editor: report.editor,
      kind: kind,
      targets: List.unmodifiable(targets),
    );

    List<EditorCleanTarget> data(EditorDataKind kind) => [
      for (final d in report.data)
        if (d.kind == kind) ...d.cleanable,
    ];

    return [
      for (final g in [
        group(EditorCleanGroupKind.obsoleteExtensions, [
          for (final e in report.extensions)
            if (e.isCleanable) EditorCleanTarget(e.path, e.installBytes),
        ]),
        group(EditorCleanGroupKind.cache, data(EditorDataKind.cache)),
        group(
          EditorCleanGroupKind.extensionDownloads,
          data(EditorDataKind.extensionDownloads),
        ),
        group(EditorCleanGroupKind.logs, data(EditorDataKind.logs)),
        group(
          EditorCleanGroupKind.crashReports,
          data(EditorDataKind.crashReports),
        ),
        group(EditorCleanGroupKind.missingWorkspaces, [
          for (final w in report.workspaces)
            if (w.isCleanable) EditorCleanTarget(w.path, w.bytes),
        ]),
      ])
        if (g.targets.isNotEmpty) g,
    ];
  }
}

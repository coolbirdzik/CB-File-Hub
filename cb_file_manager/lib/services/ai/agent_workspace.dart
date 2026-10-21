import 'dart:io';

/// What a tab's current path means to CB Agent.
enum AgentWorkspaceKind {
  /// A local folder: the agent works in it.
  folder,

  /// The drives view: every drive is visible; relative paths use home.
  drives,

  /// The Disk Cleaner: the agent reads its scan; relative paths use home.
  cleaner,

  /// Another app screen (gallery, tags, settings...): not a folder, so the
  /// agent works in home.
  screen,

  /// A network location (SMB, FTP...) the file tools cannot read, so the
  /// agent works in home.
  network,
}

/// Where CB Agent works for the tab's current path. The system prompt, the
/// tools and the chat's context strip all resolve it here, so what the user
/// is told is exactly what the agent uses.
class AgentWorkspace {
  final AgentWorkspaceKind kind;

  /// The tab's path as the app knows it (may be a `#screen` or a URL).
  final String browsingPath;

  /// The folder relative paths and default searches resolve against.
  final String workingDirectory;

  const AgentWorkspace._(this.kind, this.browsingPath, this.workingDirectory);

  static String get homeDirectory =>
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';

  factory AgentWorkspace.resolve(String currentPath, {String? home}) {
    final fallback = home ?? homeDirectory;
    AgentWorkspace at(AgentWorkspaceKind kind) =>
        AgentWorkspace._(kind, currentPath, fallback);
    if (currentPath.contains('://')) return at(AgentWorkspaceKind.network);
    if (currentPath.isEmpty || currentPath == '#drives') {
      return at(AgentWorkspaceKind.drives);
    }
    if (currentPath.startsWith('#cb-agent-cleaner')) {
      return at(AgentWorkspaceKind.cleaner);
    }
    if (currentPath.startsWith('#')) return at(AgentWorkspaceKind.screen);
    return AgentWorkspace._(
      AgentWorkspaceKind.folder,
      currentPath,
      currentPath,
    );
  }
}

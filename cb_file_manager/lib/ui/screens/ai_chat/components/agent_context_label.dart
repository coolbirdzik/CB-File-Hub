import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../services/ai/agent_workspace.dart';

/// Tells the user where CB Agent is working: the folder it searches, or the
/// screen it is on and the folder it falls back to. Reads the same
/// [AgentWorkspace] the system prompt and the tools use, and the tooltip
/// spells out what that means for the next message.
class AgentContextLabel extends StatelessWidget {
  final String currentPath;
  final double fontSize;

  /// Overrides the home folder, for tests.
  final String? home;

  const AgentContextLabel({
    super.key,
    required this.currentPath,
    this.fontSize = 11,
    this.home,
  });

  static String _name(String path) {
    final name = p.basename(path);
    return name.isEmpty ? path : name;
  }

  /// The localized title of an app screen path.
  static String screenName(AppLocalizations l, String path) {
    if (path.startsWith('#search?tag=') || path == '#tags') return l.tags;
    if (path.startsWith('#album')) return l.albums;
    if (path.startsWith('#video')) return l.videoHubTitle;
    if (path.startsWith('#torrents')) return l.torrents;
    return switch (path) {
      '#home' => l.home,
      '#gallery' => l.imageGallery,
      '#settings' => l.settings,
      _ => l.aiContextAppScreen,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final workspace = AgentWorkspace.resolve(currentPath, home: home);
    final working = workspace.workingDirectory;
    final fallback = l.aiContextDefaultFolder(_name(working));

    final (
      IconData icon,
      String title,
      String detail,
      String hint,
    ) = switch (workspace.kind) {
      AgentWorkspaceKind.folder => (
        PhosphorIconsLight.folderOpen,
        '${l.aiContextWorkingIn} ${_name(working)}',
        working,
        l.aiContextFolderHint(working),
      ),
      AgentWorkspaceKind.drives => (
        PhosphorIconsLight.hardDrives,
        l.aiAllDrives,
        fallback,
        l.aiContextDrivesHint(working),
      ),
      AgentWorkspaceKind.cleaner => (
        PhosphorIconsLight.broom,
        l.aiContextCleanerScan,
        fallback,
        l.aiContextCleanerHint(working),
      ),
      AgentWorkspaceKind.screen => (
        PhosphorIconsLight.appWindow,
        screenName(l, currentPath),
        fallback,
        l.aiContextScreenHint(working),
      ),
      AgentWorkspaceKind.network => (
        PhosphorIconsLight.globe,
        l.aiContextNetwork,
        fallback,
        l.aiContextNetworkHint(working),
      ),
    };

    final accent = theme.colorScheme.primary.withValues(alpha: 0.85);
    final muted = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    return Tooltip(
      key: const ValueKey('ai-context-label'),
      message: hint,
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        children: [
          Icon(icon, size: fontSize + 1, color: accent),
          const SizedBox(width: 5),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    TextSpan(
                      text: '  ·  $detail',
                      style: TextStyle(color: muted),
                    ),
                ],
              ),
              style: TextStyle(fontSize: fontSize),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            PhosphorIconsLight.info,
            size: fontSize,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }
}

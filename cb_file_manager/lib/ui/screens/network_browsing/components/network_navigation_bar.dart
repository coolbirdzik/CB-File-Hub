import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../components/common/breadcrumb_address_bar.dart';
import '../../../tab_manager/components/navigation_bar.dart';
import '../../../tab_manager/core/tab_manager.dart';
import '../../ssh/ssh_section.dart';

String networkAddress(String path) {
  if (!path.startsWith('#network/')) return path;
  final parts = path.split('/');
  if (parts.length < 3) return path;
  try {
    if (parts[1] == 'SFTP') {
      return Uri.parse(
        'sftp://${Uri.decodeComponent(parts[2])}',
      ).replace(pathSegments: ['', ...parts.skip(3)]).toString();
    }
    return '${parts[1].toLowerCase()}://${Uri.decodeComponent(parts[2])}/${parts.skip(3).join('/')}';
  } on FormatException {
    return path;
  }
}

String networkPathFromAddress(String address) {
  final path = address.trim();
  final uri = Uri.tryParse(path);
  if (uri == null ||
      !const ['smb', 'ftp', 'webdav', 'sftp', 'ftps'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return path;
  }
  final type = uri.scheme == 'ftps' ? 'FTP' : uri.scheme.toUpperCase();
  final authority = ['sftp', 'ftp', 'ftps'].contains(uri.scheme)
      ? uri.authority
      : uri.host;
  final suffix = '/${uri.pathSegments.join('/')}';
  return '#network/$type/${Uri.encodeComponent(authority)}$suffix';
}

String? networkParentPath(String path) {
  if (path == '#network') return '#home';
  if (const ['#smb', '#ftp', '#webdav', '#sftp', '#ssh'].contains(path)) {
    return '#network';
  }
  if (path.startsWith('#ssh/')) return '#ssh';
  if (!path.startsWith('#network/')) return null;
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length <= 3) {
    return parts.length >= 2 ? '#${parts[1].toLowerCase()}' : '#network';
  }
  return '${parts.take(parts.length - 1).join('/')}/';
}

/// Navigation updates the owning tab, even when another tab has focus.
void navigateNetworkTab(BuildContext context, String tabId, String path) {
  final tabs = context.read<TabManagerBloc>();
  if (!tabs.state.tabs.any((tab) => tab.id == tabId)) return;
  final l10n = AppLocalizations.of(context)!;
  final section = SshSection.fromPath(path);
  final name = switch (path) {
    _ when section != null && section != SshSection.hosts => section.label(
      l10n,
    ),
    '#home' => l10n.homeTab,
    '#network' => l10n.networkTab,
    '#smb' => l10n.smbNetwork,
    '#ssh' => l10n.sshWorkspace,
    '#sftp' => 'SFTP',
    '#ftp' => l10n.ftpConnections,
    '#webdav' => l10n.webdavConnections,
    _ =>
      path.split('/').lastWhere((part) => part.isNotEmpty, orElse: () => path),
  };
  tabs.add(UpdateTabPath(tabId, path));
  tabs.add(UpdateTabName(tabId, name));
}

/// The file browser's navigation control, with virtual network breadcrumbs.
class NetworkNavigationBar extends StatefulWidget {
  final String tabId;
  final String path;

  /// The workspace shown when the user presses Home. Network browsing defaults
  /// to the app home; SSH-owned views return to the SSH workspace instead.
  final String homePath;
  final ValueChanged<String>? onNavigate;
  final bool allowPathEditing;

  const NetworkNavigationBar({
    super.key,
    required this.tabId,
    required this.path,
    this.homePath = '#home',
    this.onNavigate,
    this.allowPathEditing = false,
  });

  @override
  State<NetworkNavigationBar> createState() => _NetworkNavigationBarState();
}

class _NetworkNavigationBarState extends State<NetworkNavigationBar> {
  late final TextEditingController _controller = TextEditingController(
    text: networkAddress(widget.path),
  );

  @override
  void didUpdateWidget(NetworkNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) {
      _controller.text = networkAddress(widget.path);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigate(String path) {
    if (widget.onNavigate != null) {
      widget.onNavigate!(path);
    } else {
      navigateNetworkTab(context, widget.tabId, path);
    }
  }

  List<BreadcrumbSegment> _breadcrumbs(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final paths = <String>['#network'];
    final labels = <String>[l10n.networkTab];
    final section = SshSection.fromPath(widget.path);
    if (section != null && section != SshSection.hosts) {
      paths.addAll(['#ssh', section.path]);
      labels.addAll(['SSH', section.label(l10n)]);
    } else if (widget.path != '#network') {
      final parts = widget.path
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      final protocol = widget.path.startsWith('#network/')
          ? parts.elementAtOrNull(1) ?? ''
          : widget.path.substring(1);
      paths.add('#${protocol.toLowerCase()}');
      labels.add(
        protocol.toLowerCase() == 'webdav' ? 'WebDAV' : protocol.toUpperCase(),
      );
      if (widget.path.startsWith('#network/')) {
        for (var i = 2; i < parts.length; i++) {
          paths.add('${parts.take(i + 1).join('/')}/');
          try {
            labels.add(
              protocol.toUpperCase() == 'SFTP' && i > 2
                  ? parts[i]
                  : Uri.decodeComponent(parts[i]),
            );
          } on FormatException {
            labels.add(parts[i]);
          }
        }
      }
    }
    return [
      for (var i = 0; i < paths.length; i++)
        BreadcrumbSegment(
          label: labels[i],
          icon: i == 0 ? PhosphorIconsLight.globe : null,
          onTap: i == paths.length - 1 ? null : () => _navigate(paths[i]),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabManagerBloc, TabManagerState>(
      builder: (context, state) {
        final parent = networkParentPath(widget.path);
        return PathNavigationBar(
          tabId: widget.tabId,
          pathController: _controller,
          currentPath: widget.path,
          tabPath: widget.path,
          isNetworkPath: true,
          breadcrumbSegments: _breadcrumbs(context),
          enablePathEditing: widget.allowPathEditing,
          onPathSubmitted: (value) => _navigate(networkPathFromAddress(value)),
          canNavigateToParent: parent != null,
          onNavigateToParent: parent == null ? null : () => _navigate(parent),
          onNavigateHome: () => _navigate(widget.homePath),
        );
      },
    );
  }
}

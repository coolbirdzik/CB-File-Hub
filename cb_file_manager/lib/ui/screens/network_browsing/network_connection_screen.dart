import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../../bloc/network_browsing/network_browsing_event.dart';
import '../../../bloc/network_browsing/network_browsing_state.dart';
import '../../../services/network_browsing/network_service_base.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../utils/route.dart';
import '../../../design_system/primitives/cb_button.dart';
import '../system_screen.dart';
// Import TabData
// Import TabMainScreen
import 'network_connection_dialog.dart';

// Import SMBBrowserScreen

/// Screen to display and manage network connections
class NetworkConnectionScreen extends StatefulWidget {
  final String? tabId;

  const NetworkConnectionScreen({super.key, this.tabId});

  @override
  State<NetworkConnectionScreen> createState() =>
      _NetworkConnectionScreenState();
}

class _NetworkConnectionScreenState extends State<NetworkConnectionScreen> {
  @override
  void initState() {
    super.initState();
    // Request list of available services when screen initializes
    context.read<NetworkBrowsingBloc>().add(
      const NetworkServicesListRequested(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SystemScreen(
      tabId: widget.tabId ?? context.read<TabManagerBloc>().state.activeTabId,
      title: l10n.networkConnections,
      systemId: '#network',
      icon: PhosphorIconsLight.globe,
      showAppBar: true,
      onRefresh: () => context.read<NetworkBrowsingBloc>().add(
        const NetworkServicesListRequested(),
      ),
      actions: [
        CbButton.icon(
          icon: PhosphorIconsLight.arrowClockwise,
          tooltip: l10n.refresh,
          onPressed: () => context.read<NetworkBrowsingBloc>().add(
            const NetworkServicesListRequested(),
          ),
        ),
        CbButton.icon(
          icon: PhosphorIconsLight.plus,
          tooltip: l10n.addConnection,
          onPressed: () => _showConnectionDialog(context),
        ),
      ],
      child: ClipRect(
        child: BlocBuilder<NetworkBrowsingBloc, NetworkBrowsingState>(
          builder: (context, state) {
            return RefreshIndicator(
              onRefresh: () async {
                context.read<NetworkBrowsingBloc>().add(
                  const NetworkServicesListRequested(),
                );
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // An operation error must never replace connection controls.
                  if (state.hasError)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            PhosphorIconsLight.warningCircle,
                            color: theme.colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(state.errorMessage!)),
                        ],
                      ),
                    ),
                  // Active Connections Section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 8.0),
                    child: Text(
                      l10n.activeConnectionsTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  _buildActiveConnections(state.connections),

                  const Divider(height: 32),

                  // Available Services Section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
                    child: Text(
                      l10n.availableServices,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  _buildAvailableServices(state.services ?? []),
                  ListTile(
                    leading: const Icon(PhosphorIconsLight.terminalWindow),
                    title: Text(l10n.sshWorkspace),
                    subtitle: Text(
                      '${l10n.sshHosts} · ${l10n.sshKeys} · Terminal',
                    ),
                    onTap: () =>
                        _openBrowserInTab(context, '#ssh', l10n.sshWorkspace),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActiveConnections(Map<String, NetworkServiceBase> connections) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (connections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsLight.wifiSlash,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noActiveNetworkConnections,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.useAddButtonToAddConnection,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: connections.length,
      itemBuilder: (context, index) {
        final entry = connections.entries.elementAt(index);
        final service = entry.value;
        final uri = Uri.parse(service.basePath);
        final authority =
            service.serviceName == 'FTP' || service.serviceName == 'SFTP'
            ? uri.authority
            : uri.host;
        final path = entry.key.startsWith('#network/')
            ? entry.key
            : '#network/${service.serviceName.toUpperCase()}/${Uri.encodeComponent(authority)}/';

        String displayName = l10n.unknownConnection;
        String subtitle = service.basePath.startsWith('ftps://')
            ? 'FTPS'
            : service.serviceName;

        if (path.startsWith('#network/')) {
          final parts = path.substring('#network/'.length).split('/');
          if (parts.length >= 2) {
            final serviceName = parts[0];
            final host = Uri.decodeComponent(parts[1]);
            displayName = host;
            subtitle = l10n.serviceTypeConnection(
              service.basePath.startsWith('ftps://') ? 'FTPS' : serviceName,
            );
          }
        }

        return ListTile(
          leading: Icon(service.serviceIcon, color: theme.colorScheme.primary),
          title: Text(displayName, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle),
          trailing: IconButton(
            icon: Icon(
              PhosphorIconsLight.xCircle,
              color: theme.colorScheme.error,
            ),
            onPressed: () => _disconnectService(path),
            tooltip: l10n.disconnect,
          ),
          onTap: () => _openConnection(path),
        );
      },
    );
  }

  Widget _buildAvailableServices(List<NetworkServiceBase> services) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (services.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(child: Text(l10n.noServicesAvailable)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];

        return ListTile(
          leading: Icon(service.serviceIcon, color: theme.colorScheme.primary),
          title: Text(service.serviceName),
          subtitle: Text(service.serviceDescription),
          onTap: () {
            if (service.serviceName == 'SMB') {
              _openBrowserInTab(context, '#smb', l10n.smbNetwork);
            } else if (service.serviceName == 'SFTP') {
              _openBrowserInTab(context, '#sftp', 'SFTP');
            } else if (service.serviceName == 'FTP') {
              _openBrowserInTab(context, '#ftp', l10n.ftpConnections);
            } else if (service.serviceName == 'WebDAV') {
              _openBrowserInTab(context, '#webdav', l10n.webdavConnections);
            } else {
              _showConnectionDialog(
                context,
                initialService: service.serviceName,
              );
            }
          },
        );
      },
    );
  }

  void _showConnectionDialog(BuildContext context, {String? initialService}) {
    final networkBloc = context.read<NetworkBrowsingBloc>();
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: networkBloc,
        child: NetworkConnectionDialog(
          initialService: initialService,
          onConnectionRequested: (path, name) =>
              _navigateInCurrentTab(path, tabName: name),
        ),
      ),
    );
  }

  void _disconnectService(String path) {
    context.read<NetworkBrowsingBloc>().add(NetworkDisconnectRequested(path));
  }

  void _openConnection(String path) {
    debugPrint("NetworkConnectionScreen: Opening connection to path: $path");

    if (path.startsWith('#network/')) {
      final l10n = AppLocalizations.of(context)!;

      String tabName = l10n.networkTab;
      try {
        final parts = path.substring('#network/'.length).split('/');
        if (parts.length >= 2) {
          final serviceName = parts[0];
          final host = Uri.decodeComponent(parts[1]);
          tabName = '$host ($serviceName)';
        }
      } catch (_) {}

      debugPrint(
        "NetworkConnectionScreen: Navigating in current tab to path: $path and name: $tabName",
      );
      _navigateInCurrentTab(path, tabName: tabName);
    }
    // Do not pop the navigator here, as it causes the crash.
  }

  void _openBrowserInTab(BuildContext context, String path, String tabName) {
    _navigateInCurrentTab(path, tabName: tabName);
  }

  void _navigateInCurrentTab(String path, {String? tabName}) {
    try {
      final tabBloc = BlocProvider.of<TabManagerBloc>(context, listen: false);
      final activeTab = tabBloc.state.activeTab;
      if (activeTab == null) {
        // Fallback: keep old behavior if we're not inside the tab system.
        tabBloc.add(AddTab(path: path, name: tabName, switchToTab: true));
        return;
      }

      final targetTabId = widget.tabId ?? activeTab.id;
      tabBloc.add(UpdateTabPath(targetTabId, path));
      if (tabName != null && tabName.trim().isNotEmpty) {
        tabBloc.add(UpdateTabName(targetTabId, tabName));
      }
    } catch (e) {
      debugPrint('Error navigating in current tab: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.errorWithMessage(e.toString()),
            ),
          ),
        );
      }
    }
  }
}

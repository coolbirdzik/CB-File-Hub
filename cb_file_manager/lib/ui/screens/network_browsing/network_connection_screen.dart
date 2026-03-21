import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../../bloc/network_browsing/network_browsing_event.dart';
import '../../../bloc/network_browsing/network_browsing_state.dart';
import '../../../services/network_browsing/network_service_base.dart';
import '../../tab_manager/core/tab_manager.dart';
// Import TabData
// Import TabMainScreen
import 'network_connection_dialog.dart';
// Import SMBBrowserScreen

/// Screen to display and manage network connections
class NetworkConnectionScreen extends StatefulWidget {
  const NetworkConnectionScreen({Key? key}) : super(key: key);

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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.networkConnections)),
      body: BlocBuilder<NetworkBrowsingBloc, NetworkBrowsingState>(
        builder: (context, state) {
          if (state.isLoading && state.connections.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIconsLight.warning,
                      size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(l10n.errorWithMessage(
                      state.errorMessage ?? l10n.unknownError)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context
                        .read<NetworkBrowsingBloc>()
                        .add(const NetworkServicesListRequested()),
                    child: Text(l10n.tryAgain),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              context
                  .read<NetworkBrowsingBloc>()
                  .add(const NetworkServicesListRequested());
            },
            child: ListView(
              children: [
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
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // Disable hero animation to avoid conflicts
        onPressed: () => _showConnectionDialog(context),
        tooltip: l10n.addConnection,
        child: const Icon(PhosphorIconsLight.plus),
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
              Icon(PhosphorIconsLight.wifiSlash,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                l10n.noActiveNetworkConnections,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.useAddButtonToAddConnection,
                style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
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
        final path = entry.key;
        final service = entry.value;

        String displayName = l10n.unknownConnection;
        String subtitle = service.serviceName;

        if (path.startsWith('#network/')) {
          final parts = path.substring('#network/'.length).split('/');
          if (parts.length >= 2) {
            final serviceName = parts[0];
            final host = Uri.decodeComponent(parts[1]);
            displayName = host;
            subtitle = l10n.serviceTypeConnection(serviceName);
          }
        }

        return ListTile(
          leading: Icon(
            service.serviceIcon,
            color: theme.colorScheme.primary,
          ),
          title: Text(displayName, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle),
          trailing: IconButton(
            icon: Icon(PhosphorIconsLight.xCircle,
                color: theme.colorScheme.error),
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
          leading: Icon(
            service.serviceIcon,
            color: theme.colorScheme.primary,
          ),
          title: Text(service.serviceName),
          subtitle: Text(service.serviceDescription),
          onTap: () {
            if (service.serviceName == 'SMB') {
              _openBrowserInTab(context, '#smb', l10n.smbNetwork);
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
    showDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: networkBloc,
        child: NetworkConnectionDialog(initialService: initialService),
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
          "NetworkConnectionScreen: Navigating in current tab to path: $path and name: $tabName");
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

      tabBloc.add(UpdateTabPath(activeTab.id, path));
      if (tabName != null && tabName.trim().isNotEmpty) {
        tabBloc.add(UpdateTabName(activeTab.id, tabName));
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

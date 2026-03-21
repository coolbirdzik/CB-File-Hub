import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/translation_helper.dart';

import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../../bloc/network_browsing/network_browsing_event.dart';
import '../../../bloc/network_browsing/network_browsing_state.dart';
import '../../../services/network_browsing/network_service_base.dart';
import '../../../services/network_credentials_service.dart';
import '../../../models/database/network_credentials.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../system_screen.dart';
import 'network_connection_dialog.dart';

/// Screen to browse FTP servers
class FTPBrowserScreen extends StatefulWidget {
  /// The tab ID this screen belongs to
  final String tabId;

  const FTPBrowserScreen({
    Key? key,
    required this.tabId,
  }) : super(key: key);

  @override
  State<FTPBrowserScreen> createState() => _FTPBrowserScreenState();
}

class _FTPBrowserScreenState extends State<FTPBrowserScreen>
    with WidgetsBindingObserver {
  final NetworkCredentialsService _credentialsService =
      NetworkCredentialsService();

  late NetworkBrowsingBloc _networkBloc;

  List<NetworkCredentials> _savedCredentials = [];
  final Set<int> _connectingCredentialIds = {};
  final Map<String, int> _pendingTabCredentialMap = {};

  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _networkBloc = BlocProvider.of<NetworkBrowsingBloc>(context, listen: false);

    _setupBlocListener();
    _refreshData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshData();
  }

  void _setupBlocListener() {
    _networkBloc.stream.listen((state) {
      if (!mounted) return;

      if (state.lastSuccessfullyConnectedPath != null) {
        _handleSuccessfulConnection(state.lastSuccessfullyConnectedPath!);
      }

      bool hadError = false;
      if (state.errorMessage != null && _connectingCredentialIds.isNotEmpty) {
        hadError = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${context.tr.connectionError}: ${state.errorMessage}')),
        );
      }

      setState(() {
        if (hadError || state.lastSuccessfullyConnectedPath != null) {
          _connectingCredentialIds.clear();
        }
      });
    });
  }

  void _handleSuccessfulConnection(String connectionPath) {
    if (!connectionPath.startsWith('#network/FTP/')) return;

    final host = Uri.decodeComponent(connectionPath.split('/')[2]);

    final credentialId = _pendingTabCredentialMap[host];
    if (credentialId != null) {
      _openTabForConnection(connectionPath, host);
      _pendingTabCredentialMap.remove(host);
    }
  }

  void _refreshData() {
    if (mounted) {
      setState(() {
        _loadSavedCredentials();
      });
      _networkBloc.add(const NetworkServicesListRequested());
    }
  }

  void _loadSavedCredentials() {
    try {
      _savedCredentials =
          _credentialsService.getCredentialsByServiceType('FTP');
    } catch (e) {
      debugPrint('${context.tr.loadCredentialsError}: $e');
    }
  }

  void _connectToFTPServer() {
    showDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: _networkBloc,
        child: const NetworkConnectionDialog(initialService: 'FTP'),
      ),
    ).then((_) => _refreshData());
  }

  void _connectWithSavedCredentials(NetworkCredentials credentials) {
    setState(() {
      _connectingCredentialIds.add(credentials.id);
      _pendingTabCredentialMap[credentials.host] = credentials.id;
    });

    _networkBloc.add(NetworkConnectionRequested(
      serviceName: 'FTP',
      host: credentials.host,
      username: credentials.username,
      password: credentials.password,
      port: credentials.port,
    ));
  }

  void _openTabForConnection(String path, String name) {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context, listen: false);
    tabBloc.add(UpdateTabPath(widget.tabId, path));
    tabBloc.add(UpdateTabName(widget.tabId, '$name (FTP)'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SystemScreen(
      title: context.tr.ftpConnections,
      systemId: '#ftp',
      icon: PhosphorIconsLight.cloudArrowUp,
      showAppBar: true,
      actions: [
        IconButton(
          icon: const Icon(PhosphorIconsLight.arrowsClockwise),
          onPressed: _refreshData,
          tooltip: context.tr.refreshData,
        ),
        IconButton(
          icon: const Icon(PhosphorIconsLight.plus),
          onPressed: _connectToFTPServer,
          tooltip: context.tr.addConnection,
        ),
      ],
      child: BlocBuilder<NetworkBrowsingBloc, NetworkBrowsingState>(
        bloc: _networkBloc,
        builder: (context, state) {
          final activeConnections = state.connections.entries
              .where((entry) => (entry.value).serviceName == 'FTP')
              .toList();

          if (activeConnections.isEmpty && _savedCredentials.isEmpty) {
            return Center(child: Text(context.tr.noFtpConnections));
          }

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              if (activeConnections.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 8.0),
                  child: Text(context.tr.activeConnections,
                      style: theme.textTheme.titleSmall),
                ),
                ...activeConnections.map(_buildActiveConnectionItem),
                const Divider(),
              ],
              if (_savedCredentials.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 8.0),
                  child: Text(context.tr.savedConnections,
                      style: theme.textTheme.titleSmall),
                ),
                ..._savedCredentials.map(_buildSavedConnectionItem),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveConnectionItem(
      MapEntry<String, NetworkServiceBase> entry) {
    final theme = Theme.of(context);
    String host = context.tr.unknown;
    try {
      host = Uri.parse(entry.value.basePath).host;
    } catch (_) {}

    return ListTile(
      leading:
          Icon(PhosphorIconsLight.desktop, color: theme.colorScheme.tertiary),
      title: Text(host),
      subtitle: Text(context.tr.connecting),
      onTap: () => _openTabForConnection(entry.key, host),
    );
  }

  Widget _buildSavedConnectionItem(NetworkCredentials credentials) {
    final isConnecting = _connectingCredentialIds.contains(credentials.id);
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(PhosphorIconsLight.cloudArrowUp,
          color: theme.colorScheme.primary),
      title: Text(credentials.host),
      subtitle: Text(credentials.username),
      trailing: IconButton(
        icon: isConnecting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.0))
            : Icon(PhosphorIconsLight.arrowCircleRight,
                color: theme.colorScheme.tertiary),
        onPressed: isConnecting
            ? null
            : () => _connectWithSavedCredentials(credentials),
        tooltip: context.tr.connect,
      ),
      onTap:
          isConnecting ? null : () => _connectWithSavedCredentials(credentials),
    );
  }
}

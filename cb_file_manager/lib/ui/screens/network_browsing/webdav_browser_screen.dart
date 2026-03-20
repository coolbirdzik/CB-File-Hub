import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../../bloc/network_browsing/network_browsing_event.dart';
import '../../../bloc/network_browsing/network_browsing_state.dart';
import '../../../services/network_browsing/network_service_base.dart';
import '../../../services/network_credentials_service.dart';
import '../../../models/database/network_credentials.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../system_screen.dart';
import 'network_connection_dialog.dart';

/// Screen for browsing WebDAV directories
class WebDAVBrowserScreen extends StatefulWidget {
  final String tabId;

  const WebDAVBrowserScreen({
    Key? key,
    required this.tabId,
  }) : super(key: key);

  @override
  State<WebDAVBrowserScreen> createState() => _WebDAVBrowserScreenState();
}

class _WebDAVBrowserScreenState extends State<WebDAVBrowserScreen>
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
  final TextEditingController _basePathController = TextEditingController();

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
    _basePathController.dispose();
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
              content: Text(
                  '${AppLocalizations.of(context)!.connectionError}: ${state.errorMessage}')),
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
    if (!connectionPath.startsWith('#network/WebDAV/')) return;

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
          _credentialsService.getCredentialsByServiceType('WebDAV');
    } catch (e) {
      debugPrint('Lỗi khi tải thông tin đăng nhập đã lưu: $e');
    }
  }

  void _connectToWebDAVServer() {
    showDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: _networkBloc,
        child: const NetworkConnectionDialog(initialService: 'WebDAV'),
      ),
    ).then((_) => _refreshData());
  }

  void _connectWithSavedCredentials(NetworkCredentials credentials) {
    setState(() {
      _connectingCredentialIds.add(credentials.id);
      _pendingTabCredentialMap[credentials.host] = credentials.id;
    });

    // Parse additional options
    Map<String, dynamic> additionalOptions = {};
    if (credentials.additionalOptions != null) {
      try {
        additionalOptions = Map<String, dynamic>.from(
          jsonDecode(credentials.additionalOptions!),
        );
      } catch (e) {
        debugPrint('Error parsing additional options: $e');
      }
    }

    _networkBloc.add(NetworkConnectionRequested(
      serviceName: 'WebDAV',
      host: credentials.host,
      username: credentials.username,
      password: credentials.password,
      port: credentials.port,
      additionalOptions: additionalOptions,
    ));
  }

  void _openTabForConnection(String path, String name) {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context, listen: false);
    tabBloc.add(UpdateTabPath(widget.tabId, path));
    tabBloc.add(UpdateTabName(widget.tabId, '$name (WebDAV)'));
  }

  void _editConnection(NetworkCredentials credentials) {
    _hostController.text = credentials.host;
    _usernameController.text = credentials.username;
    _passwordController.text = credentials.password;
    _portController.text = credentials.port?.toString() ?? '443';

    if (credentials.additionalOptions != null) {
      try {
        final options = jsonDecode(credentials.additionalOptions!);
        _basePathController.text = options['basePath'] ?? '/webdav';
      } catch (e) {
        _basePathController.text = '/webdav';
      }
    } else {
      _basePathController.text = '/webdav';
    }

    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editWebdavConnection),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: l10n.host,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: l10n.username,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: l10n.password,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: l10n.port,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _basePathController,
                decoration: InputDecoration(
                  labelText: l10n.basePath,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateConnection(credentials);
            },
            child: Text(l10n.update),
          ),
        ],
      ),
    );
  }

  void _updateConnection(NetworkCredentials oldCredentials) {
    final theme = Theme.of(context);
    try {
      final additionalOptions = {
        'basePath': _basePathController.text.trim(),
        'useSSL': true, // Default for WebDAV
      };

      _credentialsService.saveCredentials(
        serviceType: 'WebDAV',
        host: _hostController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        port: int.tryParse(_portController.text),
        additionalOptions: additionalOptions,
      );

      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.connectionUpdatedSuccess),
          backgroundColor: theme.colorScheme.tertiary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${AppLocalizations.of(context)!.failedToUpdateConnection}: $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  void _deleteConnection(NetworkCredentials credentials) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteConnection),
        content: Text(l10n.deleteConnectionConfirm(credentials.host)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              try {
                _credentialsService.deleteCredentials(credentials.id);
                _refreshData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.connectionDeletedSuccess),
                    backgroundColor: theme.colorScheme.tertiary,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${l10n.failedToDeleteConnection}: $e'),
                    backgroundColor: theme.colorScheme.error,
                  ),
                );
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _addSampleConnection() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addSampleWebdavConnection),
        content: const Text(
          'This will add a sample connection to the DLP Test Site WebDAV server:\n\n'
          'Host: www.dlp-test.com\n'
          'Username: www.dlp-test.com\\WebDAV\n'
          'Password: WebDAV\n'
          'Port: 443\n'
          'Base Path: /webdav\n\n'
          'Do you want to add this sample connection?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addDLPTestConnection();
            },
            child: Text(l10n.addSample),
          ),
        ],
      ),
    );
  }

  void _addDLPTestConnection() {
    final theme = Theme.of(context);
    try {
      final additionalOptions = {
        'basePath': '/webdav',
        'useSSL': true,
      };

      _credentialsService.saveCredentials(
        serviceType: 'WebDAV',
        host: 'www.dlp-test.com',
        username: 'www.dlp-test.com\\WebDAV',
        password: 'WebDAV',
        port: 443,
        additionalOptions: additionalOptions,
      );

      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.sampleConnectionAddedSuccess),
          backgroundColor: theme.colorScheme.tertiary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${AppLocalizations.of(context)!.failedToAddSampleConnection}: $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SystemScreen(
      title: l10n.webdavConnections,
      systemId: '#webdav',
      icon: PhosphorIconsLight.globe,
      showAppBar: true,
      actions: [
        IconButton(
          icon: Icon(PhosphorIconsLight.arrowsClockwise),
          onPressed: _refreshData,
          tooltip: l10n.refresh,
        ),
        IconButton(
          icon: Icon(PhosphorIconsLight.plus),
          onPressed: _connectToWebDAVServer,
          tooltip: l10n.addConnection,
        ),
      ],
      child: BlocBuilder<NetworkBrowsingBloc, NetworkBrowsingState>(
        bloc: _networkBloc,
        builder: (context, state) {
          final activeConnections = state.connections.entries
              .where((entry) => (entry.value).serviceName == 'WebDAV')
              .toList();

          if (activeConnections.isEmpty && _savedCredentials.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    PhosphorIconsLight.globe,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noWebdavConnections,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.addConnectionOrSampleToStart,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _connectToWebDAVServer,
                        icon: Icon(PhosphorIconsLight.plus),
                        label: Text(l10n.addConnection),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _addSampleConnection,
                        icon: Icon(PhosphorIconsLight.plusCircle),
                        label: Text(l10n.addSample),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              if (activeConnections.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 8.0),
                  child: Text(l10n.activeConnections,
                      style: theme.textTheme.titleSmall),
                ),
                ...activeConnections.map(_buildActiveConnectionItem),
                const Divider(),
              ],
              if (_savedCredentials.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 8.0),
                  child: Text(l10n.savedConnections,
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    String host = l10n.unknown;
    try {
      host = Uri.parse(entry.value.basePath).host;
    } catch (_) {}

    return ListTile(
      leading:
          Icon(PhosphorIconsLight.globe, color: theme.colorScheme.tertiary),
      title: Text(host),
      subtitle: Text(l10n.connecting),
      onTap: () => _openTabForConnection(entry.key, host),
    );
  }

  Widget _buildSavedConnectionItem(NetworkCredentials credentials) {
    final isConnecting = _connectingCredentialIds.contains(credentials.id);
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(PhosphorIconsLight.globe, color: theme.colorScheme.primary),
      title: Text(credentials.host),
      subtitle: Builder(
        builder: (ctx) {
          final loc = AppLocalizations.of(ctx)!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(credentials.username),
              if (credentials.port != null)
                Text('${loc.port}: ${credentials.port}'),
              Text(loc.lastConnected(_formatDate(credentials.lastConnected))),
            ],
          );
        },
      ),
      trailing: Builder(
        builder: (ctx) {
          final loc = AppLocalizations.of(ctx)!;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isConnecting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              else ...[
                IconButton(
                  icon: Icon(PhosphorIconsLight.pencilSimple,
                      color: theme.colorScheme.secondary),
                  onPressed: () => _editConnection(credentials),
                  tooltip: loc.editConnection,
                ),
                IconButton(
                  icon: Icon(PhosphorIconsLight.trash,
                      color: theme.colorScheme.error),
                  onPressed: () => _deleteConnection(credentials),
                  tooltip: loc.deleteConnection,
                ),
                IconButton(
                  icon: Icon(PhosphorIconsLight.arrowCircleRight,
                      color: theme.colorScheme.tertiary),
                  onPressed: () => _connectWithSavedCredentials(credentials),
                  tooltip: loc.connect,
                ),
              ],
            ],
          );
        },
      ),
      onTap:
          isConnecting ? null : () => _connectWithSavedCredentials(credentials),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }
}

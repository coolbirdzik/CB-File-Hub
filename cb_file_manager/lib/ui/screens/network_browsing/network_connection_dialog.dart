import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../../bloc/network_browsing/network_browsing_event.dart';
import '../../../bloc/network_browsing/network_browsing_state.dart';
// Removed smb_connect import - using mobile_smb_native instead
import '../../../services/network_credentials_service.dart';
import '../../../models/database/network_credentials.dart';
import '../../utils/route.dart';

/// Dialog for entering network connection details
class NetworkConnectionDialog extends StatefulWidget {
  /// Initial service to select in the dropdown
  final String? initialService;

  /// Initial host to fill in the host field
  final String? initialHost;

  /// Callback when connection is requested
  final Function(String connectionPath, String tabName)? onConnectionRequested;

  const NetworkConnectionDialog({
    Key? key,
    this.initialService,
    this.initialHost,
    this.onConnectionRequested,
  }) : super(key: key);

  @override
  State<NetworkConnectionDialog> createState() =>
      _NetworkConnectionDialogState();
}

class _NetworkConnectionDialogState extends State<NetworkConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedService;
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController();
  final _basePathController = TextEditingController();
  bool _showPassword = false;
  bool _useSSL = true;
  String? _domain;

  // For SMB connection progress
  bool _connectingToServer = false;

  // Thêm biến để lưu thông tin đăng nhập
  bool _saveCredentials = true;

  // Lưu trữ danh sách các host đã lưu để autocomplete
  List<String> _savedHosts = [];
  // Lưu trữ các thông tin đăng nhập đã lưu để điền tự động
  List<NetworkCredentials> _savedCredentials = [];

  // Local bloc for handling connection logic
  late NetworkBrowsingBloc _localBloc;

  @override
  void initState() {
    super.initState();
    debugPrint(
        'NetworkConnectionDialog: initState() called on platform: ${Platform.operatingSystem}');
    _selectedService = widget.initialService ?? 'SMB';
    _localBloc = NetworkBrowsingBloc();

    // Set the host if provided
    if (widget.initialHost != null) {
      _hostController.text = widget.initialHost!;
      debugPrint(
          'NetworkConnectionDialog: Initial host set to: ${widget.initialHost}');
    } else {
      debugPrint('NetworkConnectionDialog: No initial host provided');
    }

    // Set default ports based on service
    _updateDefaultPort();

    // Load saved hosts immediately
    _loadSavedHosts(); // Load saved hosts for autocomplete

    // Đảm bảo host controller đã được thiết lập trước khi tải thông tin đăng nhập
    // Trên mobile, cần thêm delay dài hơn để đảm bảo giá trị đã được cập nhật
    Future.delayed(const Duration(milliseconds: 500), () {
      debugPrint(
          'NetworkConnectionDialog: Before loading credentials, host is: ${_hostController.text}');
      _loadSavedCredentials();
    });

    // Listen to connection results
    _localBloc.stream.listen((state) {
      if (state.lastSuccessfullyConnectedPath != null &&
          widget.onConnectionRequested != null) {
        final connectionPath = state.lastSuccessfullyConnectedPath!;
        // ignore: use_build_context_synchronously
        final tabName = _getTabNameFromPath(context, connectionPath);
        widget.onConnectionRequested!(connectionPath, tabName);
        // ignore: use_build_context_synchronously
        RouteUtils.safePopDialog(context);
      }
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _basePathController.dispose();
    _localBloc.close();
    super.dispose();
  }

  String _getTabNameFromPath(BuildContext context, String path) {
    try {
      if (path.startsWith('#network/')) {
        final parts = path.split('/');
        if (parts.length >= 4) {
          final host = Uri.decodeComponent(parts[2]);
          if (parts.length >= 4) {
            final share = Uri.decodeComponent(parts[3]);
            return '$host/$share';
          }
          return host;
        }
      }
    } catch (e) {
      debugPrint('Error parsing path for tab name: $e');
    }
    return AppLocalizations.of(context)!.networkConnection;
  }

  // Tải thông tin đăng nhập đã lưu
  Future<void> _loadSavedCredentials() async {
    // Đợi một chút để đảm bảo UI đã hiển thị
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final hostToSearch = _hostController.text.trim();
      debugPrint(
          'NetworkConnectionDialog: Loading saved credentials for host: "$hostToSearch", service: $_selectedService, platform: ${Platform.operatingSystem}');

      if (hostToSearch.isEmpty) {
        debugPrint(
            'NetworkConnectionDialog: Host is empty, skipping credential load');
        return;
      }

      // Chuẩn hóa host giống như trong NetworkCredentialsService
      final normalizedHost = hostToSearch
          .replaceAll(RegExp(r'^[a-z]+://'), '')
          .replaceAll(RegExp(r':\d+$'), '');
      debugPrint('NetworkConnectionDialog: Normalized host: "$normalizedHost"');

      // Tìm thông tin đăng nhập đã lưu cho dịch vụ hiện tại
      final credentials = NetworkCredentialsService().findCredentials(
        serviceType: _selectedService,
        host: hostToSearch,
      );

      debugPrint(
          'NetworkConnectionDialog: Credentials search result: ${credentials != null ? "FOUND" : "NOT FOUND"}');
      if (credentials != null) {
        debugPrint(
            'NetworkConnectionDialog: Found credentials details - host: ${credentials.host}, username: ${credentials.username}, domain: ${credentials.domain}, port: ${credentials.port}');
      }

      if (credentials != null && mounted) {
        debugPrint(
            'NetworkConnectionDialog: Applying saved credentials for $hostToSearch - username: ${credentials.username}');
        setState(() {
          _hostController.text = credentials.host;
          _usernameController.text = credentials.username;
          _passwordController.text = credentials.password;

          if (credentials.port != null) {
            _portController.text = credentials.port.toString();
          }

          if (_selectedService == 'SMB' && credentials.domain != null) {
            _domain = credentials.domain;
          }

          // Load basePath for WebDAV
          if (_selectedService == 'WebDAV' &&
              credentials.additionalOptions != null) {
            try {
              final options = jsonDecode(credentials.additionalOptions!);
              if (options['basePath'] != null) {
                _basePathController.text = options['basePath'];
              }
            } catch (e) {
              debugPrint('Error parsing additionalOptions: $e');
            }
          }
        });

        // Kiểm tra sau khi cập nhật
        debugPrint(
            'NetworkConnectionDialog: After update - Username controller: "${_usernameController.text}", Password set: ${_passwordController.text.isNotEmpty}');
      } else {
        debugPrint(
            'NetworkConnectionDialog: No saved credentials found for host: "$hostToSearch"');

        // Kiểm tra tất cả thông tin đăng nhập đã lưu để debug
        final allCredentials = NetworkCredentialsService()
            .getCredentialsByServiceType(_selectedService);
        debugPrint(
            'NetworkConnectionDialog: Found ${allCredentials.length} saved credentials for service "$_selectedService":');
        for (var cred in allCredentials) {
          debugPrint(
              '  - Host: "${cred.host}", Username: "${cred.username}", Domain: "${cred.domain}", Port: ${cred.port}');
        }
      }
    } catch (e) {
      debugPrint(
          'NetworkConnectionDialog: Error loading saved credentials: $e');
    }
  }

  // Tải danh sách host đã lưu để autocomplete
  Future<void> _loadSavedHosts() async {
    try {
      // Lấy tất cả thông tin đăng nhập cho dịch vụ hiện tại
      _savedCredentials = NetworkCredentialsService()
          .getCredentialsByServiceType(_selectedService);

      // Trích xuất danh sách các host
      Set<String> hostSet = {};
      for (var credential in _savedCredentials) {
        hostSet.add(credential.host);
      }

      if (mounted) {
        setState(() {
          _savedHosts = hostSet.toList();
          debugPrint(
              'Loaded ${_savedHosts.length} saved hosts for $_selectedService');
        });
      }
    } catch (e) {
      debugPrint('Error loading saved hosts: $e');
    }
  }

  Future<void> _deleteSavedHost(String host) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteSavedConnectionTitle),
        content: Text(l10n.deleteSavedConnectionConfirm(host)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete,
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final credsToDelete = NetworkCredentialsService().findCredentials(
          serviceType: _selectedService,
          host: host,
        );

        if (credsToDelete != null) {
          NetworkCredentialsService().deleteCredentials(credsToDelete.id);
          await _loadSavedHosts();

          if (_hostController.text == host) {
            _hostController.clear();
            _usernameController.clear();
            _passwordController.clear();
            _domain = null;
            _updateDefaultPort();
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.connectionDeleted(host))),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(l10n.connectionNotFoundToDelete(host)),
                  backgroundColor: theme.colorScheme.secondary),
            );
          }
        }
      } catch (e) {
        debugPrint('Error deleting host: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.errorDeletingConnection}: $e')),
          );
        }
      }
    }
  }

  void _updateDefaultPort() {
    switch (_selectedService) {
      case 'SMB':
        _portController.text = '445';
        break;
      case 'FTP':
        _portController.text = '21';
        break;
      case 'WebDAV':
        _portController.text = _useSSL ? '443' : '80';
        break;
      default:
        _portController.text = '';
    }
  }

  // Helper function to connect to SMB server and get shares
  Future<void> _connectToServerAndListShares() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _connectingToServer = true;
    });

    try {
      final serverAddress = _hostController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      debugPrint(
          'NetworkConnectionDialog: Connecting to SMB server: $serverAddress, username: $username, platform: ${Platform.operatingSystem}');
      debugPrint(
          'NetworkConnectionDialog: _saveCredentials value: $_saveCredentials');

      // Kết nối trực tiếp với SMB server mà không cần chọn share
      // Tạo event kết nối với server (không cần share)
      final event = NetworkConnectionRequested(
        serviceName: _selectedService,
        host: serverAddress, // Chỉ kết nối tới server, không kèm share
        username: username,
        password: password,
        port: _portController.text.isNotEmpty
            ? int.tryParse(_portController.text)
            : null,
        additionalOptions: {
          if (_domain != null) 'domain': _domain,
        },
      );

      _localBloc.add(event);

      // Lưu thông tin đăng nhập nếu được chọn
      debugPrint(
          'NetworkConnectionDialog: Should save credentials? $_saveCredentials');
      if (_saveCredentials) {
        debugPrint(
            'NetworkConnectionDialog: Saving credentials for SMB - host: $serverAddress, username: $username');
        await NetworkCredentialsService().saveCredentials(
          serviceType: _selectedService,
          host: serverAddress,
          username: username,
          password: password,
          port: _portController.text.isNotEmpty
              ? int.tryParse(_portController.text)
              : null,
          domain: _domain,
        );
        debugPrint('NetworkConnectionDialog: Credentials saved successfully');
      } else {
        debugPrint(
            'NetworkConnectionDialog: Not saving credentials because _saveCredentials is false');
      }
    } catch (e) {
      debugPrint('Error connecting to server: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .connectionFailed(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _connectingToServer = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocProvider.value(
      value: _localBloc,
      child: BlocBuilder<NetworkBrowsingBloc, NetworkBrowsingState>(
        bloc: _localBloc,
        builder: (context, state) {
          final isLoading =
              state.isLoading || state.isConnecting || _connectingToServer;

          final l10n = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(l10n.connectToServiceServer(_selectedService)),
            content: SizedBox(
              width: 400,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Service Selection Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedService,
                        decoration: InputDecoration(
                          labelText: l10n.serviceType,
                          border: const OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'SMB', child: Text('SMB')),
                          DropdownMenuItem(value: 'FTP', child: Text('FTP')),
                          DropdownMenuItem(
                              value: 'WebDAV', child: Text('WebDAV')),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedService = value!;
                                  _updateDefaultPort();
                                  _loadSavedHosts();
                                });
                              },
                      ),

                      const SizedBox(height: 16),

                      // Host Field with Autocomplete
                      Autocomplete<String>(
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          // Sync the controller with our _hostController
                          if (controller.text != _hostController.text) {
                            controller.text = _hostController.text;
                          }
                          _hostController.addListener(() {
                            if (controller.text != _hostController.text) {
                              controller.text = _hostController.text;
                            }
                          });

                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            enabled: !isLoading,
                            decoration: InputDecoration(
                              labelText: l10n.host,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              _hostController.text = value;
                              _loadSavedCredentials();
                            },
                            onFieldSubmitted: (value) {
                              onFieldSubmitted();
                            },
                          );
                        },
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return _savedHosts;
                          }
                          return _savedHosts.where((option) => option
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase()));
                        },
                        onSelected: (String option) {
                          _hostController.text = option;
                          _loadSavedCredentials();
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Material(
                            elevation: 0,
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: options.length,
                              shrinkWrap: true,
                              itemBuilder: (BuildContext context, int index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  title: Text(option),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                            PhosphorIconsLight.pencilSimple,
                                            size: 16),
                                        onPressed: () {
                                          // Stop dropdown from closing
                                          RouteUtils.safePopDialog(context);
                                          _deleteSavedHost(option);
                                        },
                                        tooltip: l10n.deleteSavedConnection,
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    onSelected(option);
                                  },
                                );
                              },
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Username Field
                      TextFormField(
                        controller: _usernameController,
                        enabled: !isLoading,
                        decoration: InputDecoration(
                          labelText: l10n.username,
                          border: const OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        enabled: !isLoading,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: l10n.password,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? PhosphorIconsLight.eye
                                  : PhosphorIconsLight.eyeSlash,
                            ),
                            onPressed: isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _showPassword = !_showPassword;
                                    });
                                  },
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Port Field
                      TextFormField(
                        controller: _portController,
                        enabled: !isLoading,
                        decoration: InputDecoration(
                          labelText: l10n.portOptional,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),

                      // Show additional options based on selected service
                      if (_selectedService == 'WebDAV') ...[
                        const SizedBox(height: 16),

                        // SSL Checkbox
                        CheckboxListTile(
                          title: Text(l10n.useSslTls),
                          value: _useSSL,
                          onChanged: isLoading
                              ? null
                              : (value) {
                                  setState(() {
                                    _useSSL = value ?? true;
                                    if (_portController.text == '443' ||
                                        _portController.text == '80') {
                                      _portController.text =
                                          _useSSL ? '443' : '80';
                                    }
                                  });
                                },
                        ),

                        const SizedBox(height: 16),

                        // Base Path Field
                        TextFormField(
                          controller: _basePathController,
                          enabled: !isLoading,
                          decoration: InputDecoration(
                            labelText: l10n.basePathOptional,
                            hintText: l10n.basePathHint,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],

                      if (_selectedService == 'SMB') ...[
                        const SizedBox(height: 16),

                        // Domain Field
                        TextFormField(
                          enabled: !isLoading,
                          decoration: InputDecoration(
                            labelText: l10n.domainOptional,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            _domain = value.isEmpty ? null : value;
                          },
                        ),
                      ],

                      // Error message display
                      if (state.hasError && state.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withValues(alpha: 0.1),
                            border: Border.all(
                                color:
                                    theme.colorScheme.error.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(PhosphorIconsLight.warning,
                                  color: theme.colorScheme.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.errorMessage!,
                                  style:
                                      TextStyle(color: theme.colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Save Credentials Checkbox
                      CheckboxListTile(
                        title: Text(l10n.saveCredentials),
                        subtitle: Text(l10n.saveCredentialsDescription),
                        value: _saveCredentials,
                        onChanged: isLoading
                            ? null
                            : (value) {
                                setState(() {
                                  _saveCredentials = value ?? true;
                                });
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : _selectedService == 'SMB'
                        ? _connectToServerAndListShares
                        : () {
                            if (_formKey.currentState!.validate()) {
                              _localBloc
                                  .add(const NetworkClearLastConnectedPath());

                              final host = _hostController.text.trim();
                              final username = _usernameController.text.trim();
                              final password = _passwordController.text;
                              final port = _portController.text.isNotEmpty
                                  ? int.tryParse(_portController.text)
                                  : null;

                              final event = NetworkConnectionRequested(
                                serviceName: _selectedService,
                                host: host,
                                username: username,
                                password: password,
                                port: port,
                                additionalOptions: {
                                  if (_selectedService == 'WebDAV')
                                    'useSSL': _useSSL,
                                  if (_selectedService == 'WebDAV' &&
                                      _basePathController.text.isNotEmpty)
                                    'basePath': _basePathController.text.trim(),
                                  if (_selectedService == 'SMB' &&
                                      _domain != null)
                                    'domain': _domain,
                                },
                              );
                              debugPrint(
                                  'NetworkConnectionDialog: Sending WebDAV connection event: $event');
                              _localBloc.add(event);

                              // Lưu thông tin đăng nhập nếu được chọn
                              if (_saveCredentials) {
                                NetworkCredentialsService().saveCredentials(
                                  serviceType: _selectedService,
                                  host: host,
                                  username: username,
                                  password: password,
                                  port: port,
                                  domain: _domain,
                                  additionalOptions: {
                                    if (_selectedService == 'WebDAV')
                                      'useSSL': _useSSL,
                                    if (_selectedService == 'WebDAV' &&
                                        _basePathController.text.isNotEmpty)
                                      'basePath':
                                          _basePathController.text.trim(),
                                  },
                                );
                              }
                            }
                          },
                child: isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: theme.colorScheme.onPrimary),
                      )
                    : Text(l10n.connect),
              ),
            ],
          );
        },
      ),
    );
  }
}

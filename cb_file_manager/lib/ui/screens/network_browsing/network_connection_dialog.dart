import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../../bloc/network_browsing/network_browsing_event.dart';
import '../../../bloc/network_browsing/network_browsing_state.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../helpers/core/text_utils.dart';
import '../../../models/database/network_credentials.dart';
import '../../../services/network_browsing/network_service_registry.dart';
import '../../../services/network_credentials_service.dart';
import '../../components/common/connection_form_row.dart';
import '../../utils/route.dart';
import '../ssh/ssh_host_dialog.dart';

// Removed smb_connect import - using mobile_smb_native instead

/// Dialog for entering network connection details
class NetworkConnectionDialog extends StatefulWidget {
  /// Initial service to select in the dropdown
  final String? initialService;

  /// Initial host to fill in the host field
  final String? initialHost;
  final NetworkServiceRegistry? registry;

  /// Callback when connection is requested
  final Function(String connectionPath, String tabName)? onConnectionRequested;

  const NetworkConnectionDialog({
    super.key,
    this.initialService,
    this.initialHost,
    this.registry,
    this.onConnectionRequested,
  });

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
  String _ftpSecurity = 'none';
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
      'NetworkConnectionDialog: initState() called on platform: ${Platform.operatingSystem}',
    );
    _selectedService = widget.initialService ?? 'SMB';
    _localBloc = NetworkBrowsingBloc(registry: widget.registry);

    // Set the host if provided
    if (widget.initialHost != null) {
      _hostController.text = widget.initialHost!;
      debugPrint(
        'NetworkConnectionDialog: Initial host set to: ${widget.initialHost}',
      );
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
      if (!mounted) return;
      debugPrint(
        'NetworkConnectionDialog: Before loading credentials, host is: ${_hostController.text}',
      );
      _loadSavedCredentials();
    });

    // Listen to connection results
    _localBloc.stream.listen((state) {
      if (!mounted) return;
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
    if (!mounted) return;

    try {
      final hostToSearch = _hostController.text.trim();
      debugPrint(
        'NetworkConnectionDialog: Loading saved credentials for host: "$hostToSearch", service: $_selectedService, platform: ${Platform.operatingSystem}',
      );

      if (hostToSearch.isEmpty) {
        debugPrint(
          'NetworkConnectionDialog: Host is empty, skipping credential load',
        );
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
        'NetworkConnectionDialog: Credentials search result: ${credentials != null ? "FOUND" : "NOT FOUND"}',
      );
      if (credentials != null) {
        debugPrint(
          'NetworkConnectionDialog: Found credentials details - host: ${credentials.host}, username: ${credentials.username}, domain: ${credentials.domain}, port: ${credentials.port}',
        );
      }

      if (credentials != null && mounted) {
        debugPrint(
          'NetworkConnectionDialog: Applying saved credentials for $hostToSearch - username: ${credentials.username}',
        );
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

          if (_selectedService == 'FTP' &&
              credentials.additionalOptions != null) {
            final options = jsonDecode(credentials.additionalOptions!);
            _ftpSecurity = options['ftpSecurity'] ?? 'none';
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
          'NetworkConnectionDialog: After update - Username controller: "${_usernameController.text}", Password set: ${_passwordController.text.isNotEmpty}',
        );
      } else {
        debugPrint(
          'NetworkConnectionDialog: No saved credentials found for host: "$hostToSearch"',
        );

        // Kiểm tra tất cả thông tin đăng nhập đã lưu để debug
        final allCredentials = NetworkCredentialsService()
            .getCredentialsByServiceType(_selectedService);
        debugPrint(
          'NetworkConnectionDialog: Found ${allCredentials.length} saved credentials for service "$_selectedService":',
        );
        for (var cred in allCredentials) {
          debugPrint(
            '  - Host: "${cred.host}", Username: "${cred.username}", Domain: "${cred.domain}", Port: ${cred.port}',
          );
        }
      }
    } catch (e) {
      debugPrint(
        'NetworkConnectionDialog: Error loading saved credentials: $e',
      );
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
            'Loaded ${_savedHosts.length} saved hosts for $_selectedService',
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading saved hosts: $e');
    }
  }

  Future<void> _deleteSavedHost(String host) async {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.cbColors;
    final confirmed = await RouteUtils.showAcrylicDialog<bool>(
      context: context,
      builder: (ctx) => CbDialog(
        destructive: true,
        icon: PhosphorIconsLight.trash,
        title: l10n.deleteSavedConnectionTitle,
        content: Text(l10n.deleteSavedConnectionConfirm(host)),
        actions: [
          CbButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: l10n.cancel,
          ),
          CbButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: l10n.delete,
            variant: CbButtonVariant.danger,
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
                backgroundColor: colors.surfaceRaised,
              ),
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
      case 'SFTP':
        _portController.text = '22';
        break;
      case 'FTP':
        _portController.text = _ftpSecurity == 'implicitTls' ? '990' : '21';
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
        'NetworkConnectionDialog: Connecting to SMB server: $serverAddress, username: $username, platform: ${Platform.operatingSystem}',
      );
      debugPrint(
        'NetworkConnectionDialog: _saveCredentials value: $_saveCredentials',
      );

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
        additionalOptions: {if (_domain != null) 'domain': _domain},
      );

      _localBloc.add(event);

      // Lưu thông tin đăng nhập nếu được chọn
      debugPrint(
        'NetworkConnectionDialog: Should save credentials? $_saveCredentials',
      );
      if (_saveCredentials) {
        debugPrint(
          'NetworkConnectionDialog: Saving credentials for SMB - host: $serverAddress, username: $username',
        );
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
          'NetworkConnectionDialog: Not saving credentials because _saveCredentials is false',
        );
      }
    } catch (e) {
      debugPrint('Error connecting to server: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.connectionFailed(e.toString()),
            ),
          ),
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
    final colors = context.cbColors;
    return BlocProvider.value(
      value: _localBloc,
      child: BlocBuilder<NetworkBrowsingBloc, NetworkBrowsingState>(
        bloc: _localBloc,
        builder: (context, state) {
          final isLoading =
              state.isLoading || state.isConnecting || _connectingToServer;

          final l10n = AppLocalizations.of(context)!;
          if (_selectedService == 'SFTP') {
            return SshHostDialog(
              connectSftp: true,
              onChangeService: () => setState(() {
                _selectedService = 'SMB';
                _updateDefaultPort();
                _loadSavedHosts();
              }),
              initialHost: widget.initialHost,
              onConnected: (path) =>
                  widget.onConnectionRequested?.call(path, 'SFTP'),
            );
          }
          return CbDialog(
            width: 800,
            icon: PhosphorIconsLight.plugsConnected,
            showCloseButton: !isLoading,
            title: l10n.connectToServiceServer(_selectedService),
            content: SizedBox(
              width: double.infinity,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Service Selection Dropdown
                      CbSelect<String>(
                        label: l10n.serviceType,
                        expand: true,
                        value: _selectedService,
                        items: const [
                          CbSelectItem(value: 'SMB', label: 'SMB'),
                          CbSelectItem(value: 'FTP', label: 'FTP / FTPS'),
                          CbSelectItem(value: 'SFTP', label: 'SFTP'),
                          CbSelectItem(value: 'WebDAV', label: 'WebDAV'),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedService = value;
                                  _updateDefaultPort();
                                  _loadSavedHosts();
                                });
                              },
                      ),

                      const SizedBox(height: CbSpacing.lg),

                      if (_selectedService == 'FTP') ...[
                        CbSelect<String>(
                          label: l10n.ftpSecurity,
                          expand: true,
                          value: _ftpSecurity,
                          items: [
                            CbSelectItem(value: 'none', label: l10n.ftpPlain),
                            CbSelectItem(
                              value: 'explicitTls',
                              label: l10n.ftpExplicitTls,
                            ),
                            CbSelectItem(
                              value: 'implicitTls',
                              label: l10n.ftpImplicitTls,
                            ),
                          ],
                          onChanged: isLoading
                              ? null
                              : (value) => setState(() {
                                  _ftpSecurity = value;
                                  _updateDefaultPort();
                                }),
                        ),
                        const SizedBox(height: CbSpacing.lg),
                      ],
                      ConnectionFormRow(
                        firstFlex: 3,
                        secondFlex: 1,
                        first: Autocomplete<String>(
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                // Sync the controller with our _hostController
                                if (controller.text != _hostController.text) {
                                  controller.text = _hostController.text;
                                }

                                return CbTextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  enabled: !isLoading,
                                  label: l10n.host,

                                  onChanged: (value) {
                                    _hostController.text = value;
                                    _loadSavedCredentials();
                                  },
                                  onSubmitted: (value) {
                                    onFieldSubmitted();
                                  },
                                );
                              },
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return _savedHosts;
                            }
                            return _savedHosts.where(
                              (option) => TextUtils.matchesSearch(
                                option,
                                textEditingValue.text,
                              ),
                            );
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
                                            size: 16,
                                          ),
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
                        second: CbTextField(
                          controller: _portController,
                          enabled: !isLoading,
                          label: l10n.portOptional,

                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(height: CbSpacing.xl),
                      ConnectionFormRow(
                        first: CbTextField(
                          controller: _usernameController,
                          enabled: !isLoading,
                          label: l10n.username,
                        ),
                        second: CbTextField(
                          controller: _passwordController,
                          autocorrect: false,
                          enableSuggestions: false,
                          enabled: !isLoading,
                          obscureText: !_showPassword,
                          label: l10n.password,
                          suffix: CbButton.icon(
                            tooltip: l10n.password,
                            icon: _showPassword
                                ? PhosphorIconsLight.eye
                                : PhosphorIconsLight.eyeSlash,
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
                      // Show additional options based on selected service
                      if (_selectedService == 'WebDAV') ...[
                        const SizedBox(height: CbSpacing.lg),

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
                                      _portController.text = _useSSL
                                          ? '443'
                                          : '80';
                                    }
                                  });
                                },
                        ),

                        const SizedBox(height: CbSpacing.lg),

                        // Base Path Field
                        CbTextField(
                          controller: _basePathController,
                          enabled: !isLoading,
                          label: l10n.basePathOptional,
                          placeholder: l10n.basePathHint,
                        ),
                      ],

                      if (_selectedService == 'SMB') ...[
                        const SizedBox(height: CbSpacing.lg),

                        // Domain Field
                        CbTextField(
                          enabled: !isLoading,
                          label: l10n.domainOptional,

                          onChanged: (value) {
                            _domain = value.isEmpty ? null : value;
                          },
                        ),
                      ],

                      // Error message display
                      if (state.hasError && state.errorMessage != null) ...[
                        const SizedBox(height: CbSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: CbDecorations.tint(
                            context,
                            colors.status.danger,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIconsLight.warning,
                                color: colors.status.danger,
                                size: 20,
                              ),
                              const SizedBox(width: CbSpacing.sm),
                              Expanded(
                                child: Text(
                                  state.errorMessage!,
                                  style: TextStyle(color: colors.status.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: CbSpacing.lg),

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
              CbButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                label: l10n.cancel,
              ),
              CbButton(
                variant: CbButtonVariant.primary,
                onPressed: isLoading
                    ? null
                    : _selectedService == 'SMB'
                    ? _connectToServerAndListShares
                    : () {
                        if (_formKey.currentState!.validate()) {
                          _localBloc.add(const NetworkClearLastConnectedPath());

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
                              if (_selectedService == 'FTP')
                                'ftpSecurity': _ftpSecurity,
                              if (_selectedService == 'WebDAV')
                                'useSSL': _useSSL,
                              if (_selectedService == 'WebDAV' &&
                                  _basePathController.text.isNotEmpty)
                                'basePath': _basePathController.text.trim(),
                              if (_selectedService == 'SMB' && _domain != null)
                                'domain': _domain,
                            },
                          );
                          debugPrint(
                            'NetworkConnectionDialog: Connecting to $_selectedService',
                          );
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
                                if (_selectedService == 'FTP')
                                  'ftpSecurity': _ftpSecurity,
                                if (_selectedService == 'WebDAV')
                                  'useSSL': _useSSL,
                                if (_selectedService == 'WebDAV' &&
                                    _basePathController.text.isNotEmpty)
                                  'basePath': _basePathController.text.trim(),
                              },
                            );
                          }
                        }
                      },
                loading: isLoading,
                label: l10n.connect,
              ),
            ],
          );
        },
      ),
    );
  }
}

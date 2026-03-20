import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/services/network_browsing/ftp_client/ftp_client.dart';
import 'package:cb_file_manager/bloc/network_browsing/network_browsing_bloc.dart';
import 'package:cb_file_manager/bloc/network_browsing/network_browsing_event.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/route.dart';

class FtpConnectionForm extends StatefulWidget {
  const FtpConnectionForm({Key? key}) : super(key: key);

  @override
  _FtpConnectionFormState createState() => _FtpConnectionFormState();
}

class _FtpConnectionFormState extends State<FtpConnectionForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '21');
  final TextEditingController _usernameController =
      TextEditingController(text: 'anonymous');
  final TextEditingController _passwordController =
      TextEditingController(text: 'anonymous@');

  bool _isLoading = false;
  bool _usePassiveMode = true; // Default to passive mode
  String? _connectionError;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _connectionError = null;
    });

    final host = _hostController.text;
    final port = int.tryParse(_portController.text) ?? 21;
    final username = _usernameController.text;
    final password = _passwordController.text;

    try {
      final ftpClient = FtpClient(
        host: host,
        port: port,
        username: username,
        password: password,
      );

      await ftpClient.connect();

      // Set passive mode based on selection
      await ftpClient.setPassiveMode(_usePassiveMode);

      // Try to list directory to verify connection works
      try {
        final files = await ftpClient.listDirectory();
        debugPrint(
            'FTP: Successfully listed ${files.length} files/directories');
      } catch (e) {
        debugPrint('FTP: Error listing directory: $e');
        // If listing fails, try toggling passive mode
        await ftpClient.togglePassiveMode();

        // Try listing again
        try {
          final files = await ftpClient.listDirectory();
          debugPrint(
              'FTP: Successfully listed ${files.length} files/directories after toggling passive mode');
          // Update passive mode to match what worked
          setState(() {
            _usePassiveMode = !_usePassiveMode;
          });
        } catch (e2) {
          debugPrint('FTP: Error listing directory after toggling mode: $e2');
          // Continue anyway, we'll show the error in the UI if needed
        }
      }

      // Continue with successful connection
      if (context.mounted) {
        context.read<NetworkBrowsingBloc>().add(
              NetworkConnectionRequested(
                serviceName: 'FTP',
                host: host,
                username: username,
                password: password,
                port: port,
                additionalOptions: {
                  'usePassiveMode': _usePassiveMode,
                },
              ),
            );
        RouteUtils.safePopDialog(context);
      }
    } catch (e) {
      setState(() {
        _connectionError =
            AppLocalizations.of(context)!.connectionFailed(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _hostController,
            decoration: InputDecoration(
              labelText: l10n.host,
              hintText: 'ftp.example.com',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.pleaseEnterHost;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _portController,
            decoration: InputDecoration(
              labelText: l10n.port,
              hintText: '21',
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.pleaseEnterPort;
              }
              final port = int.tryParse(value);
              if (port == null || port <= 0 || port > 65535) {
                return l10n.pleaseEnterValidPort;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: l10n.username,
              hintText: 'anonymous',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: l10n.password,
              hintText: 'anonymous@',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(l10n.connectionMode),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(l10n.passive),
                      icon: const Icon(PhosphorIconsLight.shieldCheck),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(l10n.active),
                      icon: const Icon(PhosphorIconsLight.network),
                    ),
                  ],
                  selected: {_usePassiveMode},
                  onSelectionChanged: (Set<bool> selection) {
                    setState(() {
                      _usePassiveMode = selection.first;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_connectionError != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.warningCircle,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connectionError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _isLoading ? null : () => RouteUtils.safePopDialog(context),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isLoading ? null : _connect,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(l10n.connect),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

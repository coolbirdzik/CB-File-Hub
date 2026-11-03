import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:xterm/xterm.dart';
import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/ssh/ssh_profile_store.dart';
import '../../components/common/screen_scaffold.dart';
import '../../../bloc/selection/selection.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../network_browsing/components/network_navigation_bar.dart';
import 'ssh_host_dialog.dart';

class SshTerminalScreen extends StatefulWidget {
  final String tabId, profileId;
  const SshTerminalScreen({
    super.key,
    required this.tabId,
    required this.profileId,
  });
  @override
  State<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends State<SshTerminalScreen> {
  final _terminal = Terminal(maxLines: 10000);
  final _focus = FocusNode();
  SSHClient? _client;
  SSHSession? _session;
  final _subscriptions = <StreamSubscription<String>>[];
  int _generation = 0;
  bool _connecting = false;
  String? _error;
  SshProfile? _profile;
  @override
  void initState() {
    super.initState();
    _terminal.onOutput = (data) =>
        _session?.stdin.add(Uint8List.fromList(utf8.encode(data)));
    _terminal.onResize = (w, h, pw, ph) =>
        _session?.resizeTerminal(w, h, pw, ph);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connect();
    });
  }

  void _disconnect() {
    _generation++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _session?.close();
    _session = null;
    _client?.close();
    _client = null;
  }

  Future<void> _connect() async {
    _disconnect();
    final generation = _generation;
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final store = SshProfileStore.instance;
      await store.load();
      final profile = store.profiles
          .where((p) => p.id == widget.profileId)
          .firstOrNull;
      if (profile == null) throw StateError('Saved SSH host no longer exists.');
      _profile = profile;
      final client = await SshConnector(store).connect(
        profile,
        onClientCreated: (client) {
          if (!mounted || generation != _generation) {
            client.close();
          } else {
            _client = client;
          }
        },
        trustPrompt: (h, port, type, fp, old) =>
            promptSshHostTrust(context, h, port, type, fp, old),
      );
      if (!mounted || generation != _generation) {
        client.close();
        return;
      }
      _client = client;
      final session = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: _terminal.viewWidth,
          height: _terminal.viewHeight,
        ),
      );
      if (!mounted || generation != _generation) {
        session.close();
        client.close();
        return;
      }
      _session = session;
      for (final stream in [session.stdout, session.stderr]) {
        _subscriptions.add(
          stream
              .cast<List<int>>()
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen(
                _terminal.write,
                onError: (Object e) {
                  if (mounted) setState(() => _error = e.toString());
                },
              ),
        );
      }
      unawaited(
        session.done.then(
          (_) {
            if (mounted && generation == _generation) {
              _disconnect();
              setState(() => _error = context.tr.sshDisconnected);
            }
          },
          onError: (Object e) {
            if (mounted && generation == _generation) {
              _disconnect();
              setState(() => _error = e.toString());
            }
          },
        ),
      );
      _focus.requestFocus();
    } catch (e) {
      if (mounted && generation == _generation) {
        _disconnect();
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _connecting = false);
      } else if (mounted && _session == null) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  void dispose() {
    _disconnect();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return ScreenScaffold(
      selectionState: const SelectionState(),
      isNetworkPath: true,
      isDesktop: true,
      onClearSelection: () {},
      showRemoveTagsDialog: (_) {},
      showManageAllTagsDialog: (_) {},
      showDeleteConfirmationDialog: (_) {},
      showAppBar: true,
      showSearchBar: false,
      searchBar: const SizedBox.shrink(),
      pathNavigationBar: Row(
        children: [
          CbButton.icon(
            icon: PhosphorIconsLight.house,
            tooltip: tr.sshWorkspace,
            onPressed: () => navigateNetworkTab(context, widget.tabId, '#ssh'),
          ),
          Expanded(
            child: Text(
              _profile?.name ?? 'SSH',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        CbButton.icon(
          icon: PhosphorIconsLight.arrowClockwise,
          tooltip: tr.sshReconnect,
          onPressed: _connecting ? null : _connect,
        ),
        CbButton.icon(
          icon: PhosphorIconsLight.stop,
          tooltip: tr.disconnect,
          onPressed: _session == null
              ? null
              : () {
                  _disconnect();
                  setState(() => _error = tr.sshDisconnected);
                },
        ),
        CbButton.icon(
          icon: PhosphorIconsLight.arrowsLeftRight,
          tooltip: tr.sshFileTransfer,
          onPressed: () => context.read<TabManagerBloc>().add(
            AddTab(
              path: '#ssh/transfer/${widget.profileId}',
              name: '${_profile?.name ?? 'SSH'} · SFTP',
              switchToTab: true,
            ),
          ),
        ),
        CbButton.icon(
          icon: PhosphorIconsLight.eraser,
          tooltip: tr.sshClearTerminal,
          onPressed: () => _terminal.write('\x1b[2J\x1b[H'),
        ),
      ],
      body: ClipRect(
        child: Column(
          children: [
            if (_connecting) const LinearProgressIndicator(),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: TerminalView(
                _terminal,
                focusNode: _focus,
                autofocus: true,
                padding: const EdgeInsets.all(12),
                readOnly: _session == null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

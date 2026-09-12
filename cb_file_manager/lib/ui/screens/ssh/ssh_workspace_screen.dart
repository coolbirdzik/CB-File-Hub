import 'package:cb_file_manager/ui/components/common/search_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/network_browsing/network_service_registry.dart';
import '../../../services/ssh/local_ssh_discovery.dart';
import '../../../services/ssh/ssh_profile_store.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../utils/route.dart';
import '../../utils/platform_utils.dart';
import '../../components/common/grid_list_collection.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../../helpers/core/text_utils.dart';
import '../folder_list/folder_list_state.dart';
import 'ssh_host_list_item.dart';
import '../network_browsing/components/network_navigation_bar.dart';
import '../system_screen.dart';
import 'ssh_host_dialog.dart';
import 'ssh_key_dialog.dart';

class SshWorkspaceScreen extends StatefulWidget {
  final String tabId;
  final bool sftpOnly;
  final SshProfileStore? store;
  final LocalSshDiscovery? discovery;
  final GridListViewController? viewController;
  const SshWorkspaceScreen({
    super.key,
    required this.tabId,
    this.sftpOnly = false,
    this.store,
    this.discovery,
    this.viewController,
  });
  @override
  State<SshWorkspaceScreen> createState() => _SshWorkspaceScreenState();
}

class _SshWorkspaceScreenState extends State<SshWorkspaceScreen> {
  late final store = widget.store ?? SshProfileStore.instance;
  late final _discovery = widget.discovery ?? LocalSshDiscovery();
  LocalSshSnapshot _local = const LocalSshSnapshot();
  final _search = TextEditingController();
  bool _loaded = false;
  String? _error, _connecting, _selectedProfileId;
  int _section = 0;
  late final _view =
      widget.viewController ??
      GridListViewController(
        load: () =>
            UserPreferences.instance.getGridListCollectionMode('ssh_hosts'),
        save: (mode) => UserPreferences.instance.setGridListCollectionMode(
          'ssh_hosts',
          mode,
        ),
      );
  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _view.addListener(_changed);
    _run(_view.initialize);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await store.load();
      if (mounted) setState(() => _loaded = true);
      final local = await _discovery.scan();
      if (mounted) {
        setState(() {
          _local = local;
          _loaded = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    _view.removeListener(_changed);
    if (widget.viewController == null) _view.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _edit([SshProfile? profile]) async {
    await RouteUtils.showAcrylicDialog(
      context: context,
      builder: (_) =>
          SshHostDialog(profile: profile, store: store, discovery: _discovery),
    );
  }

  Future<bool> _confirm(String name) async =>
      await RouteUtils.showAcrylicDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr.sshDeleteConfirm),
          content: Text(name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr.delete),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _browse(SshProfile p, {bool openInNewTab = false}) async {
    setState(() {
      _connecting = p.id;
      _error = null;
    });
    await _run(() async {
      final result = await NetworkServiceRegistry().connect(
        serviceName: 'SFTP',
        host: p.host,
        username: p.username,
        password: p.password,
        port: p.port,
        additionalOptions: {
          'keyId': p.keyId,
          'trustPrompt':
              (String h, int port, String type, String fp, String? old) =>
                  promptSshHostTrust(context, h, port, type, fp, old),
        },
      );
      if (!result.success) {
        throw StateError(result.errorMessage ?? 'SFTP connection failed');
      }
      if (mounted) {
        if (openInNewTab) {
          context.read<TabManagerBloc>().add(
            AddTab(
              path: result.connectedPath!,
              name: '${p.name} · SFTP',
              switchToTab: true,
            ),
          );
        } else {
          navigateNetworkTab(context, widget.tabId, result.connectedPath!);
          context.read<TabManagerBloc>().add(
            UpdateTabName(widget.tabId, '${p.name} · SFTP'),
          );
        }
      }
    });
    if (mounted) setState(() => _connecting = null);
  }

  void _openTerminal(SshProfile p) {
    navigateNetworkTab(context, widget.tabId, '#ssh/session/${p.id}');
    context.read<TabManagerBloc>().add(
      UpdateTabName(widget.tabId, '${p.name} · SSH'),
    );
  }

  void _openTerminalInNewTab(SshProfile p) =>
      context.read<TabManagerBloc>().add(
        AddTab(
          path: '#ssh/session/${p.id}',
          name: '${p.name} · SSH',
          switchToTab: true,
        ),
      );
  Future<void> _keyDialog({
    required bool generate,
    LocalSshKey? localKey,
  }) async {
    await showSshKeyDialog(
      context,
      store: store,
      generate: generate,
      localKey: localKey,
      localKeys: _local.keys,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final query = _search.text;
    final profiles =
        store.profiles
            .where(
              (p) => TextUtils.matchesSearch(
                '${p.name} ${p.host} ${p.username} ${p.group}',
                query,
              ),
            )
            .toList()
          ..sort(
            (a, b) => '${a.group}/${a.name}'.compareTo('${b.group}/${b.name}'),
          );
    return SystemScreen(
      tabId: widget.tabId,
      systemId: widget.sftpOnly ? '#sftp' : '#ssh',
      title: widget.sftpOnly ? 'SFTP' : tr.sshWorkspace,
      icon: PhosphorIconsLight.terminalWindow,
      showAppBar: true,
      viewMode: _section == 0 ? _view.mode : ViewMode.list,
      onRefresh: _load,
      actions: [
        if (widget.sftpOnly)
          CbButton.icon(
            icon: PhosphorIconsLight.terminalWindow,
            tooltip: tr.sshWorkspace,
            onPressed: () => navigateNetworkTab(context, widget.tabId, '#ssh'),
          ),
        CbButton.icon(
          icon: PhosphorIconsLight.plus,
          tooltip: tr.sshAddHost,
          onPressed: _loaded ? _edit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!widget.sftpOnly) ...[
                  ChoiceChip(
                    label: Text(tr.sshHosts),
                    selected: _section == 0,
                    onSelected: (_) => setState(() => _section = 0),
                  ),
                  ChoiceChip(
                    label: Text(tr.sshKeys),
                    selected: _section == 1,
                    onSelected: (_) => setState(() => _section = 1),
                  ),
                  ChoiceChip(
                    label: Text(tr.sshKnownHosts),
                    selected: _section == 2,
                    onSelected: (_) => setState(() => _section = 2),
                  ),
                ] else
                  Text('SFTP', style: Theme.of(context).textTheme.titleLarge),
                if (_section == 0)
                  CbButton(
                    icon: PhosphorIconsLight.plus,
                    label: tr.sshAddHost,
                    onPressed: _loaded ? _edit : null,
                  ),
                CbButton(
                  icon: PhosphorIconsLight.key,
                  label: tr.sshImportKey,
                  onPressed: _loaded ? () => _keyDialog(generate: false) : null,
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _error = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (!_loaded && _error == null) const LinearProgressIndicator(),
          if (_section == 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: SearchTextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: tr.search,
                        prefixIcon: const Icon(
                          PhosphorIconsLight.magnifyingGlass,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GridListViewToggle(
                    mode: _view.mode,
                    onChanged: (mode) => _run(() => _view.select(mode)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _selectedProfileId == null
                    ? null
                    : () => setState(() => _selectedProfileId = null),
                child: profiles.isEmpty
                    ? _empty(tr.sshNoHosts, () => _edit(), tr.sshAddHost)
                    : GridListCollection<SshProfile>(
                        mode: _view.mode,
                        isDesktop: isDesktopPlatform,
                        items: profiles,
                        identity: (p) => p.id,
                        onRefresh: _load,
                        itemBuilder: (_, p, mode) {
                          return SshHostListItem(
                            key: ValueKey(p.id),
                            name: p.name,
                            isGrid: mode == ViewMode.grid,
                            authenticationLabel: p.keyId == null
                                ? tr.sshPasswordAuth
                                : tr.sshKeyAuth,
                            description:
                                '${p.username}@${p.host}:${p.port}'
                                '${p.group.isEmpty ? '' : ' · ${p.group}'}',
                            isDesktop: isDesktopPlatform,
                            isSelected: _selectedProfileId == p.id,
                            isConnecting: _connecting == p.id,
                            terminalTooltip: tr.sshOpenTerminal,
                            browseTooltip: tr.sshBrowseFiles,
                            onSelect: () => setState(
                              () => _selectedProfileId =
                                  _selectedProfileId == p.id ? null : p.id,
                            ),
                            onOpen: _connecting != null
                                ? null
                                : () {
                                    if (widget.sftpOnly) {
                                      _browse(p);
                                    } else {
                                      _openTerminal(p);
                                    }
                                  },
                            onOpenInNewTab: _connecting != null
                                ? null
                                : () {
                                    if (widget.sftpOnly) {
                                      _browse(p, openInNewTab: true);
                                    } else {
                                      _openTerminalInNewTab(p);
                                    }
                                  },
                            onBrowse: _connecting == null
                                ? () => _browse(p)
                                : null,
                            onBrowseInNewTab: _connecting == null
                                ? () => _browse(p, openInNewTab: true)
                                : null,
                            showTerminalAction: !widget.sftpOnly,
                            menuTooltip: tr.moreOptions,
                            menuBuilder: (_) => [
                              PopupMenuItem<void>(
                                onTap: () => _openTerminal(p),
                                child: Text(tr.sshOpenTerminal),
                              ),
                              PopupMenuItem<void>(
                                onTap: () => _openTerminalInNewTab(p),
                                child: Text(
                                  '${tr.sshOpenTerminal} (${tr.openInNewTab})',
                                ),
                              ),
                              PopupMenuItem<void>(
                                enabled: _connecting == null,
                                onTap: () => _browse(p),
                                child: Text(
                                  _connecting == p.id
                                      ? tr.sshConnecting
                                      : tr.sshBrowseFiles,
                                ),
                              ),
                              PopupMenuItem<void>(
                                enabled: _connecting == null,
                                onTap: () => _browse(p, openInNewTab: true),
                                child: Text(
                                  '${tr.sshBrowseFiles} (${tr.openInNewTab})',
                                ),
                              ),
                              PopupMenuItem<void>(
                                onTap: () => _edit(p),
                                child: Text(tr.edit),
                              ),
                              PopupMenuItem<void>(
                                onTap: () => _run(() async {
                                  if (await _confirm(p.name)) {
                                    await store.deleteProfile(p.id);
                                  }
                                }),
                                child: Text(tr.delete),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ] else if (_section == 1)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      CbButton(
                        label: tr.sshGenerateKey,
                        onPressed: _loaded
                            ? () => _keyDialog(generate: true)
                            : null,
                      ),
                      CbButton(
                        label: tr.sshImportKey,
                        onPressed: _loaded
                            ? () => _keyDialog(generate: false)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_local.keys.isNotEmpty) ...[
                    Text(
                      tr.sshLocalKeys,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(tr.sshLocalKeysHint),
                    const SizedBox(height: 12),
                    for (final key in _local.keys)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.key_outlined),
                        title: Text(key.name),
                        subtitle: Text(key.path),
                        trailing: const Icon(Icons.add),
                        onTap: () => _keyDialog(generate: false, localKey: key),
                      ),
                    const Divider(height: 32),
                  ],
                  if (store.keys.isEmpty && _local.keys.isEmpty)
                    Text(tr.sshNoKeys),
                  for (final key in store.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            key.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SelectableText(
                            key.fingerprint,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: key.publicKey),
                                ),
                                child: Text(tr.sshCopyPublicKey),
                              ),
                              TextButton(
                                onPressed: () => _run(() async {
                                  if (store.profiles.any(
                                    (p) => p.keyId == key.id,
                                  )) {
                                    setState(() => _error = tr.sshKeyInUse);
                                    return;
                                  }
                                  if (await _confirm(key.name)) {
                                    await store.deleteKey(key.id);
                                  }
                                }),
                                child: Text(tr.delete),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (store.knownHosts.isEmpty) Text(tr.sshNoTrustedHosts),
                  for (final entry in store.knownHosts.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key),
                          SelectableText(entry.value),
                          TextButton(
                            onPressed: () => _run(() async {
                              if (await _confirm(entry.key)) {
                                await store.forgetHost(entry.key);
                              }
                            }),
                            child: Text(tr.sshForgetHost),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(String text, VoidCallback action, String label) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsLight.terminalWindow, size: 48),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          CbButton(label: label, onPressed: _loaded ? action : null),
        ],
      ),
    ),
  );
}

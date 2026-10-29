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
import '../../components/common/app_toast.dart';
import '../../components/common/grid_list_collection.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../../helpers/core/text_utils.dart';
import '../folder_list/folder_list_state.dart';
import 'ssh_host_list_item.dart';
import 'ssh_host_sort.dart';
import '../network_browsing/components/network_navigation_bar.dart';
import '../system_screen.dart';
import 'ssh_host_dialog.dart';
import 'ssh_key_dialog.dart';
import 'ssh_import_dialog.dart';
import 'ssh_proxy_dialog.dart';

/// Below this width every header action and inactive tab collapses to an
/// icon.
const double _compactWidth = 640;

/// Below this width only the secondary header actions collapse, so the tabs
/// and actions stay on one line beside the sidebar, even with Vietnamese
/// labels.
const double _wideWidth = 1040;

class SshWorkspaceScreen extends StatefulWidget {
  final String tabId;
  final bool sftpOnly;
  final SshProfileStore? store;
  final LocalSshDiscovery? discovery;
  final GridListViewController? viewController;
  final SshHostSortController? sortController;
  const SshWorkspaceScreen({
    super.key,
    required this.tabId,
    this.sftpOnly = false,
    this.store,
    this.discovery,
    this.viewController,
    this.sortController,
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
  late final _sort =
      widget.sortController ??
      SshHostSortController(
        load: () => UserPreferences.instance.getCollectionSort('ssh_hosts'),
        save: (sort) =>
            UserPreferences.instance.setCollectionSort('ssh_hosts', sort),
      );
  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _view.addListener(_changed);
    _sort.addListener(_changed);
    _run(_view.initialize);
    _run(_sort.initialize);
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
    _sort.removeListener(_changed);
    if (widget.sortController == null) _sort.dispose();
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
        builder: (context) => CbDialog(
          title: context.tr.sshDeleteConfirm,
          subtitle: name,
          icon: PhosphorIconsLight.trash,
          destructive: true,
          width: 440,
          actions: [
            CbButton(
              label: context.tr.cancel,
              onPressed: () => Navigator.pop(context, false),
            ),
            CbButton(
              label: context.tr.delete,
              variant: CbButtonVariant.danger,
              autofocus: true,
              onPressed: () => Navigator.pop(context, true),
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
          'proxyId': p.proxyId,
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

  Future<void> _importFromApp() => _run(() async {
    final summary = await showSshImportDialog(context, store);
    if (!mounted || summary == null) return;
    AppToast.success(
      context,
      context.tr.sshProxyImportSummary(
        summary.hosts,
        summary.keys,
        summary.proxies,
        summary.duplicates,
      ),
    );
  });

  Future<void> _deleteKey(SshStoredKey key) => _run(() async {
    if (store.profiles.any((p) => p.keyId == key.id)) {
      setState(() => _error = context.tr.sshKeyInUse);
      return;
    }
    if (await _confirm(key.name)) await store.deleteKey(key.id);
  });

  Future<void> _deleteProxy(SshProxy proxy) => _run(() async {
    if (store.profiles.any((p) => p.proxyId == proxy.id)) {
      setState(() => _error = context.tr.sshProxyInUse);
      return;
    }
    if (await _confirm(proxy.name)) await store.deleteProxy(proxy.id);
  });

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(
                context,
                compact: compact,
                wide: constraints.maxWidth >= _wideWidth,
              ),
              if (_error != null) _errorBanner(context),
              if (!_loaded && _error == null)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: switch (_section) {
                  0 => _hostsSection(context, compact: compact),
                  1 => _keysSection(context, compact: compact),
                  3 => _proxiesSection(context),
                  _ => _knownHostsSection(context),
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────

  Widget _header(
    BuildContext context, {
    required bool compact,
    required bool wide,
  }) {
    final tr = context.tr;
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, CbSpacing.lg, 20, CbSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: CbSpacing.md,
        runSpacing: CbSpacing.md,
        children: [
          if (widget.sftpOnly)
            Text(
              'SFTP',
              style: CbTypography.headingMd.copyWith(color: c.textPrimary),
            )
          else
            _SectionTabs(
              compact: compact,
              selected: _section,
              onSelected: (section) => setState(() => _section = section),
              tabs: [
                (
                  key: 'hosts',
                  icon: PhosphorIconsLight.hardDrives,
                  label: tr.sshHosts,
                  count: store.profiles.length,
                ),
                (
                  key: 'keys',
                  icon: PhosphorIconsLight.key,
                  label: tr.sshKeys,
                  count: store.keys.length,
                ),
                (
                  key: 'known-hosts',
                  icon: PhosphorIconsLight.shieldCheck,
                  label: tr.sshKnownHosts,
                  count: store.knownHosts.length,
                ),
                (
                  key: 'proxies',
                  icon: PhosphorIconsLight.arrowsSplit,
                  label: tr.sshProxies,
                  count: store.proxies.length,
                ),
              ],
            ),
          Wrap(
            spacing: CbSpacing.sm,
            runSpacing: CbSpacing.sm,
            children: _sectionActions(context, compact: compact, wide: wide),
          ),
        ],
      ),
    );
  }

  List<Widget> _sectionActions(
    BuildContext context, {
    required bool compact,
    required bool wide,
  }) {
    final tr = context.tr;
    Widget action(
      IconData icon,
      String label,
      VoidCallback onPressed, {
      bool primary = false,
    }) {
      final variant = primary
          ? CbButtonVariant.primary
          : CbButtonVariant.secondary;
      final enabled = _loaded ? onPressed : null;
      return compact || (!primary && !wide)
          ? CbButton.icon(
              icon: icon,
              tooltip: label,
              variant: variant,
              onPressed: enabled,
            )
          : CbButton(
              icon: icon,
              label: label,
              variant: variant,
              onPressed: enabled,
            );
    }

    final importFromApp = action(
      PhosphorIconsLight.downloadSimple,
      tr.sshImportFromApp,
      _importFromApp,
    );
    final importKey = action(
      PhosphorIconsLight.key,
      tr.sshImportKey,
      () => _keyDialog(generate: false),
    );
    return switch (_section) {
      0 => [
        importFromApp,
        importKey,
        action(PhosphorIconsLight.plus, tr.sshAddHost, _edit, primary: true),
      ],
      1 => [
        importKey,
        action(
          PhosphorIconsLight.sparkle,
          tr.sshGenerateKey,
          () => _keyDialog(generate: true),
          primary: true,
        ),
      ],
      3 => [
        importFromApp,
        action(
          PhosphorIconsLight.plus,
          tr.sshAddProxy,
          () => showSshProxyDialog(context, store),
          primary: true,
        ),
      ],
      _ => const [],
    };
  }

  Widget _errorBanner(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, CbSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.status.dangerSurface,
          borderRadius: CbRadii.mdAll,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CbSpacing.md,
            CbSpacing.xs,
            CbSpacing.xs,
            CbSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIconsLight.warningCircle,
                size: CbSizes.iconMd,
                color: c.status.danger,
              ),
              const SizedBox(width: CbSpacing.sm),
              Expanded(
                child: Text(
                  _error!,
                  style: CbTypography.body.copyWith(color: c.status.danger),
                ),
              ),
              CbButton.icon(
                icon: PhosphorIconsLight.x,
                tooltip: context.tr.close,
                size: CbButtonSize.sm,
                onPressed: () => setState(() => _error = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sections ────────────────────────────────────────────────────────────

  Widget _hostsSection(BuildContext context, {required bool compact}) {
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
          ..sort(_sort.compare);
    final search = CbTextField(
      controller: _search,
      placeholder: tr.search,
      prefixIcon: PhosphorIconsLight.magnifyingGlass,
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, CbSpacing.sm),
          child: Row(
            children: [
              if (compact)
                Expanded(child: search)
              else ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: SizedBox(width: 360, child: search),
                ),
                const Spacer(),
              ],
              const SizedBox(width: CbSpacing.sm),
              _sortMenu(context, compact: compact),
              const SizedBox(width: CbSpacing.xs),
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
                ? _empty(
                    context,
                    icon: PhosphorIconsLight.terminalWindow,
                    text: tr.sshNoHosts,
                    label: tr.sshAddHost,
                    action: () => _edit(),
                  )
                : Padding(
                    // The grid insets its cards by 8px; line them up with the
                    // header's 20px gutter. List rows stay full-bleed.
                    padding: EdgeInsets.symmetric(
                      horizontal: _view.mode == ViewMode.grid ? 12 : 0,
                    ),
                    child: GridListCollection<SshProfile>(
                      mode: _view.mode,
                      isDesktop: isDesktopPlatform,
                      items: profiles,
                      identity: (p) => p.id,
                      onRefresh: _load,
                      gridMinExtent: SshHostListItem.gridExtent,
                      gridMaxExtent: SshHostListItem.gridExtent,
                      itemBuilder: (_, p, mode) => _hostItem(context, p, mode),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _sortMenu(BuildContext context, {required bool compact}) {
    final tr = context.tr;
    String label(SshHostSortField field) => switch (field) {
      SshHostSortField.name => tr.sshDisplayName,
      SshHostSortField.host => tr.host,
      SshHostSortField.username => tr.username,
      SshHostSortField.group => tr.sshGroup,
    };
    IconData icon(SshHostSortField field) => switch (field) {
      SshHostSortField.name => PhosphorIconsLight.textAa,
      SshHostSortField.host => PhosphorIconsLight.globe,
      SshHostSortField.username => PhosphorIconsLight.user,
      SshHostSortField.group => PhosphorIconsLight.folders,
    };
    final direction = _sort.ascending
        ? PhosphorIconsLight.sortAscending
        : PhosphorIconsLight.sortDescending;
    return Material(
      type: MaterialType.transparency,
      child: MenuAnchor(
        builder: (context, controller, _) {
          void toggle() =>
              controller.isOpen ? controller.close() : controller.open();
          final tooltip = '${tr.sortByTooltip}: ${label(_sort.field)}';
          return compact
              ? CbButton.icon(
                  key: const ValueKey('ssh-host-sort'),
                  icon: direction,
                  tooltip: tooltip,
                  onPressed: toggle,
                )
              : CbButton(
                  key: const ValueKey('ssh-host-sort'),
                  icon: direction,
                  label: label(_sort.field),
                  trailingIcon: PhosphorIconsLight.caretDown,
                  variant: CbButtonVariant.ghost,
                  tooltip: tooltip,
                  onPressed: toggle,
                );
        },
        menuChildren: [
          for (final field in SshHostSortField.values)
            MenuItemButton(
              key: ValueKey('ssh-host-sort-${field.name}'),
              leadingIcon: Icon(icon(field), size: CbSizes.iconMd),
              trailingIcon: field == _sort.field
                  ? Icon(
                      _sort.ascending
                          ? PhosphorIconsLight.arrowUp
                          : PhosphorIconsLight.arrowDown,
                      size: CbSizes.iconSm,
                    )
                  : null,
              onPressed: () => _run(() => _sort.select(field)),
              child: Text(label(field)),
            ),
        ],
      ),
    );
  }

  Widget _hostItem(BuildContext context, SshProfile p, ViewMode mode) {
    final tr = context.tr;
    return SshHostListItem(
      key: ValueKey(p.id),
      name: p.name,
      isGrid: mode == ViewMode.grid,
      authenticationLabel: p.keyId == null ? tr.sshPasswordAuth : tr.sshKeyAuth,
      usesKeyAuth: p.keyId != null,
      description: '${p.username}@${p.host}:${p.port}',
      group: p.group,
      isDesktop: isDesktopPlatform,
      isSelected: _selectedProfileId == p.id,
      isConnecting: _connecting == p.id,
      terminalTooltip: tr.sshOpenTerminal,
      browseTooltip: tr.sshBrowseFiles,
      onSelect: () => setState(
        () => _selectedProfileId = _selectedProfileId == p.id ? null : p.id,
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
      onBrowse: _connecting == null ? () => _browse(p) : null,
      onBrowseInNewTab: _connecting == null
          ? () => _browse(p, openInNewTab: true)
          : null,
      showTerminalAction: !widget.sftpOnly,
      menuTooltip: tr.moreOptions,
      menuBuilder: (menuContext) => [
        _menuItem(
          menuContext,
          PhosphorIconsLight.terminalWindow,
          tr.sshOpenTerminal,
          () => _openTerminal(p),
        ),
        _menuItem(
          menuContext,
          PhosphorIconsLight.arrowSquareOut,
          '${tr.sshOpenTerminal} (${tr.openInNewTab})',
          () => _openTerminalInNewTab(p),
        ),
        const PopupMenuDivider(),
        _menuItem(
          menuContext,
          PhosphorIconsLight.folderOpen,
          _connecting == p.id ? tr.sshConnecting : tr.sshBrowseFiles,
          () => _browse(p),
          enabled: _connecting == null,
        ),
        _menuItem(
          menuContext,
          PhosphorIconsLight.arrowSquareOut,
          '${tr.sshBrowseFiles} (${tr.openInNewTab})',
          () => _browse(p, openInNewTab: true),
          enabled: _connecting == null,
        ),
        const PopupMenuDivider(),
        _menuItem(
          menuContext,
          PhosphorIconsLight.pencilSimple,
          tr.edit,
          () => _edit(p),
        ),
        _menuItem(
          menuContext,
          PhosphorIconsLight.trash,
          tr.delete,
          () => _run(() async {
            if (await _confirm(p.name)) await store.deleteProfile(p.id);
          }),
          danger: true,
        ),
      ],
    );
  }

  PopupMenuItem<void> _menuItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool enabled = true,
    bool danger = false,
  }) {
    final c = context.cbColors;
    final color = !enabled
        ? c.textDisabled
        : danger
        ? c.status.danger
        : c.textPrimary;
    return PopupMenuItem<void>(
      enabled: enabled,
      onTap: onTap,
      height: CbSizes.controlMd + CbSpacing.xs,
      child: Row(
        children: [
          Icon(
            icon,
            size: CbSizes.iconMd,
            color: danger && enabled ? color : c.iconSubtle,
          ),
          const SizedBox(width: CbSpacing.md),
          Flexible(
            child: Text(
              label,
              style: CbTypography.body.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _keysSection(BuildContext context, {required bool compact}) {
    final tr = context.tr;
    if (store.keys.isEmpty && _local.keys.isEmpty) {
      return _empty(
        context,
        icon: PhosphorIconsLight.key,
        text: tr.sshNoKeys,
        label: tr.sshGenerateKey,
        action: () => _keyDialog(generate: true),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, CbSpacing.xl),
      children: [
        for (final key in store.keys)
          _SshItemRow(
            icon: PhosphorIconsLight.key,
            title: key.name,
            badge: key.publicKey.split(' ').first,
            subtitle: key.fingerprint,
            selectableSubtitle: true,
            trailing: [
              CbButton.icon(
                icon: PhosphorIconsLight.copy,
                tooltip: tr.sshCopyPublicKey,
                size: CbButtonSize.sm,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: key.publicKey));
                  if (context.mounted) {
                    AppToast.success(context, '${tr.copied}${key.name}');
                  }
                },
              ),
              CbButton.icon(
                icon: PhosphorIconsLight.trash,
                tooltip: tr.delete,
                size: CbButtonSize.sm,
                onPressed: () => _deleteKey(key),
              ),
            ],
          ),
        if (_local.keys.isNotEmpty) ...[
          _GroupHeader(
            title: tr.sshLocalKeys,
            hint: tr.sshLocalKeysHint,
            first: store.keys.isEmpty,
          ),
          for (final key in _local.keys)
            _SshItemRow(
              icon: PhosphorIconsLight.desktop,
              muted: true,
              title: key.name,
              subtitle: key.path,
              onPressed: () => _keyDialog(generate: false, localKey: key),
              trailing: [
                if (compact)
                  CbButton.icon(
                    icon: PhosphorIconsLight.downloadSimple,
                    tooltip: tr.sshImportKey,
                    size: CbButtonSize.sm,
                    onPressed: () => _keyDialog(generate: false, localKey: key),
                  )
                else
                  CbButton(
                    icon: PhosphorIconsLight.downloadSimple,
                    label: tr.sshImportKey,
                    size: CbButtonSize.sm,
                    variant: CbButtonVariant.subtle,
                    onPressed: () => _keyDialog(generate: false, localKey: key),
                  ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _knownHostsSection(BuildContext context) {
    final tr = context.tr;
    if (store.knownHosts.isEmpty) {
      return _empty(
        context,
        icon: PhosphorIconsLight.shieldCheck,
        text: tr.sshNoTrustedHosts,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, CbSpacing.xl),
      children: [
        for (final entry in store.knownHosts.entries)
          _SshItemRow(
            icon: PhosphorIconsLight.shieldCheck,
            title: entry.key,
            subtitle: entry.value,
            selectableSubtitle: true,
            trailing: [
              CbButton.icon(
                icon: PhosphorIconsLight.shieldSlash,
                tooltip: tr.sshForgetHost,
                size: CbButtonSize.sm,
                onPressed: () => _run(() async {
                  if (await _confirm(entry.key)) {
                    await store.forgetHost(entry.key);
                  }
                }),
              ),
            ],
          ),
      ],
    );
  }

  Widget _proxiesSection(BuildContext context) {
    final tr = context.tr;
    if (store.proxies.isEmpty) {
      return _empty(
        context,
        icon: PhosphorIconsLight.arrowsSplit,
        text: tr.sshNoProxies,
        label: tr.sshAddProxy,
        action: () => showSshProxyDialog(context, store),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, CbSpacing.xl),
      children: [
        for (final proxy in store.proxies)
          _SshItemRow(
            icon: PhosphorIconsLight.arrowsSplit,
            title: proxy.name,
            badge: proxy.protocol,
            subtitle: '${proxy.host}:${proxy.port}',
            onPressed: () => showSshProxyDialog(context, store, proxy: proxy),
            trailing: [
              CbButton.icon(
                icon: PhosphorIconsLight.pencilSimple,
                tooltip: tr.edit,
                size: CbButtonSize.sm,
                onPressed: () =>
                    showSshProxyDialog(context, store, proxy: proxy),
              ),
              CbButton.icon(
                icon: PhosphorIconsLight.trash,
                tooltip: tr.delete,
                size: CbButtonSize.sm,
                onPressed: () => _deleteProxy(proxy),
              ),
            ],
          ),
      ],
    );
  }

  Widget _empty(
    BuildContext context, {
    required IconData icon,
    required String text,
    String? label,
    VoidCallback? action,
  }) {
    final c = context.cbColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CbSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.accent.tint,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 56,
                  child: Icon(icon, size: CbSizes.iconXl, color: c.accent.text),
                ),
              ),
              const SizedBox(height: CbSpacing.lg),
              Text(
                text,
                textAlign: TextAlign.center,
                style: CbTypography.body.copyWith(color: c.textSecondary),
              ),
              if (label != null && action != null) ...[
                const SizedBox(height: CbSpacing.lg),
                CbButton(
                  icon: PhosphorIconsLight.plus,
                  label: label,
                  variant: CbButtonVariant.primary,
                  onPressed: _loaded ? action : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

typedef _SectionTab = ({String key, IconData icon, String label, int count});

/// Segmented switcher for the workspace sections: a sunken track with the
/// active segment lifted onto the surface colour. When [compact], inactive
/// segments drop their label so all four fit a phone-width header.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.selected,
    required this.tabs,
    required this.onSelected,
    this.compact = false,
  });

  final int selected;
  final List<_SectionTab> tabs;
  final ValueChanged<int> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.fillSubtle,
          borderRadius: CbRadii.all(CbRadii.md + 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tabs.length; i++)
                _segment(context, i, tabs[i], i == selected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    int index,
    _SectionTab tab,
    bool isSelected,
  ) {
    final tokens = context.cb;
    final c = tokens.colors;
    final showLabel = isSelected || !compact;
    return Semantics(
      selected: isSelected,
      child: CbPressable(
        key: ValueKey('ssh-section-${tab.key}'),
        semanticLabel: tab.label,
        tooltip: showLabel ? null : tab.label,
        cursor: SystemMouseCursors.click,
        onPressed: () => onSelected(index),
        builder: (context, state) => AnimatedContainer(
          duration: CbDurations.fast,
          curve: CbCurves.standard,
          height: CbSizes.controlSm,
          padding: const EdgeInsets.symmetric(horizontal: CbSpacing.md - 2),
          decoration: BoxDecoration(
            // On dark themes the raised surface is too close to the track,
            // so the active segment takes the strongest fill step instead.
            color: isSelected
                ? (tokens.isDark ? c.fillPressed : c.surfaceRaised)
                : state.pressed
                ? c.fillPressed
                : state.hovered
                ? c.fillHover
                : c.fillSubtle.withValues(alpha: 0),
            borderRadius: CbRadii.mdAll,
            boxShadow: [
              if (isSelected && !tokens.isDark) ...tokens.shadowLevel1,
              if (state.focused) ...CbDecorations.focusRing(c),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tab.icon,
                size: CbSizes.iconSm,
                color: isSelected ? c.accent.text : c.iconSubtle,
              ),
              if (showLabel) ...[
                const SizedBox(width: CbSpacing.xs + 2),
                Text(
                  tab.label,
                  style: CbTypography.labelSm.copyWith(
                    color: isSelected ? c.textPrimary : c.textSecondary,
                  ),
                ),
              ],
              if (tab.count > 0) ...[
                const SizedBox(width: CbSpacing.xs + 2),
                Text(
                  '${tab.count}',
                  style: CbTypography.caption.copyWith(
                    color: c.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, this.hint, this.first = false});

  final String title;
  final String? hint;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 0 : CbSpacing.xl,
        bottom: CbSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: CbTypography.headingSm.copyWith(color: c.textPrimary),
          ),
          if (hint != null) ...[
            const SizedBox(height: CbSpacing.xxs),
            Text(
              hint!,
              style: CbTypography.bodySm.copyWith(color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A settings-card style row: icon tile, title with an optional badge, a
/// monospace detail line and trailing actions.
class _SshItemRow extends StatelessWidget {
  const _SshItemRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    this.trailing = const [],
    this.onPressed,
    this.selectableSubtitle = false,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle, badge;
  final List<Widget> trailing;
  final VoidCallback? onPressed;
  final bool selectableSubtitle, muted;

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final detailStyle = CbTypography.monoSm.copyWith(color: c.textSecondary);
    return CbSurface(
      margin: const EdgeInsets.only(bottom: CbSpacing.xs),
      padding: const EdgeInsets.fromLTRB(
        CbSpacing.md,
        CbSpacing.sm + 2,
        CbSpacing.sm,
        CbSpacing.sm + 2,
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: muted ? c.fill : c.accent.tint,
              borderRadius: CbRadii.smAll,
            ),
            child: SizedBox.square(
              dimension: CbSizes.controlMd,
              child: Icon(
                icon,
                size: CbSizes.iconMd,
                color: muted ? c.iconSubtle : c.accent.text,
              ),
            ),
          ),
          const SizedBox(width: CbSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: CbTypography.label.copyWith(
                          color: c.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null && badge!.isNotEmpty) ...[
                      const SizedBox(width: CbSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.fill,
                          borderRadius: CbRadii.all(CbRadii.xs),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CbSpacing.xs + 2,
                            vertical: 1,
                          ),
                          child: Text(
                            badge!,
                            style: CbTypography.labelXs.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: CbSpacing.xxs),
                  selectableSubtitle
                      ? SelectableText(subtitle!, style: detailStyle)
                      : Text(
                          subtitle!,
                          style: detailStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ],
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: CbSpacing.sm),
            for (final action in trailing) action,
          ],
        ],
      ),
    );
  }
}

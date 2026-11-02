import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
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
import '../../components/common/search_text_field.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../../helpers/core/text_utils.dart';
import '../folder_list/folder_list_state.dart';
import 'ssh_connection_status.dart';
import '../../components/common/shared_action_bar.dart';
import 'ssh_folder_item.dart';
import 'ssh_host_list_item.dart';
import 'ssh_section.dart';
import 'ssh_host_sort.dart';
import '../network_browsing/components/network_navigation_bar.dart';
import '../system_screen.dart';
import 'ssh_host_dialog.dart';
import 'ssh_key_dialog.dart';
import 'ssh_import_dialog.dart';
import 'ssh_proxy_dialog.dart';

/// Below this width row actions collapse to icons.
const double _compactWidth = 640;

class SshWorkspaceScreen extends StatefulWidget {
  final String tabId;
  final bool sftpOnly;
  final SshProfileStore? store;
  final LocalSshDiscovery? discovery;
  final GridListViewController? viewController;
  final SshHostSortController? sortController;

  /// Which section this tab path shows; `#sftp` always shows hosts.
  final SshSection section;
  const SshWorkspaceScreen({
    super.key,
    required this.tabId,
    this.sftpOnly = false,
    this.store,
    this.discovery,
    this.viewController,
    this.sortController,
    this.section = SshSection.hosts,
  });
  @override
  State<SshWorkspaceScreen> createState() => _SshWorkspaceScreenState();
}

class _SshWorkspaceScreenState extends State<SshWorkspaceScreen> {
  late final store = widget.store ?? SshProfileStore.instance;
  late final _discovery = widget.discovery ?? LocalSshDiscovery();
  LocalSshSnapshot _local = const LocalSshSnapshot();
  final _search = SearchTextController();
  final _searchFocus = FocusNode();
  bool _loaded = false;
  String? _error, _connecting, _selectedId;

  /// The latest file-browsing connection, kept after a failure so the card
  /// shows which step failed.
  String? _statusProfileId;
  SshConnectionStatus _status = const SshConnectionStatus();
  bool _searching = false;
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
    _searchFocus.dispose();
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
      _statusProfileId = p.id;
      _status = const SshConnectionStatus();
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
          'onPhase': (SshConnectPhase phase) {
            if (mounted && _statusProfileId == p.id) {
              setState(() => _status = SshConnectionStatus(phase: phase));
            }
          },
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
    if (mounted) {
      setState(() {
        _connecting = null;
        if (_statusProfileId != p.id) return;
        // A failure keeps its step on the card; success leaves the route.
        _status = _error == null
            ? const SshConnectionStatus()
            : SshConnectionStatus(phase: _status.phase, failed: true);
      });
    }
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

  SshSection get _section =>
      widget.sftpOnly ? SshSection.hosts : widget.section;

  void _openSearch() {
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      setState(() => _searching = true);
    }
  }

  /// Closing also clears the query, so no hidden filter keeps hiding items.
  void _closeSearch() => setState(() {
    _searching = false;
    _search.clear();
  });

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final hosts = _section == SshSection.hosts;
    return SystemScreen(
      tabId: widget.tabId,
      systemId: widget.sftpOnly ? '#sftp' : _section.path,
      title: widget.sftpOnly ? 'SFTP' : tr.sshWorkspace,
      icon: PhosphorIconsLight.terminalWindow,
      showAppBar: true,
      viewMode: hosts ? _view.mode : ViewMode.list,
      onRefresh: _load,
      showSearchBar: _searching,
      searchBar: _searchBar(context),
      onSearch: _openSearch,
      onEscape: _searching ? _closeSearch : null,
      actions: _actions(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) _errorBanner(context),
              if (!_loaded && _error == null)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: switch (_section) {
                  SshSection.hosts => _hostsSection(context),
                  SshSection.keys => _keysSection(context, compact: compact),
                  SshSection.proxies => _proxiesSection(context),
                  SshSection.knownHosts => _knownHostsSection(context),
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// The file browser's search bar, in the path's place while searching.
  Widget _searchBar(BuildContext context) {
    final tr = context.tr;
    return SizedBox(
      height: 40,
      child: SearchTextField(
        key: const ValueKey('ssh-search'),
        controller: _search,
        focusNode: _searchFocus,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: tr.search,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          prefixIcon: const Icon(PhosphorIconsLight.magnifyingGlass, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsLight.broom),
                  tooltip: tr.clearSearch,
                  onPressed: () => setState(_search.clear),
                ),
        ).flat(context, radius: 16),
      ),
    );
  }

  /// Toolbar actions in the file browser's order and style: search, sort and
  /// view mode (hosts only), refresh, add, more. As narrow as a phone, only
  /// add and more stay (and closing an open search); the rest moves into the
  /// more menu so the path keeps its room.
  List<Widget> _actions(BuildContext context) {
    final tr = context.tr;
    final enabled = _loaded;
    final hosts = _section == SshSection.hosts;
    final compact = MediaQuery.sizeOf(context).width < _compactWidth;
    final add = switch (_section) {
      SshSection.hosts => (tr.sshAddHost, () => _edit()),
      SshSection.keys => (tr.sshGenerateKey, () => _keyDialog(generate: true)),
      SshSection.proxies => (
        tr.sshAddProxy,
        () => showSshProxyDialog(context, store),
      ),
      SshSection.knownHosts => null,
    };
    void openWorkspace() => navigateNetworkTab(context, widget.tabId, '#ssh');
    final otherMode = _view.mode == ViewMode.grid
        ? ViewMode.list
        : ViewMode.grid;
    // Null separates groups.
    final more = <_MenuAction?>[
      if (widget.sftpOnly && compact)
        (
          key: null,
          icon: PhosphorIconsLight.terminalWindow,
          label: tr.sshWorkspace,
          run: openWorkspace,
        ),
      if (hosts || _section == SshSection.proxies)
        (
          key: null,
          icon: PhosphorIconsLight.downloadSimple,
          label: tr.sshImportFromApp,
          run: _importFromApp,
        ),
      if (hosts || _section == SshSection.keys)
        (
          key: null,
          icon: PhosphorIconsLight.key,
          label: tr.sshImportKey,
          run: () => _keyDialog(generate: false),
        ),
      if (compact) ...[
        null,
        if (!_searching)
          (
            key: const ValueKey('ssh-search-menu-action'),
            icon: PhosphorIconsLight.magnifyingGlass,
            label: tr.searchTooltip,
            run: _openSearch,
          ),
        if (hosts) ...[
          (
            key: const ValueKey('ssh-view-mode-toggle'),
            icon: otherMode == ViewMode.list
                ? PhosphorIconsLight.list
                : PhosphorIconsLight.squaresFour,
            label: otherMode == ViewMode.list
                ? tr.viewModeList
                : tr.viewModeGrid,
            run: () => _run(() => _view.select(otherMode)),
          ),
          for (final field in SshHostSortField.values)
            (
              key: ValueKey('ssh-host-sort-${field.name}'),
              icon: _sortIcon(field),
              label: '${tr.sortByTooltip}: ${_sortLabel(tr, field)}',
              run: () => _run(() => _sort.select(field)),
            ),
        ],
        (
          key: const ValueKey('shared-refresh-action'),
          icon: PhosphorIconsLight.arrowsClockwise,
          label: tr.refreshTooltip,
          run: _load,
        ),
      ],
    ];
    while (more.isNotEmpty && more.first == null) {
      more.removeAt(0);
    }
    final search = IconButton(
      key: const ValueKey('shared-search-action'),
      icon: Icon(
        _searching ? PhosphorIconsLight.x : PhosphorIconsLight.magnifyingGlass,
      ),
      tooltip: _searching ? tr.close : tr.searchTooltip,
      onPressed: _searching ? _closeSearch : _openSearch,
    );
    return [
      if (widget.sftpOnly && !compact)
        IconButton(
          icon: const Icon(PhosphorIconsLight.terminalWindow),
          tooltip: tr.sshWorkspace,
          onPressed: openWorkspace,
        ),
      if (hosts && !compact)
        ...SharedActionBar.buildCommonActions(
          context: context,
          onSearchPressed: _searching ? _closeSearch : _openSearch,
          isSearchActive: _searching,
          sortAction: _sortMenu(context),
          onSortOptionSelected: (_) {},
          currentSortOption: SortOption.nameAsc,
          viewMode: _view.mode,
          allowedViewModes: const {ViewMode.list, ViewMode.grid},
          onViewModeToggled: () {},
          onViewModeSelected: (mode) => _run(() => _view.select(mode)),
          onRefresh: _load,
          onSelectionModeToggled: () {},
          showMoreOptions: false,
        )
      else ...[
        if (!compact || _searching) search,
        if (!compact)
          IconButton(
            key: const ValueKey('shared-refresh-action'),
            icon: const Icon(PhosphorIconsLight.arrowsClockwise),
            tooltip: tr.refreshTooltip,
            onPressed: _load,
          ),
      ],
      if (add != null)
        IconButton(
          key: const ValueKey('ssh-add-action'),
          icon: const Icon(PhosphorIconsLight.plus),
          tooltip: add.$1,
          onPressed: enabled ? add.$2 : null,
        ),
      if (more.isNotEmpty)
        PopupMenuButton<VoidCallback>(
          key: const ValueKey('ssh-more-action'),
          icon: const Icon(PhosphorIconsLight.dotsThreeVertical),
          tooltip: tr.moreOptionsTooltip,
          offset: const Offset(0, 50),
          enabled: enabled,
          onSelected: (run) => run(),
          itemBuilder: (context) => [
            for (final action in more)
              if (action == null)
                const PopupMenuDivider()
              else
                PopupMenuItem(
                  key: action.key,
                  value: action.run,
                  child: Row(
                    children: [
                      Icon(action.icon, size: 20),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          action.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
    ];
  }

  Widget _errorBanner(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, CbSpacing.sm, 20, CbSpacing.sm),
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
                onPressed: () => setState(() {
                  _error = null;
                  if (_status.failed) _status = const SshConnectionStatus();
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sections ────────────────────────────────────────────────────────────

  Widget _hostsSection(BuildContext context) {
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
    // The other sections sit before the hosts, like folders before files.
    final entries = <_HostsEntry>[
      if (!widget.sftpOnly && query.isEmpty)
        for (final section in [
          SshSection.keys,
          SshSection.knownHosts,
          SshSection.proxies,
        ])
          _SectionEntry(section),
      for (final profile in profiles) _ProfileEntry(profile),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _selectedId == null
          ? null
          : () => setState(() => _selectedId = null),
      child: entries.isEmpty
          ? _empty(
              context,
              icon: PhosphorIconsLight.terminalWindow,
              text: tr.sshNoHosts,
              label: tr.sshAddHost,
              action: () => _edit(),
            )
          : GridListCollection<_HostsEntry>(
              mode: _view.mode,
              isDesktop: isDesktopPlatform,
              items: entries,
              identity: (entry) => entry.id,
              onRefresh: _load,
              gridMinExtent: SshHostListItem.gridExtent,
              gridMaxExtent: SshHostListItem.gridExtent,
              itemBuilder: (_, entry, mode) => switch (entry) {
                _SectionEntry(:final section) => _folderItem(
                  context,
                  section,
                  mode,
                ),
                _ProfileEntry(:final profile) => _hostItem(
                  context,
                  profile,
                  mode,
                ),
              },
            ),
    );
  }

  Widget _folderItem(BuildContext context, SshSection section, ViewMode mode) {
    final tr = context.tr;
    final id = 'section:${section.name}';
    final count = switch (section) {
      SshSection.keys => store.keys.length,
      SshSection.knownHosts => store.knownHosts.length,
      SshSection.proxies => store.proxies.length,
      SshSection.hosts => store.profiles.length,
    };
    return SshFolderItem(
      key: ValueKey('ssh-section-${section.path.split('/').last}'),
      icon: switch (section) {
        SshSection.keys => PhosphorIconsLight.key,
        SshSection.knownHosts => PhosphorIconsLight.shieldCheck,
        SshSection.proxies => PhosphorIconsLight.arrowsSplit,
        SshSection.hosts => PhosphorIconsLight.hardDrives,
      },
      name: section.label(tr),
      detail: tr.itemsCount(count),
      isGrid: mode == ViewMode.grid,
      isDesktop: isDesktopPlatform,
      isSelected: _selectedId == id,
      onSelect: () =>
          setState(() => _selectedId = _selectedId == id ? null : id),
      onOpen: () => navigateNetworkTab(context, widget.tabId, section.path),
    );
  }

  String _sortLabel(AppLocalizations tr, SshHostSortField field) =>
      switch (field) {
        SshHostSortField.name => tr.sshDisplayName,
        SshHostSortField.host => tr.host,
        SshHostSortField.username => tr.username,
        SshHostSortField.group => tr.sshGroup,
      };

  IconData _sortIcon(SshHostSortField field) => switch (field) {
    SshHostSortField.name => PhosphorIconsLight.textAa,
    SshHostSortField.host => PhosphorIconsLight.globe,
    SshHostSortField.username => PhosphorIconsLight.user,
    SshHostSortField.group => PhosphorIconsLight.folders,
  };

  /// The file browser's sort icon, with the host fields.
  Widget _sortMenu(BuildContext context) {
    final tr = context.tr;
    final primary = Theme.of(context).colorScheme.primary;
    String label(SshHostSortField field) => _sortLabel(tr, field);
    IconData icon(SshHostSortField field) => _sortIcon(field);
    return PopupMenuButton<SshHostSortField>(
      key: const ValueKey('ssh-host-sort'),
      icon: Icon(
        _sort.ascending
            ? PhosphorIconsLight.sortAscending
            : PhosphorIconsLight.sortDescending,
      ),
      tooltip: '${tr.sortByTooltip}: ${label(_sort.field)}',
      offset: const Offset(0, 50),
      onSelected: (field) => _run(() => _sort.select(field)),
      itemBuilder: (context) => [
        for (final field in SshHostSortField.values)
          PopupMenuItem(
            key: ValueKey('ssh-host-sort-${field.name}'),
            value: field,
            child: Row(
              children: [
                Icon(
                  icon(field),
                  size: 20,
                  color: field == _sort.field ? primary : null,
                ),
                const SizedBox(width: 10),
                Text(
                  label(field),
                  style: TextStyle(
                    fontWeight: field == _sort.field
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: field == _sort.field ? primary : null,
                  ),
                ),
                const Spacer(),
                if (field == _sort.field)
                  Icon(
                    _sort.ascending
                        ? PhosphorIconsLight.arrowUp
                        : PhosphorIconsLight.arrowDown,
                    size: 20,
                    color: primary,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _hostItem(BuildContext context, SshProfile p, ViewMode mode) {
    final tr = context.tr;
    final proxy = p.proxyId == null
        ? null
        : store.proxies.where((x) => x.id == p.proxyId).firstOrNull;
    return SshHostListItem(
      key: ValueKey(p.id),
      name: p.name,
      routeLabel: p.proxyId == null
          ? tr.sshProxyNone
          : '${tr.sshProxy}: ${proxy == null ? '—' : sshProxyDescription(proxy)}',
      viaProxy: p.proxyId != null,
      connectionStatus: _statusProfileId == p.id ? _status : null,
      isGrid: mode == ViewMode.grid,
      authenticationLabel: p.keyId == null ? tr.sshPasswordAuth : tr.sshKeyAuth,
      usesKeyAuth: p.keyId != null,
      description: '${p.username}@${p.host}:${p.port}',
      group: p.group,
      isDesktop: isDesktopPlatform,
      isSelected: _selectedId == p.id,
      isConnecting: _connecting == p.id,
      terminalTooltip: tr.sshOpenTerminal,
      browseTooltip: tr.sshBrowseFiles,
      onSelect: () =>
          setState(() => _selectedId = _selectedId == p.id ? null : p.id),
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
    final query = _search.text;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, CbSpacing.sm, 20, CbSpacing.xl),
      children: [
        for (final key in store.keys.where(
          (k) => TextUtils.matchesSearch('${k.name} ${k.fingerprint}', query),
        ))
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
        if (_local.keys.isNotEmpty && query.isEmpty) ...[
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
    final query = _search.text;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, CbSpacing.sm, 20, CbSpacing.xl),
      children: [
        for (final entry in store.knownHosts.entries.where(
          (e) => TextUtils.matchesSearch(e.key, query),
        ))
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
    final query = _search.text;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, CbSpacing.sm, 20, CbSpacing.xl),
      children: [
        for (final proxy in store.proxies.where(
          (x) => TextUtils.matchesSearch('${x.name} ${x.host}', query),
        ))
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

typedef _MenuAction = ({
  Key? key,
  IconData icon,
  String label,
  VoidCallback run,
});

sealed class _HostsEntry {
  const _HostsEntry();
  String get id;
}

class _SectionEntry extends _HostsEntry {
  const _SectionEntry(this.section);
  final SshSection section;
  @override
  String get id => 'section:${section.name}';
}

class _ProfileEntry extends _HostsEntry {
  const _ProfileEntry(this.profile);
  final SshProfile profile;
  @override
  String get id => profile.id;
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

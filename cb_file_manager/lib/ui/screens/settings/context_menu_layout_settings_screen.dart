// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../helpers/files/context_menu_layout_preferences.dart';
import '../../components/common/app_toast.dart';

class ContextMenuLayoutSettingsScreen extends StatefulWidget {
  final ContextMenuLayoutTarget initialTarget;

  const ContextMenuLayoutSettingsScreen({
    Key? key,
    this.initialTarget = ContextMenuLayoutTarget.file,
  }) : super(key: key);

  @override
  State<ContextMenuLayoutSettingsScreen> createState() =>
      _ContextMenuLayoutSettingsScreenState();
}

class _ContextMenuLayoutSettingsScreenState
    extends State<ContextMenuLayoutSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Map<ContextMenuLayoutTarget, ContextMenuLayoutPreference> _layouts =
      <ContextMenuLayoutTarget, ContextMenuLayoutPreference>{};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: ContextMenuLayoutTarget.values.length,
      initialIndex: widget.initialTarget.index,
      vsync: this,
    )..addListener(_handleTabChanged);
    _loadLayouts();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  Future<void> _loadLayouts() async {
    final loaded = <ContextMenuLayoutTarget, ContextMenuLayoutPreference>{};
    for (final target in ContextMenuLayoutTarget.values) {
      loaded[target] = await ContextMenuLayoutPreferences.instance.load(target);
    }
    if (!mounted) return;
    setState(() {
      _layouts
        ..clear()
        ..addAll(loaded);
      _isLoading = false;
    });
  }

  Future<void> _saveLayout(
    ContextMenuLayoutTarget target,
    ContextMenuLayoutPreference layout,
  ) async {
    setState(() {
      _layouts[target] = layout;
    });
    await ContextMenuLayoutPreferences.instance.save(target, layout);
  }

  Future<void> _resetCurrentLayout() async {
    final target = ContextMenuLayoutTarget.values[_tabController.index];
    await ContextMenuLayoutPreferences.instance.reset(target);
    if (!mounted) return;
    setState(() {
      _layouts[target] = ContextMenuLayoutPreference.defaults(target);
    });
    AppToast.info(
        context, AppLocalizations.of(context)!.contextMenuLayoutReset);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.contextMenuLayout),
        actions: [
          IconButton(
            tooltip: l10n.resetContextMenuLayout,
            onPressed: _isLoading ? null : _resetCurrentLayout,
            icon: const Icon(PhosphorIconsLight.arrowCounterClockwise),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(PhosphorIconsLight.file),
              text: l10n.contextMenuForFiles,
            ),
            Tab(
              icon: const Icon(PhosphorIconsLight.folder),
              text: l10n.contextMenuForFolders,
            ),
            Tab(
              icon: const Icon(PhosphorIconsLight.files),
              text: l10n.contextMenuForMultipleItems,
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withAlpha(110),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsLight.info, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(l10n.contextMenuLayoutHint)),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: ContextMenuLayoutTarget.values
                        .map(_buildLayoutList)
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLayoutList(ContextMenuLayoutTarget target) {
    final layout =
        _layouts[target] ?? ContextMenuLayoutPreference.defaults(target);
    final descriptors = _descriptorsFor(context, target);
    final descriptorById = <String, _ContextMenuCommandDescriptor>{
      for (final descriptor in descriptors) descriptor.id: descriptor,
    };
    final orderedDescriptors = <_ContextMenuCommandDescriptor>[
      for (final id in layout.order)
        if (descriptorById.containsKey(id)) descriptorById[id]!,
    ];

    return ReorderableListView.builder(
      key: PageStorageKey<String>('context-menu-layout-${target.name}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      buildDefaultDragHandles: false,
      itemCount: orderedDescriptors.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        final reorderedIds =
            orderedDescriptors.map((descriptor) => descriptor.id).toList();
        final movedId = reorderedIds.removeAt(oldIndex);
        reorderedIds.insert(newIndex, movedId);
        var reorderedIndex = 0;
        final nextOrder = layout.order.map((id) {
          if (!descriptorById.containsKey(id)) {
            return id;
          }
          return reorderedIds[reorderedIndex++];
        }).toList();
        _saveLayout(target, layout.copyWith(order: nextOrder));
      },
      itemBuilder: (context, index) {
        final descriptor = orderedDescriptors[index];
        final isVisible = !layout.hiddenIds.contains(descriptor.id);
        return Card(
          key: ValueKey<String>('context-menu-command-${descriptor.id}'),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(descriptor.icon),
            title: Text(descriptor.label),
            subtitle: descriptor.id == contextMenuThirdPartyAppsId
                ? Text(AppLocalizations.of(context)!.thirdPartyApps)
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isVisible,
                  onChanged: (value) {
                    final hiddenIds = Set<String>.of(layout.hiddenIds);
                    if (value) {
                      hiddenIds.remove(descriptor.id);
                    } else {
                      hiddenIds.add(descriptor.id);
                    }
                    _saveLayout(
                      target,
                      layout.copyWith(hiddenIds: hiddenIds),
                    );
                  },
                ),
                const SizedBox(width: 4),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(PhosphorIconsLight.dotsSixVertical),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ContextMenuCommandDescriptor {
  final String id;
  final String label;
  final IconData icon;

  const _ContextMenuCommandDescriptor({
    required this.id,
    required this.label,
    required this.icon,
  });
}

List<_ContextMenuCommandDescriptor> _descriptorsFor(
  BuildContext context,
  ContextMenuLayoutTarget target,
) {
  final l10n = AppLocalizations.of(context)!;
  final common = <String, _ContextMenuCommandDescriptor>{
    'open': _ContextMenuCommandDescriptor(
      id: 'open',
      label: l10n.open,
      icon: PhosphorIconsLight.folderOpen,
    ),
    'copy': _ContextMenuCommandDescriptor(
      id: 'copy',
      label: l10n.copy,
      icon: PhosphorIconsLight.copy,
    ),
    'cut': _ContextMenuCommandDescriptor(
      id: 'cut',
      label: l10n.cut,
      icon: PhosphorIconsLight.scissors,
    ),
    'rename': _ContextMenuCommandDescriptor(
      id: 'rename',
      label: l10n.rename,
      icon: PhosphorIconsLight.pencilSimple,
    ),
    'tags': _ContextMenuCommandDescriptor(
      id: 'tags',
      label: l10n.manageTags,
      icon: PhosphorIconsLight.tag,
    ),
    'properties': _ContextMenuCommandDescriptor(
      id: 'properties',
      label: l10n.properties,
      icon: PhosphorIconsLight.info,
    ),
    'delete': _ContextMenuCommandDescriptor(
      id: 'delete',
      label: l10n.moveToTrash,
      icon: PhosphorIconsLight.trash,
    ),
    contextMenuThirdPartyAppsId: _ContextMenuCommandDescriptor(
      id: contextMenuThirdPartyAppsId,
      label: l10n.thirdPartyApps,
      icon: PhosphorIconsLight.appWindow,
    ),
    'more_options': _ContextMenuCommandDescriptor(
      id: 'more_options',
      label: l10n.moreOptions,
      icon: PhosphorIconsLight.dotsThreeVertical,
    ),
  };

  switch (target) {
    case ContextMenuLayoutTarget.file:
      return <_ContextMenuCommandDescriptor>[
        _ContextMenuCommandDescriptor(
          id: 'play_video',
          label: l10n.playVideo,
          icon: PhosphorIconsLight.play,
        ),
        _ContextMenuCommandDescriptor(
          id: 'view_image',
          label: l10n.viewImage,
          icon: PhosphorIconsLight.image,
        ),
        common['open']!,
        _ContextMenuCommandDescriptor(
          id: 'open_file_location',
          label: l10n.fileLocation,
          icon: PhosphorIconsLight.folderOpen,
        ),
        _ContextMenuCommandDescriptor(
          id: 'open_in_new_tab',
          label: l10n.openInNewTab,
          icon: PhosphorIconsLight.tabs,
        ),
        _ContextMenuCommandDescriptor(
          id: 'open_in_new_window',
          label: '${l10n.open} ${l10n.newWindow.toLowerCase()}',
          icon: PhosphorIconsLight.appWindow,
        ),
        _ContextMenuCommandDescriptor(
          id: 'open_with',
          label: l10n.openWith,
          icon: PhosphorIconsLight.appWindow,
        ),
        _ContextMenuCommandDescriptor(
          id: 'choose_default_app',
          label: l10n.chooseDefaultApp,
          icon: PhosphorIconsLight.checkCircle,
        ),
        _ContextMenuCommandDescriptor(
          id: 'download',
          label: l10n.download,
          icon: PhosphorIconsLight.downloadSimple,
        ),
        common['copy']!,
        common['cut']!,
        common['rename']!,
        common['tags']!,
        common['properties']!,
        common['delete']!,
        common[contextMenuThirdPartyAppsId]!,
        common['more_options']!,
      ];
    case ContextMenuLayoutTarget.folder:
      return <_ContextMenuCommandDescriptor>[
        common['open']!,
        _ContextMenuCommandDescriptor(
          id: 'open_in_new_tab',
          label: l10n.openInNewTab,
          icon: PhosphorIconsLight.tabs,
        ),
        _ContextMenuCommandDescriptor(
          id: 'open_in_split_view',
          label: l10n.openInSplitView,
          icon: PhosphorIconsLight.columns,
        ),
        _ContextMenuCommandDescriptor(
          id: 'open_in_new_window',
          label: '${l10n.open} ${l10n.newWindow.toLowerCase()}',
          icon: PhosphorIconsLight.appWindow,
        ),
        _ContextMenuCommandDescriptor(
          id: 'toggle_pin_sidebar',
          label: l10n.pinToSidebar,
          icon: PhosphorIconsLight.pushPin,
        ),
        common['copy']!,
        common['cut']!,
        _ContextMenuCommandDescriptor(
          id: 'paste',
          label: l10n.pasteHere,
          icon: PhosphorIconsLight.clipboard,
        ),
        common['rename']!,
        common['tags']!,
        common['properties']!,
        common[contextMenuThirdPartyAppsId]!,
        common['more_options']!,
      ];
    case ContextMenuLayoutTarget.multiSelection:
      return <_ContextMenuCommandDescriptor>[
        common['copy']!,
        common['cut']!,
        common['tags']!,
        common['delete']!,
        common[contextMenuThirdPartyAppsId]!,
        common['more_options']!,
      ];
  }
}

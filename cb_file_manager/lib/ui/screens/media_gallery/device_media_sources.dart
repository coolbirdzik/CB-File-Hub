import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/device_media_library.dart';
import '../../components/common/library_hub_scaffold.dart';
import '../../components/common/breadcrumb_address_bar.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../tab_manager/core/tab_paths.dart';
import '../folder_list/folder_list_state.dart';
import 'image_viewer_screen.dart';
import 'video_player_full_screen.dart';

typedef DeviceMediaSourcesBuilder =
    Widget Function(
      BuildContext context,
      List<DeviceMediaSource> sources,
      bool loading,
      Future<void> Function() refresh,
    );

/// Supplies device sources to the hub's existing collection layout.
class DeviceMediaSources extends StatefulWidget {
  const DeviceMediaSources({
    super.key,
    required this.type,
    required this.child,
    required this.builder,
    required this.tabId,
    this.enabled = true,
    this.access,
  });

  final RequestType type;
  final String tabId;
  final Widget child;
  final DeviceMediaSourcesBuilder builder;
  final bool enabled;
  final DeviceMediaAccess? access;

  @override
  State<DeviceMediaSources> createState() => _DeviceMediaSourcesState();
}

class _DeviceMediaSourcesState extends State<DeviceMediaSources>
    with WidgetsBindingObserver {
  DeviceMediaLibrary? _library;

  @override
  void initState() {
    super.initState();
    final access = widget.access ?? DeviceMediaAccess();
    if (widget.enabled && access.isSupported) {
      WidgetsBinding.instance.addObserver(this);
      _library = DeviceMediaLibrary(widget.type, access: access);
      unawaited(_library!.refresh(requestPermission: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_library?.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _library?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    if (library == null) return widget.child;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => widget.builder(
        context,
        [
          if (library.sources.isEmpty)
            DeviceMediaSource(library: library, tabId: widget.tabId)
          else
            for (final source in library.sources)
              DeviceMediaSource(
                library: library,
                path: source,
                tabId: widget.tabId,
              ),
        ],
        library.loading,
        library.refresh,
      ),
    );
  }
}

/// A device album participates in the same grid/list as custom sources.
class DeviceMediaSource {
  const DeviceMediaSource({
    required this.library,
    required this.tabId,
    this.path,
  });
  final DeviceMediaLibrary library;
  final String tabId;
  final AssetPathEntity? path;

  String get id => 'device-${library.type.value}-${path?.id ?? "all"}';
  DeviceMediaPath get location => DeviceMediaPath(
    isVideo: library.type == RequestType.video,
    albumId: path?.isAll == true ? null : path?.id,
  );
  String title(BuildContext context) =>
      _sourceTitle(AppLocalizations.of(context)!, library.type, path);

  Widget buildTile(BuildContext context, {ViewMode mode = ViewMode.grid}) =>
      _SourceTile(
        key: ValueKey(id),
        source: path,
        library: library,
        mode: mode,
        onTap: () {
          TabNavigator.updateTabPath(context, tabId, location.path);
          context.read<TabManagerBloc>().add(
            UpdateTabName(tabId, title(context)),
          );
        },
      );
}

String _sourceTitle(
  AppLocalizations l10n,
  RequestType type,
  AssetPathEntity? source,
) => source == null || source.isAll
    ? (type == RequestType.video ? l10n.allVideos : l10n.allImages)
    : source.name;

class _AccessMessage extends StatelessWidget {
  const _AccessMessage({required this.library});
  final DeviceMediaLibrary library;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final limited = library.permission == PermissionState.limited;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            library.error != null
                ? l10n.operationFailed
                : limited
                ? l10n.deviceMediaLimited
                : l10n.deviceMediaPermission,
          ),
          Wrap(
            spacing: 8,
            children: [
              if (limited)
                TextButton(
                  onPressed: () async {
                    await library.access.selectMore(library.type);
                    await library.refresh();
                  },
                  child: Text(l10n.deviceMediaManageAccess),
                )
              else
                TextButton(
                  onPressed: () => library.refresh(requestPermission: true),
                  child: Text(
                    library.error != null ? l10n.retry : l10n.grantPermission,
                  ),
                ),
              TextButton(
                onPressed: library.access.settings,
                child: Text(l10n.openSettings),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatefulWidget {
  const _SourceTile({
    super.key,
    required this.source,
    required this.library,
    required this.onTap,
    required this.mode,
  });
  final ViewMode mode;
  final AssetPathEntity? source;
  final DeviceMediaLibrary library;
  final VoidCallback onTap;

  @override
  State<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends State<_SourceTile> {
  late Future<List<AssetEntity>> _cover = _loadCover();

  Future<List<AssetEntity>> _loadCover() => widget.source == null
      ? Future.value([])
      : widget.library.access.page(widget.source!, 0, 1);

  @override
  void didUpdateWidget(covariant _SourceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) _cover = _loadCover();
  }

  Widget _buildCover(BuildContext context) => FutureBuilder<List<AssetEntity>>(
    future: _cover,
    builder: (context, snapshot) => snapshot.data?.isNotEmpty == true
        ? _AssetThumbnail(
            key: ValueKey(snapshot.data!.first.id),
            asset: snapshot.data!.first,
          )
        : ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              widget.library.type == RequestType.video
                  ? PhosphorIconsLight.filmStrip
                  : PhosphorIconsLight.images,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _sourceTitle(
      AppLocalizations.of(context)!,
      widget.library.type,
      widget.source,
    );
    if (widget.mode != ViewMode.grid) {
      final compact = widget.mode == ViewMode.details;
      final size = compact ? 32.0 : 52.0;
      return InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: compact ? 4 : 8,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: _buildCover(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildCover(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetThumbnail extends StatefulWidget {
  const _AssetThumbnail({super.key, required this.asset});
  final AssetEntity asset;

  @override
  State<_AssetThumbnail> createState() => _AssetThumbnailState();
}

class _AssetThumbnailState extends State<_AssetThumbnail> {
  late final Future<Uint8List?> _data = widget.asset.thumbnailDataWithSize(
    const ThumbnailSize(256, 256),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _data,
    builder: (context, snapshot) => snapshot.data != null
        ? Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          )
        : ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.image_outlined),
          ),
  );
}

class DeviceMediaAlbumScreen extends StatefulWidget {
  const DeviceMediaAlbumScreen({
    super.key,
    required this.tabId,
    required this.location,
    this.access,
  });
  final String tabId;
  final DeviceMediaPath location;
  final DeviceMediaAccess? access;

  @override
  State<DeviceMediaAlbumScreen> createState() => _DeviceMediaAlbumScreenState();
}

class _DeviceMediaAlbumScreenState extends State<DeviceMediaAlbumScreen>
    with WidgetsBindingObserver {
  late final DeviceMediaLibrary _library = DeviceMediaLibrary(
    widget.location.isVideo ? RequestType.video : RequestType.image,
    access: widget.access,
  );
  late final DeviceMediaPager _pager = DeviceMediaPager(_library.access);
  final _scroll = ScrollController();
  bool _opening = false;
  String? _sourceName;

  String get _title {
    final l10n = AppLocalizations.of(context)!;
    if (_sourceName != null) return _sourceName!;
    if (widget.location.albumId != null) {
      return widget.location.isVideo ? l10n.videoLibrary : l10n.albums;
    }
    return widget.location.isVideo ? l10n.allVideos : l10n.allImages;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _library.addListener(_syncSource);
    _scroll.addListener(_loadNearEnd);
    _pager.addListener(_fillViewport);
    unawaited(_library.refresh(requestPermission: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_library.refresh());
  }

  void _fillViewport() {
    if (_pager.loading || _pager.error != null || !_pager.hasMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _loadNearEnd();
    });
  }

  void _syncSource() {
    final library = _library;
    final source = library.loading
        ? null
        : library.sources
              .where(
                (source) => widget.location.albumId == null
                    ? source.isAll
                    : source.id == widget.location.albumId,
              )
              .firstOrNull;
    if (source != null && !source.isAll) _sourceName = source.name;
    if (!library.loading) {
      final tabs = context.read<TabManagerBloc>();
      final tab = tabs.state.tabs
          .where((tab) => tab.id == widget.tabId)
          .firstOrNull;
      if (tab != null &&
          tab.path == widget.location.path &&
          tab.name != _title) {
        tabs.add(UpdateTabName(widget.tabId, _title));
      }
    }
    unawaited(_pager.reset(source));
  }

  void _loadNearEnd() {
    if (_scroll.position.extentAfter < 600 && _pager.error == null) {
      unawaited(_pager.loadMore());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _library.removeListener(_syncSource);
    _library.dispose();
    _pager.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open(AssetEntity asset) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      // Resolve only the selected asset. iOS may materialize an iCloud item.
      final file = await asset.file;
      if (!mounted) return;
      if (!_library.permission.hasAccess ||
          !_pager.assets.any((item) => item.id == asset.id)) {
        return;
      }
      if (file == null) throw StateError('Media is unavailable');
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _library.type == RequestType.video
              ? VideoPlayerFullScreen(file: file)
              : ImageViewerScreen(file: file),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.operationFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) => LibraryHubScaffold(
        tabId: widget.tabId,
        path: widget.location.path,
        parentPath: widget.location.parentPath,
        title: _title,
        icon: widget.location.isVideo
            ? PhosphorIconsLight.filmStrip
            : PhosphorIconsLight.images,
        enablePathEditing: true,
        onRefresh: _library.refresh,
        breadcrumbSegments: [
          BreadcrumbSegment(
            label: widget.location.isVideo
                ? l10n.videoGallery
                : l10n.imageGallery,
            icon: widget.location.isVideo
                ? PhosphorIconsLight.filmStrip
                : PhosphorIconsLight.images,
            onTap: () => TabNavigator.updateTabPath(
              context,
              widget.tabId,
              widget.location.parentPath,
            ),
          ),
          BreadcrumbSegment(label: _title),
        ],
        body: ListenableBuilder(
          listenable: Listenable.merge([_library, _pager]),
          builder: (context, _) {
            final library = _library;
            if (!library.loading &&
                (!library.permission.hasAccess || library.error != null)) {
              return _AccessMessage(library: library);
            }
            return Column(
              children: [
                if (library.permission == PermissionState.limited)
                  _AccessMessage(library: library),
                if (_opening || library.loading || _pager.loading)
                  const LinearProgressIndicator(),
                if (_pager.error != null)
                  TextButton(
                    onPressed: _pager.loadMore,
                    child: Text(l10n.retry),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: library.refresh,
                    child: CustomScrollView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (_pager.assets.isEmpty &&
                            _pager.error == null &&
                            !_pager.loading &&
                            !library.loading)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                library.type == RequestType.video
                                    ? l10n.noVideosFound
                                    : l10n.noImagesFound,
                              ),
                            ),
                          )
                        else
                          SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 160,
                                  crossAxisSpacing: 2,
                                  mainAxisSpacing: 2,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final asset = _pager.assets[index];
                              return Semantics(
                                button: true,
                                label: asset.title ?? '$_title ${index + 1}',
                                child: InkWell(
                                  onTap: _opening ? null : () => _open(asset),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _AssetThumbnail(
                                        key: ValueKey(asset.id),
                                        asset: asset,
                                      ),
                                      if (library.type == RequestType.video)
                                        const Align(
                                          alignment: Alignment.bottomRight,
                                          child: Icon(
                                            Icons.play_circle_fill,
                                            color: Colors.white,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }, childCount: _pager.assets.length),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

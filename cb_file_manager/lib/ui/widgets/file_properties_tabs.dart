import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/helpers/core/file_hash.dart';
import 'package:cb_file_manager/services/file_metadata_service.dart';
import 'package:cb_file_manager/services/windows_shell_properties.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'file_properties_details.dart';

enum FilePropertiesTab { overview, details, media, checksum, tags }

/// Shared, lazy file inspector for the full Properties page and the docked pane.
/// The caller supplies the existing tag editor only on surfaces that need it.
class FilePropertiesTabs extends StatefulWidget {
  const FilePropertiesTabs({
    super.key,
    required this.filePath,
    required this.statFuture,
    this.dense = false,
    this.isDirectory = false,
    this.scrollContent = false,
    this.initialTab = FilePropertiesTab.overview,
    this.tags,
    this.shellReader,
  });

  final String filePath;
  final Future<FileStat> statFuture;
  final bool dense, isDirectory, scrollContent;
  final FilePropertiesTab initialTab;
  final Widget? tags;

  /// Optional reader for deterministic tests; production reads the Windows Shell.
  final Future<String> Function(String path, String property)? shellReader;

  @override
  State<FilePropertiesTabs> createState() => _FilePropertiesTabsState();
}

class _FilePropertiesTabsState extends State<FilePropertiesTabs>
    with TickerProviderStateMixin {
  late TabController _controller;
  late List<FilePropertiesTab> _tabs;
  final _metadata = FileMetadataService();
  bool _tagsVisited = false;
  Future<Map<String, String>>? _system, _media;
  Future<Uint8List?>? _preview;
  Future<int?>? _folderCount;
  Future<String>? _checksum;

  bool get _isImage =>
      !widget.isDirectory && FileTypeUtils.isImageFile(widget.filePath);
  bool get _isVideo =>
      !widget.isDirectory && FileTypeUtils.isVideoFile(widget.filePath);
  bool get _isAudio =>
      !widget.isDirectory && FileTypeUtils.isAudioFile(widget.filePath);
  bool get _hasShell =>
      widget.shellReader != null || WindowsShellProperties.isSupported;
  FilePropertiesTab get _selected => _tabs[_controller.index];

  List<FilePropertiesTab> _availableTabs() => [
    FilePropertiesTab.overview,
    FilePropertiesTab.details,
    if (_isImage || _isVideo || _isAudio) FilePropertiesTab.media,
    if (!widget.isDirectory) FilePropertiesTab.checksum,
    if (widget.tags != null) FilePropertiesTab.tags,
  ];

  @override
  void initState() {
    super.initState();
    _createController(widget.initialTab);
  }

  void _createController(FilePropertiesTab selection) {
    _tabs = _availableTabs();
    final index = _tabs.indexOf(selection);
    _controller = TabController(
      length: _tabs.length,
      initialIndex: index < 0 ? 0 : index,
      vsync: this,
    )..addListener(_tabChanged);
    _tagsVisited |= _selected == FilePropertiesTab.tags;
  }

  void _tabChanged() {
    if (mounted) {
      setState(() => _tagsVisited |= _selected == FilePropertiesTab.tags);
    }
  }

  @override
  void didUpdateWidget(covariant FilePropertiesTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filePath != oldWidget.filePath ||
        widget.statFuture != oldWidget.statFuture) {
      _metadata.invalidate(widget.filePath);
      _system = null;
      _media = null;
      _preview = null;
      _folderCount = null;
      _checksum = null;
    }
    if (!listEquals(_tabs, _availableTabs())) {
      final selected = _selected;
      _controller.removeListener(_tabChanged);
      _controller.dispose();
      _createController(selected);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  (String, IconData) _tabInfo(AppLocalizations l, FilePropertiesTab tab) =>
      switch (tab) {
        FilePropertiesTab.overview => (
          l.propertiesOverview,
          PhosphorIconsLight.file,
        ),
        FilePropertiesTab.details => (
          l.propertiesDetails,
          PhosphorIconsLight.listBullets,
        ),
        FilePropertiesTab.media => (
          l.propertiesMedia,
          _isVideo
              ? PhosphorIconsLight.filmStrip
              : _isAudio
              ? PhosphorIconsLight.musicNotes
              : PhosphorIconsLight.image,
        ),
        FilePropertiesTab.checksum => (
          l.propertiesChecksum,
          PhosphorIconsLight.hash,
        ),
        FilePropertiesTab.tags => (l.tags, PhosphorIconsLight.tag),
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selected != FilePropertiesTab.tags)
          KeyedSubtree(
            key: ValueKey('${widget.filePath}:${_selected.name}'),
            child: switch (_selected) {
              FilePropertiesTab.overview => _overview(),
              FilePropertiesTab.details => _details(l),
              FilePropertiesTab.media => _mediaDetails(l),
              FilePropertiesTab.checksum => _checksumDetails(l),
              FilePropertiesTab.tags => const SizedBox.shrink(),
            },
          ),
        // Once opened, keep the tag editor alive while switching tabs, including
        // draft text and unsaved changes. Do not load it on first open otherwise.
        if (_tagsVisited && widget.tags != null)
          Offstage(
            key: const ValueKey('file-properties-tags-content'),
            offstage: _selected != FilePropertiesTab.tags,
            child: TickerMode(
              enabled: _selected == FilePropertiesTab.tags,
              child: ExcludeFocus(
                excluding: _selected != FilePropertiesTab.tags,
                child: widget.tags!,
              ),
            ),
          ),
      ],
    );
    final content = Padding(
      padding: EdgeInsets.only(top: widget.dense ? CbSpacing.sm : CbSpacing.lg),
      child: body,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.scrollContent ? MainAxisSize.max : MainAxisSize.min,
      children: [
        TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: CbSpacing.sm),
          labelStyle: widget.dense ? CbTypography.labelSm : CbTypography.label,
          unselectedLabelStyle: widget.dense
              ? CbTypography.labelSm
              : CbTypography.label,
          tabs: [
            for (final tab in _tabs)
              Tab(
                key: ValueKey('file-properties-tab-${tab.name}'),
                height: widget.dense ? CbSizes.controlSm : CbSizes.controlMd,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _tabInfo(l, tab).$2,
                      size: widget.dense ? CbSizes.iconXs : CbSizes.iconSm,
                    ),
                    const SizedBox(width: CbSpacing.xs),
                    Text(_tabInfo(l, tab).$1),
                  ],
                ),
              ),
          ],
        ),
        if (widget.scrollContent)
          Expanded(child: SingleChildScrollView(child: content))
        else
          content,
      ],
    );
  }

  Widget _overview() {
    final details = FilePropertiesDetails(
      filePath: widget.filePath,
      statFuture: widget.statFuture,
      dense: true,
      labelWidth: widget.dense ? 88 : 148,
    );
    return widget.dense
        ? details
        : CbSurface(
            radius: CbRadii.md,
            padding: const EdgeInsets.all(CbSpacing.md),
            child: details,
          );
  }

  Widget _rows(Iterable<(String, String)> values) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (label, value) in values)
        FilePropertyRow(
          label: label,
          value: value,
          labelWidth: widget.dense ? 88 : 148,
        ),
    ],
  );

  Widget _section(String title, Widget body) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: CbTypography.headingSm.copyWith(
          color: context.cbColors.textPrimary,
        ),
      ),
      const SizedBox(height: CbSpacing.sm),
      CbSurface(
        radius: CbRadii.md,
        padding: EdgeInsets.all(widget.dense ? CbSpacing.sm : CbSpacing.md),
        child: body,
      ),
    ],
  );

  String _date(DateTime value) => value.toLocal().toString().split('.')[0];

  Widget _details(AppLocalizations l) => FutureBuilder<FileStat>(
    future: widget.statFuture,
    builder: (context, snapshot) {
      if (!snapshot.hasData &&
          snapshot.connectionState != ConnectionState.done) {
        return const CbLoadingText();
      }
      final stat = snapshot.data;
      if (stat == null || stat.type == FileSystemEntityType.notFound) {
        return Text(l.operationFailed);
      }
      final isDir = stat.type == FileSystemEntityType.directory;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(
            l.propertiesFileSystem,
            _rows([
              (l.columnParentFolder, path.dirname(widget.filePath)),
              if (!isDir && path.extension(widget.filePath).isNotEmpty)
                (l.columnExtension, path.extension(widget.filePath)),
              if (!isDir) (l.propertiesExactSize, '${stat.size} B'),
              (l.fileModified, _date(stat.modified)),
              (l.fileAccessed, _date(stat.accessed)),
              (l.propertiesMetadataChanged, _date(stat.changed)),
              if (!Platform.isWindows) (l.columnPermissions, stat.modeString()),
            ]),
          ),
          if (isDir) ...[
            const SizedBox(height: CbSpacing.lg),
            _section(
              l.columnItemCount,
              FutureBuilder<int?>(
                future: _folderCount ??= _metadata.getFolderItemCount(
                  widget.filePath,
                ),
                builder: (context, snapshot) =>
                    snapshot.connectionState != ConnectionState.done
                    ? const CbLoadingText()
                    : Text(
                        snapshot.data == null
                            ? l.unknown
                            : l.itemCountFormat(snapshot.data!),
                        style: CbTypography.body,
                      ),
              ),
            ),
          ],
          if (_hasShell) ...[
            const SizedBox(height: CbSpacing.lg),
            _section(
              l.columnChooserSystemGroup,
              FutureBuilder<Map<String, String>>(
                future: _system ??= _loadSystem(isDir),
                builder: (context, snapshot) => _renderMetadata(l, snapshot),
              ),
            ),
          ],
        ],
      );
    },
  );

  Future<Map<String, String>> _readShell(
    String filePath,
    List<String> keys, {
    Map<String, String> aliases = const {},
  }) async {
    final read = widget.shellReader ?? WindowsShellProperties.instance.get;
    // Windows shell parsing requires a native path, even when callers use
    // forward slashes in Dart File paths.
    final shellPath = widget.shellReader == null
        ? path.normalize(filePath)
        : filePath;
    final values = await Future.wait(
      keys.map((key) async {
        try {
          return (key, await read(shellPath, aliases[key] ?? key));
        } catch (_) {
          return (key, '');
        }
      }),
    );
    return {
      for (final (key, value) in values)
        if (value.trim().isNotEmpty) key: value,
    };
  }

  Future<Map<String, String>> _loadSystem(bool isDir) => _readShell(
    widget.filePath,
    [
      'dateCreated',
      'attributes',
      'owner',
      if (!isDir) ...[
        'title',
        'authors',
        'comments',
        'pageCount',
        'company',
        'fileDescription',
        'fileVersion',
        'productName',
      ],
    ],
    aliases: {
      'dateCreated': ShellProperty.system('System.DateCreated'),
      'attributes': ShellProperty.system('System.FileAttributes'),
    },
  );

  String _metadataLabel(AppLocalizations l, String key) => switch (key) {
    'dateCreated' => l.fileCreated,
    'attributes' => l.columnAttributes,
    'dimensions' => l.columnDimensions,
    'duration' => l.duration,
    'aspectRatio' => l.edAspectRatio,
    _ => l.shellColumn(key),
  };

  Widget _renderMetadata(
    AppLocalizations l,
    AsyncSnapshot<Map<String, String>> snapshot,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const CbLoadingText();
    }
    final values = snapshot.data;
    if (values == null || values.isEmpty) {
      return Text(
        l.noDataFound,
        style: CbTypography.bodySm.copyWith(
          color: context.cbColors.textSecondary,
        ),
      );
    }
    return _rows(
      values.entries.map(
        (entry) => (_metadataLabel(l, entry.key), entry.value),
      ),
    );
  }

  Future<Map<String, String>> _loadMedia() async {
    final filePath = widget.filePath;
    final isImage = _isImage, isVideo = _isVideo, isAudio = _isAudio;
    final result = <String, String>{};
    if (isImage) {
      final dimensions = await _metadata.getImageDimensions(filePath);
      if (dimensions != null) {
        result['dimensions'] = '${dimensions.width} × ${dimensions.height}';
        final divisor = dimensions.width.gcd(dimensions.height);
        if (divisor > 0) {
          result['aspectRatio'] =
              '${dimensions.width ~/ divisor}:${dimensions.height ~/ divisor}';
        }
      }
    } else if (isVideo || isAudio) {
      final duration = await _metadata.getMediaDuration(filePath);
      if (duration != null) {
        result['duration'] = FileMetadataService.formatDuration(duration);
      }
    }
    if (_hasShell) {
      final shell = await _readShell(filePath, [
        if (isImage) ...['dimensions', 'dateTaken', 'cameraModel', 'rating'],
        if (isVideo) ...['dimensions', 'duration', 'frameRate', 'bitRate'],
        if (isAudio) ...[
          'duration',
          'bitRate',
          'artist',
          'album',
          'genre',
          'year',
        ],
        'title',
      ]);
      for (final entry in shell.entries) {
        result.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return result;
  }

  Future<Uint8List?> _loadPreview(String filePath) async {
    // Use an encoded thumbnail rather than a FileImage backed by an open file
    // mapping. On Windows that would prevent deleting/renaming the source.
    try {
      final thumbnail = await NativeImage.thumbnail(
        path: filePath,
        width: 640,
        height: 480,
        fit: NativeThumbnailFit.shrinkOnly,
      );
      if (thumbnail != null) return thumbnail.bytes;
    } catch (_) {
      // Fall back for builds without the optional native helper.
    }
    try {
      final file = File(filePath);
      if (await file.length() <= 16 * 1024 * 1024) {
        return await file.readAsBytes();
      }
    } catch (_) {
      // Metadata remains available even when the preview cannot be decoded.
    }
    return null;
  }

  Widget _mediaDetails(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_isImage) ...[
        CbSurface(
          radius: CbRadii.md,
          clip: true,
          child: SizedBox(
            height: widget.dense ? 124 : 220,
            child: FutureBuilder<Uint8List?>(
              future: _preview ??= _loadPreview(widget.filePath),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CbLoadingText());
                }
                final bytes = snapshot.data;
                if (bytes == null) {
                  return Center(child: Text(l.previewUnavailable));
                }
                return Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  cacheWidth: 640,
                  errorBuilder: (context, _, _) =>
                      Center(child: Text(l.errorLoadingImage)),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: CbSpacing.lg),
      ],
      _section(
        l.propertiesMedia,
        FutureBuilder<Map<String, String>>(
          future: _media ??= _loadMedia(),
          builder: (context, snapshot) => _renderMetadata(l, snapshot),
        ),
      ),
    ],
  );

  Future<String> _calculateChecksum(String filePath) async {
    final file = File(filePath);
    final before = await file.stat();
    final digest = await sha256OfFile(filePath);
    final after = await file.stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed) {
      throw const _FileChangedDuringHash();
    }
    return digest.toString();
  }

  Widget _checksumDetails(AppLocalizations l) => _section(
    'SHA-256',
    FutureBuilder<String>(
      future: _checksum,
      builder: (context, snapshot) {
        final busy = snapshot.connectionState == ConnectionState.waiting;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.propertiesChecksumHint,
              style: CbTypography.bodySm.copyWith(
                color: context.cbColors.textSecondary,
              ),
            ),
            const SizedBox(height: CbSpacing.md),
            if (snapshot.hasData && !busy) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      snapshot.data!,
                      style: CbTypography.mono,
                    ),
                  ),
                  CbButton.icon(
                    key: const ValueKey('file-properties-copy-checksum'),
                    icon: PhosphorIconsLight.copy,
                    size: CbButtonSize.xs,
                    tooltip: l.copyValue,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: snapshot.data!),
                      );
                      if (context.mounted) {
                        AppToast.info(context, l.propertiesChecksumCopied);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: CbSpacing.md),
            ],
            if (snapshot.hasError && !busy) ...[
              Text(
                snapshot.error is _FileChangedDuringHash
                    ? l.propertiesChecksumChanged
                    : l.operationFailed,
                style: CbTypography.bodySm.copyWith(
                  color: context.cbColors.status.danger,
                ),
              ),
              const SizedBox(height: CbSpacing.sm),
            ],
            CbButton(
              key: const ValueKey('file-properties-calculate-checksum'),
              label: l.propertiesCalculateChecksum,
              icon: PhosphorIconsLight.hash,
              variant: CbButtonVariant.secondary,
              size: widget.dense ? CbButtonSize.sm : CbButtonSize.md,
              loading: busy,
              onPressed: busy
                  ? null
                  : () {
                      final calculation = _calculateChecksum(widget.filePath);
                      setState(() {
                        _checksum = calculation;
                      });
                    },
            ),
          ],
        );
      },
    ),
  );
}

class _FileChangedDuringHash implements Exception {
  const _FileChangedDuringHash();
}

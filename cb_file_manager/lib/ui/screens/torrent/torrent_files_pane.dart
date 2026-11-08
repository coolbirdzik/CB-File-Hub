import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/torrent/torrent_entry.dart';
import '../../../services/torrent/torrent_metainfo.dart';
import '../../../services/torrent/torrent_service.dart';

/// Bottom pane listing the payload files of the selected torrent. Magnets
/// without metainfo offer to fetch it (name and file list only).
class TorrentFilesPane extends StatefulWidget {
  final TorrentService service;

  /// The single selected entry, or null for no or several selected entries.
  final TorrentEntry? entry;
  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onClose;
  final String Function(int bytes) formatSize;
  final bool canFetchMetadata;

  const TorrentFilesPane({
    super.key,
    required this.service,
    required this.entry,
    required this.height,
    required this.onResize,
    required this.onResizeEnd,
    required this.onClose,
    required this.formatSize,
    required this.canFetchMetadata,
  });

  @override
  State<TorrentFilesPane> createState() => _TorrentFilesPaneState();
}

class _TorrentFilesPaneState extends State<TorrentFilesPane> {
  String? _key;
  Future<List<TorrentFileItem>>? _files;
  final _scroll = ScrollController();

  AppLocalizations get l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(TorrentFilesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    final entry = widget.entry;
    // Metainfo is immutable for a hash; reread only when the archive changes.
    final key = entry == null ? null : '${entry.hash}|${entry.torrentPath}';
    if (key == _key) return;
    _key = key;
    _files = entry == null || entry.torrentPath.isEmpty
        ? null
        : widget.service.files(entry);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.cbColors;
    return SizedBox(
      key: const ValueKey('torrent-files-pane'),
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) =>
                  widget.onResize(-details.delta.dy),
              onVerticalDragEnd: (_) => widget.onResizeEnd(),
              child: SizedBox(
                height: 6,
                child: Center(
                  child: Divider(height: 1, color: colors.strokeSubtle),
                ),
              ),
            ),
          ),
          _header(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() => FutureBuilder<List<TorrentFileItem>>(
    future: _files,
    builder: (context, snapshot) {
      final files = snapshot.data;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: CbSpacing.md),
        child: Row(
          spacing: CbSpacing.sm,
          children: [
            Icon(
              PhosphorIconsLight.files,
              size: 16,
              color: context.cbColors.icon,
            ),
            Text(l.torrentFiles, style: CbTypography.headingSm),
            if (files != null)
              Flexible(
                child: Text(
                  l.torrentFilesSummary(
                    files.length,
                    widget.formatSize(
                      files.fold<int>(0, (sum, file) => sum + file.length),
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CbTypography.bodySm.copyWith(
                    color: context.cbColors.textSecondary,
                  ),
                ),
              ),
            const Spacer(),
            CbButton.icon(
              key: const ValueKey('torrent-files-pane-close'),
              icon: PhosphorIconsLight.x,
              tooltip: l.close,
              size: CbButtonSize.sm,
              onPressed: widget.onClose,
            ),
          ],
        ),
      );
    },
  );

  Widget _message(
    String text, {
    List<Widget> actions = const [],
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.all(CbSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: CbSpacing.sm,
      children: [
        SelectableText(
          text,
          style: CbTypography.body.copyWith(
            color: color ?? context.cbColors.textSecondary,
          ),
        ),
        if (actions.isNotEmpty)
          Wrap(
            spacing: CbSpacing.sm,
            runSpacing: CbSpacing.sm,
            children: actions,
          ),
      ],
    ),
  );

  Widget _body() {
    final entry = widget.entry;
    if (entry == null) return _message(l.torrentFilesSelectHint);
    if (entry.torrentPath.isEmpty) return _magnetBody(entry);
    return FutureBuilder<List<TorrentFileItem>>(
      future: _files,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message(
            '${snapshot.error}',
            color: context.cbColors.status.danger,
          );
        }
        final files = snapshot.data;
        if (files == null) return _message(l.torrentFilesLoading);
        return Scrollbar(
          controller: _scroll,
          child: ListView.builder(
            key: const ValueKey('torrent-files-list'),
            controller: _scroll,
            itemExtent: 28,
            itemCount: files.length,
            itemBuilder: (context, index) => _row(files[index]),
          ),
        );
      },
    );
  }

  Widget _magnetBody(TorrentEntry entry) {
    final service = widget.service;
    if (service.isFetchingMetadata(entry.hash)) {
      return _message(
        l.torrentFetchingMetadata,
        actions: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          CbButton(
            key: const ValueKey('torrent-cancel-metadata'),
            label: l.cancel,
            size: CbButtonSize.sm,
            onPressed: () => unawaited(service.cancelMetadata(entry.hash)),
          ),
        ],
      );
    }
    final error = service.metadataError(entry.hash);
    final fetch = widget.canFetchMetadata
        ? CbButton(
            key: const ValueKey('torrent-fetch-metadata'),
            label: error == null ? l.torrentFetchMetadata : l.retry,
            icon: PhosphorIconsLight.downloadSimple,
            size: CbButtonSize.sm,
            onPressed: () => unawaited(service.fetchMetadata(entry)),
          )
        : null;
    return _message(
      error == null
          ? l.torrentMetadataMissing
          : '${l.torrentMetadataFailed}: $error',
      color: error == null ? null : context.cbColors.status.danger,
      actions: [?fetch],
    );
  }

  Widget _row(TorrentFileItem file) {
    final colors = context.cbColors;
    final slash = file.path.lastIndexOf('/');
    final directory = slash < 0 ? '' : file.path.substring(0, slash + 1);
    final name = file.path.substring(slash + 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CbSpacing.md),
      child: Row(
        spacing: CbSpacing.sm,
        children: [
          Icon(PhosphorIconsLight.file, size: 16, color: colors.iconSubtle),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (directory.isNotEmpty)
                    TextSpan(
                      text: directory,
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  TextSpan(text: name),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CbTypography.body,
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              widget.formatSize(file.length),
              textAlign: TextAlign.end,
              style: CbTypography.bodySm.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

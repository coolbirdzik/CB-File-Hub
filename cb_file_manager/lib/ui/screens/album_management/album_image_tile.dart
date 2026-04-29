import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as pathlib;

import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';

class AlbumImageTile extends StatefulWidget {
  final File file;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isDesktopMode;
  final VoidCallback onOpen;
  final void Function({bool shiftSelect, bool ctrlSelect}) onSelect;

  const AlbumImageTile({
    Key? key,
    required this.file,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isDesktopMode,
    required this.onOpen,
    required this.onSelect,
  }) : super(key: key);

  @override
  State<AlbumImageTile> createState() => _AlbumImageTileState();
}

class _AlbumImageTileState extends State<AlbumImageTile> {
  bool _hovering = false;

  // Video thumbnail state — lazy loaded once per tile lifecycle.
  String? _videoThumbPath;
  bool _videoThumbRequested = false;

  bool get _isImage => FileTypeUtils.isImageFile(widget.file.path);
  bool get _isVideo => FileTypeUtils.isVideoFile(widget.file.path);

  @override
  void initState() {
    super.initState();
    if (_isVideo) _loadVideoThumbnail();
  }

  Future<void> _loadVideoThumbnail() async {
    if (_videoThumbRequested) return;
    _videoThumbRequested = true;

    // Wait until the listing gate is open so we don't compete with file
    // list loading for I/O / CPU.
    if (!ThumbnailLoader.isListingReady) {
      ThumbnailLoader.runAfterReady(() {
        if (mounted) {
          _videoThumbRequested = false; // allow retry
          _loadVideoThumbnail();
        }
      });
      return;
    }

    try {
      final path = await VideoThumbnailHelper.getThumbnail(
        widget.file.path,
        isPriority: false,
        forceRegenerate: false,
      );
      if (mounted && path != null) {
        setState(() => _videoThumbPath = path);
      }
    } catch (_) {}
  }

  void _handleTap() {
    final keyboard = HardwareKeyboard.instance;
    final shift = keyboard.isShiftPressed;
    final ctrl = keyboard.isControlPressed || keyboard.isMetaPressed;

    if (widget.isDesktopMode || widget.isSelectionMode) {
      widget.onSelect(shiftSelect: shift, ctrlSelect: ctrl);
    } else {
      widget.onOpen();
    }
  }

  void _handleDoubleTap() {
    if (widget.isDesktopMode) widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = pathlib.basename(widget.file.path);
    final overlayColor = widget.isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.22)
        : (_hovering && widget.isDesktopMode
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent);

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (widget.isDesktopMode && !_hovering) {
            setState(() => _hovering = true);
          }
        },
        onExit: (_) {
          if (widget.isDesktopMode && _hovering) {
            setState(() => _hovering = false);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onDoubleTap: _handleDoubleTap,
          onLongPress: () => widget.onSelect(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _buildMediaContent(theme),
                    ),
                    if (overlayColor != Colors.transparent)
                      IgnorePointer(child: Container(color: overlayColor)),
                    if (widget.isSelected)
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            PhosphorIconsLight.checkCircle,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaContent(ThemeData theme) {
    if (_isImage) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.of(context).devicePixelRatio;
          final cacheWidth =
              (constraints.maxWidth * dpr).clamp(96.0, 320.0).round();
          return Image.file(
            widget.file,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            gaplessPlayback: false,
            errorBuilder: (_, __, ___) => _fallbackIcon(theme),
          );
        },
      );
    }
    if (_isVideo) {
      if (_videoThumbPath != null) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(_videoThumbPath!),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) =>
                  _fallbackIcon(theme, icon: PhosphorIconsLight.filmSlate),
            ),
            // Play icon overlay
            Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(PhosphorIconsLight.play, color: Colors.white, size: 22),
              ),
            ),
          ],
        );
      }
      // Thumbnail not yet ready — show video icon placeholder.
      return _fallbackIcon(theme, icon: PhosphorIconsLight.filmSlate);
    }
    return _fallbackIcon(theme);
  }

  Widget _fallbackIcon(ThemeData theme, {IconData? icon}) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Icon(
        icon ?? PhosphorIconsLight.image,
        size: 42,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

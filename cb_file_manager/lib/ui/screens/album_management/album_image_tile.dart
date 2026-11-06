import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as pathlib;

import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_image.dart';

class AlbumImageTile extends StatefulWidget {
  final File file;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isDesktopMode;
  final VoidCallback onOpen;
  final void Function({bool shiftSelect, bool ctrlSelect}) onSelect;
  final ValueChanged<TapUpDetails> onSecondaryTapUp;

  const AlbumImageTile({
    super.key,
    required this.file,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isDesktopMode,
    required this.onOpen,
    required this.onSelect,
    required this.onSecondaryTapUp,
  });

  @override
  State<AlbumImageTile> createState() => _AlbumImageTileState();
}

class _AlbumImageTileState extends State<AlbumImageTile> {
  bool _hovering = false;

  bool get _isImage => FileTypeUtils.isImageFile(widget.file.path);
  bool get _isVideo => FileTypeUtils.isVideoFile(widget.file.path);

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
          onSecondaryTapUp: widget.onSecondaryTapUp,
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
    if (!_isImage && !_isVideo) return _fallbackIcon(theme);
    if (_isImage) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cacheWidth =
              (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .clamp(96.0, 320.0)
                  .round();
          return ThumbnailImage(
            image: ResizeImage(FileImage(widget.file), width: cacheWidth),
            width: double.infinity,
            height: double.infinity,
          );
        },
      );
    }
    return ThumbnailLoader(
      key: ValueKey(widget.file.path),
      filePath: widget.file.path,
      isImage: _isImage,
      isVideo: _isVideo,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
    );
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

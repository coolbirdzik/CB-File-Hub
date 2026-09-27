import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';

/// Shared timing for the image viewer's chrome, so every control moves with
/// the same rhythm.
class ViewerMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 380);
  static const Curve curve = Curves.easeOutCubic;

  const ViewerMotion._();
}

/// Frosted dark surface used by the viewer's floating controls.
class ViewerGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  const ViewerGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF141417).withValues(alpha: 0.72),
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Soft-rounded icon button with hover, press and active feedback.
class ViewerIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool filled;
  final double size;
  final double iconSize;
  final Color? color;

  const ViewerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.filled = false,
    this.size = 40,
    this.iconSize = 20,
    this.color,
  });

  @override
  State<ViewerIconButton> createState() => _ViewerIconButtonState();
}

class _ViewerIconButtonState extends State<ViewerIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  Color get _background {
    if (!_enabled) {
      return widget.filled
          ? Colors.black.withValues(alpha: 0.25)
          : Colors.transparent;
    }
    if (widget.active) return Colors.white.withValues(alpha: 0.22);
    if (_hovered) {
      return widget.filled
          ? Colors.black.withValues(alpha: 0.6)
          : Colors.white.withValues(alpha: 0.12);
    }
    return widget.filled
        ? Colors.black.withValues(alpha: 0.38)
        : Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _enabled
        ? (widget.color ?? Colors.white)
        : Colors.white.withValues(alpha: 0.3);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.86 : (_hovered && widget.filled ? 1.08 : 1),
            duration: ViewerMotion.fast,
            curve: ViewerMotion.curve,
            child: AnimatedContainer(
              duration: ViewerMotion.fast,
              curve: ViewerMotion.curve,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                // A soft rounded square, not a circle, matching the rest of
                // the app's buttons; scales with the button's own size.
                borderRadius: BorderRadius.circular(widget.size * 0.28),
                color: _background,
                border: widget.filled
                    ? Border.all(color: Colors.white.withValues(alpha: 0.1))
                    : null,
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: ViewerMotion.medium,
                switchInCurve: ViewerMotion.curve,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Icon(
                  widget.icon,
                  key: ValueKey<IconData>(widget.icon),
                  size: widget.iconSize,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin vertical rule separating groups of buttons in a toolbar.
class ViewerToolbarDivider extends StatelessWidget {
  const ViewerToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withValues(alpha: 0.14),
    );
  }
}

/// Fades and slides a piece of chrome in and out of view.
class ViewerChromeReveal extends StatelessWidget {
  final bool visible;
  final Offset hiddenOffset;
  final Duration delay;
  final Widget child;

  const ViewerChromeReveal({
    super.key,
    required this.visible,
    required this.hiddenOffset,
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : hiddenOffset,
        duration: ViewerMotion.slow + delay,
        curve: visible ? ViewerMotion.curve : Curves.easeInCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: ViewerMotion.medium + delay,
          curve: ViewerMotion.curve,
          child: child,
        ),
      ),
    );
  }
}

/// Properties of the image on screen, shown in a floating card.
class ImageInfoPanel extends StatefulWidget {
  final File file;
  final bool active;
  final VoidCallback onClose;
  final VoidCallback onCopyPath;

  const ImageInfoPanel({
    super.key,
    required this.file,
    required this.active,
    required this.onClose,
    required this.onCopyPath,
  });

  @override
  State<ImageInfoPanel> createState() => _ImageInfoPanelState();
}

class _ImageInfoPanelState extends State<ImageInfoPanel> {
  FileStat? _stat;
  Size? _dimensions;
  String? _loadedPath;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(ImageInfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadIfNeeded();
  }

  // Only read the file while the panel is open, so paging through images
  // with the panel closed costs nothing.
  Future<void> _loadIfNeeded() async {
    final path = widget.file.path;
    if (!widget.active || _loadedPath == path) return;
    _loadedPath = path;
    setState(() {
      _stat = null;
      _dimensions = null;
    });

    FileStat? stat;
    Size? dimensions;
    try {
      stat = await widget.file.stat();
    } catch (_) {}
    try {
      // Reads only the header: no full decode of the image.
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      dimensions = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
    } catch (_) {}

    if (!mounted || _loadedPath != path) return;
    setState(() {
      _stat = stat;
      _dimensions = dimensions;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final file = widget.file;
    final stat = _stat;
    final dimensions = _dimensions;
    final extension = pathlib.extension(file.path).replaceFirst('.', '');

    return ViewerGlass(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.properties,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ViewerIconButton(
                icon: PhosphorIconsLight.x,
                tooltip: l10n.close,
                size: 34,
                iconSize: 18,
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 10),
              child: AnimatedSwitcher(
                duration: ViewerMotion.medium,
                child: Column(
                  key: ValueKey<String>(
                    '${file.path}-${stat != null}-${dimensions != null}',
                  ),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      icon: PhosphorIconsLight.fileImage,
                      label: l10n.fileName,
                      value: pathlib.basename(file.path),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsLight.frameCorners,
                      label: l10n.resolution,
                      value: dimensions == null
                          ? '—'
                          : '${dimensions.width.toInt()} × '
                                '${dimensions.height.toInt()} px',
                    ),
                    _InfoRow(
                      icon: PhosphorIconsLight.hardDrives,
                      label: l10n.fileSize,
                      value: stat == null ? '—' : _formatFileSize(stat.size),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsLight.tag,
                      label: l10n.fileType,
                      value: extension.isEmpty ? '—' : extension.toUpperCase(),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsLight.calendarBlank,
                      label: l10n.fileModified,
                      value: stat == null ? '—' : _formatDate(stat.modified),
                    ),
                    _InfoRow(
                      icon: PhosphorIconsLight.folder,
                      label: l10n.fileLocation,
                      value: pathlib.dirname(file.path),
                      trailing: ViewerIconButton(
                        icon: PhosphorIconsLight.copy,
                        tooltip: l10n.filePath,
                        size: 30,
                        iconSize: 16,
                        onPressed: widget.onCopyPath,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = min((log(bytes) / log(1024)).floor(), suffixes.length - 1);
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

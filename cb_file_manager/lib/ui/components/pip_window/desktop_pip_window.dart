import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Reusable Windows/Mac/Linux window caption buttons: Minimize, Maximize/Restore, Close
/// Matches styling used in the tabbed UI's title bar.
class WindowCaptionButtons extends StatelessWidget {
  final ThemeData? theme;
  final bool visibleOnDesktopOnly;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onClose;

  const WindowCaptionButtons({
    Key? key,
    this.theme,
    this.visibleOnDesktopOnly = true,
    this.padding,
    this.onClose,
  }) : super(key: key);

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (visibleOnDesktopOnly && !_isDesktop) {
      return const SizedBox.shrink();
    }

    final ThemeData effectiveTheme = theme ?? Theme.of(context);

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          _CaptionButton(
            icon: PhosphorIconsLight.minus,
            tooltip: 'Minimize',
            theme: effectiveTheme,
            onPressed: () async {
              try {
                await windowManager.minimize();
              } catch (_) {}
            },
          ),
          _CaptionButton(
            icon: PhosphorIconsLight.square, // Will be replaced dynamically
            tooltip: 'Maximize',
            theme: effectiveTheme,
            listensMaximize: true,
            onPressed: () async {
              try {
                final isMax = await windowManager.isMaximized();
                if (isMax) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              } catch (_) {}
            },
          ),
          _CaptionButton(
            icon: PhosphorIconsLight.x,
            tooltip: 'Close',
            isCloseButton: true,
            theme: effectiveTheme,
            onPressed: () async {
              try {
                if (onClose != null) {
                  onClose!();
                } else {
                  await windowManager.close();
                }
              } catch (_) {}
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isCloseButton;
  final ThemeData theme;
  final bool listensMaximize;

  const _CaptionButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
    this.isCloseButton = false,
    this.listensMaximize = false,
  }) : super(key: key);

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _isHovered = false;
  IconData? _dynamicIcon;
  String? _dynamicTooltip;
  _WindowStateListener? _listener;

  @override
  void initState() {
    super.initState();
    if (widget.listensMaximize) {
      _listener = _WindowStateListener(onChange: _updateMaxVisuals);
      windowManager.addListener(_listener!);
      _updateMaxVisuals();
    }
  }

  @override
  void dispose() {
    if (_listener != null) {
      windowManager.removeListener(_listener!);
    }
    super.dispose();
  }

  Future<void> _updateMaxVisuals() async {
    try {
      final isMax = await windowManager.isMaximized();
      if (!mounted) return;
      setState(() {
        _dynamicIcon = isMax
            ? PhosphorIconsLight.cornersIn
            : PhosphorIconsLight.cornersOut;
        _dynamicTooltip = isMax ? 'Restore' : 'Maximize';
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final baseIconColor = widget.theme.colorScheme.onSurface
        .withValues(alpha: isDark ? 0.7 : 0.54);
    final hoverBg = widget.isCloseButton
        ? Colors.red.withValues(alpha: 0.9)
        : (isDark
            ? widget.theme.colorScheme.onSurface.withValues(alpha: 0.10)
            : widget.theme.colorScheme.onSurface.withValues(alpha: 0.08));
    final hoverIconColor = widget.isCloseButton
        ? Colors.white
        : widget.theme.colorScheme.onSurface;

    return Tooltip(
      message: _dynamicTooltip ?? widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onPressed();
            },
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            borderRadius: BorderRadius.circular(16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _isHovered ? hoverBg : Colors.transparent,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Icon(
                _dynamicIcon ?? widget.icon,
                size: 18,
                color: _isHovered ? hoverIconColor : baseIconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowStateListener extends WindowListener {
  final VoidCallback onChange;
  _WindowStateListener({required this.onChange});

  @override
  void onWindowMaximize() => onChange();
  @override
  void onWindowUnmaximize() => onChange();
  @override
  void onWindowRestore() => onChange();
}

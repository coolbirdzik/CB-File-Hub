import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../utils/fluent_background.dart';
import '../../common/window_caption_buttons.dart';
import 'package:window_manager/window_manager.dart';

/// Custom app bar for video player with window controls and glass blur effect
class VideoPlayerAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onClose;
  final bool showWindowControls;
  final double blurAmount;
  final double opacity;

  const VideoPlayerAppBar({
    Key? key,
    required this.title,
    this.actions,
    this.onClose,
    this.showWindowControls = true,
    this.blurAmount = 12.0,
    this.opacity = 0.6,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<VideoPlayerAppBar> createState() => _VideoPlayerAppBarState();
}

class _VideoPlayerAppBarState extends State<VideoPlayerAppBar> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  VoidCallback get _onCloseDefault => () {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          exit(0);
        }
      };

  @override
  Widget build(BuildContext context) {
    final onClose = widget.onClose ?? _onCloseDefault;
    return FluentBackground.appBar(
      context: context,
      title: _buildTitle(),
      leading: _isDesktopPlatform
          ? IconButton(
              icon:
                  const Icon(PhosphorIconsLight.arrowLeft, color: Colors.white),
              onPressed: onClose,
            )
          : null,
      actions: _buildActions(onClose),
      blurAmount: widget.blurAmount,
      opacity: widget.opacity,
    );
  }

  Widget _buildTitle() {
    final content = Row(
      children: [
        const Icon(PhosphorIconsLight.videoCamera,
            color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    // Allow dragging the window by the title area on desktop
    if (_isDesktopPlatform) {
      return DragToMoveArea(child: content);
    }
    return content;
  }

  List<Widget> _buildActions(VoidCallback onClose) {
    final List<Widget> actions = [];

    // Add custom actions if provided
    if (widget.actions != null) {
      actions.addAll(widget.actions!);
    }

    // Add window controls for desktop platforms
    if (widget.showWindowControls && _isDesktopPlatform) {
      actions.add(WindowCaptionButtons(
        theme: Theme.of(context),
        onClose: onClose,
      ));
    }

    return actions;
  }
}

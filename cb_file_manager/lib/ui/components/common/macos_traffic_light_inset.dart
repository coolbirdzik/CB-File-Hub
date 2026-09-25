import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Reserves room for the macOS traffic lights at the leading edge of a custom
/// title bar row, and moves the native buttons so they sit vertically centred
/// in a bar of [barHeight] (see macos/Runner/MainFlutterWindow.swift).
///
/// The space doubles as a window drag handle. It collapses in full screen,
/// where macOS hides the buttons. Renders nothing on other platforms.
class MacosTrafficLightInset extends StatefulWidget {
  /// Height of the title bar row this inset lives in.
  final double barHeight;

  /// Distance from the window's left edge to the close button.
  final double buttonsLeading;

  /// Space kept between the zoom button and the row's first widget.
  final double gap;

  const MacosTrafficLightInset({
    super.key,
    required this.barHeight,
    this.buttonsLeading = 14,
    this.gap = 8,
  });

  static const MethodChannel _channel = MethodChannel(
    'cb_file_manager/macos_window',
  );

  @override
  State<MacosTrafficLightInset> createState() => _MacosTrafficLightInsetState();
}

class _MacosTrafficLightInsetState extends State<MacosTrafficLightInset>
    with WindowListener {
  bool _isFullScreen = false;

  /// Right edge of the zoom button in window coordinates, as the runner
  /// reports it; button size and spacing differ between macOS releases.
  double? _buttonsEnd;
  double _reservedWidth = 76;

  @override
  void initState() {
    super.initState();
    if (!Platform.isMacOS) return;
    windowManager.addListener(this);
    _applyLayout();
    windowManager
        .isFullScreen()
        .then((value) {
          if (mounted && value != _isFullScreen) {
            setState(() => _isFullScreen = value);
          }
        })
        .catchError((_) {});
  }

  @override
  void didUpdateWidget(MacosTrafficLightInset oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barHeight != widget.barHeight ||
        oldWidget.buttonsLeading != widget.buttonsLeading) {
      _applyLayout();
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _applyLayout() async {
    try {
      final end = await MacosTrafficLightInset._channel.invokeMethod<double>(
        'setTrafficLightLayout',
        <String, double>{
          'barHeight': widget.barHeight,
          'leading': widget.buttonsLeading,
        },
      );
      if (end == null || !mounted) return;
      _buttonsEnd = end;
      _updateReservedWidth();
    } catch (_) {}
  }

  /// The inset need not start at the window edge (the row may be padded), so
  /// reserve only what is left of the buttons past its own left edge.
  void _updateReservedWidth() {
    final end = _buttonsEnd;
    if (end == null || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      // The reply can beat the first layout; measure once it has happened.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _updateReservedWidth(),
      );
      return;
    }
    final left = box.localToGlobal(Offset.zero).dx;
    final width = (end + widget.gap - left).clamp(0.0, double.infinity);
    if (width != _reservedWidth) setState(() => _reservedWidth = width);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
    _applyLayout();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS || _isFullScreen) return const SizedBox.shrink();
    return DragToMoveArea(
      child: SizedBox(width: _reservedWidth, height: double.infinity),
    );
  }
}

/// Keeps the traffic lights clear above a panel that reaches the top of the
/// window, such as the overlay drawer: a drag strip as tall as the title bar
/// row. Collapses in full screen; renders nothing on other platforms.
class MacosTrafficLightTopInset extends StatefulWidget {
  final double height;

  const MacosTrafficLightTopInset({super.key, required this.height});

  @override
  State<MacosTrafficLightTopInset> createState() =>
      _MacosTrafficLightTopInsetState();
}

class _MacosTrafficLightTopInsetState extends State<MacosTrafficLightTopInset>
    with WindowListener {
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isMacOS) return;
    windowManager.addListener(this);
    windowManager
        .isFullScreen()
        .then((value) {
          if (mounted && value != _isFullScreen) {
            setState(() => _isFullScreen = value);
          }
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    if (Platform.isMacOS) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS || _isFullScreen) return const SizedBox.shrink();
    return DragToMoveArea(
      child: SizedBox(width: double.infinity, height: widget.height),
    );
  }
}

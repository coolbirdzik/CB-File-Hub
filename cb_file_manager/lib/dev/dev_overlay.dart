import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dev_tools_panel.dart';

const bool _enableDevOverlayFlag = bool.fromEnvironment(
  'CB_SHOW_DEV_OVERLAY',
  defaultValue: false,
);

bool get isDevOverlayEnabled => !kReleaseMode && _enableDevOverlayFlag;

/// Developer overlay that shows a floating dev tools button.
/// Only renders when explicitly enabled in a non-release build.
///
/// Usage in MaterialApp builder:
/// ```dart
/// builder: (context, child) {
///   return DevOverlay(child: child ?? const SizedBox.shrink());
/// }
/// ```
class DevOverlay extends StatefulWidget {
  final Widget child;

  const DevOverlay({Key? key, required this.child}) : super(key: key);

  @override
  State<DevOverlay> createState() => _DevOverlayState();
}

class _DevOverlayState extends State<DevOverlay> {
  bool _isPanelOpen = false;
  Offset _buttonPosition = const Offset(16, 100);

  @override
  Widget build(BuildContext context) {
    if (!isDevOverlayEnabled) return widget.child;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          // Draggable dev tools button
          Positioned(
            left: _buttonPosition.dx,
            top: _buttonPosition.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _buttonPosition = Offset(
                    _buttonPosition.dx + details.delta.dx,
                    _buttonPosition.dy + details.delta.dy,
                  );
                });
              },
              child: _DevButton(
                isOpen: _isPanelOpen,
                onTap: () => setState(() => _isPanelOpen = !_isPanelOpen),
              ),
            ),
          ),
          // Dev tools panel
          if (_isPanelOpen)
            Positioned(
              left: _buttonPosition.dx,
              top: _buttonPosition.dy + 48,
              child: DevToolsPanel(
                onClose: () => setState(() => _isPanelOpen = false),
              ),
            ),
        ],
      ),
    );
  }
}

class _DevButton extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onTap;

  const _DevButton({required this.isOpen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      color: isOpen ? Colors.red.shade700 : Colors.deepPurple.shade700,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Text(
            isOpen ? '✕' : '🔧',
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}

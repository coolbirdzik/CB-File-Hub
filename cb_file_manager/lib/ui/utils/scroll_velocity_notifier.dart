import 'dart:async';
import 'package:flutter/material.dart';

/// A global notifier that tracks scroll velocity to optimize performance
/// during fast scrolling operations.
///
/// This is used to pause expensive operations like thumbnail generation
/// when the user is scrolling quickly through a list/grid.
class ScrollVelocityNotifier extends ChangeNotifier {
  static final ScrollVelocityNotifier _instance =
      ScrollVelocityNotifier._internal();
  static ScrollVelocityNotifier get instance => _instance;

  ScrollVelocityNotifier._internal();

  double _velocity = 0.0;
  DateTime _lastUpdate = DateTime.now();
  Timer? _resetTimer;
  bool _isScrollingFast = false;
  bool _isScrolling = false;

  // Configuration - pixels per second threshold for "fast scrolling"
  static const double _fastScrollThreshold = 800.0;
  // Time window to consider scroll "stopped"
  static const Duration _resetDelay = Duration(milliseconds: 150);

  /// Current scroll velocity in pixels per second
  double get velocity => _velocity;

  /// Whether the user is currently scrolling fast
  bool get isScrollingFast => _isScrollingFast;

  /// Any non-zero scrolling remains active until end/idle, including the
  /// first slow tick after a long pause.
  bool get isScrolling => _isScrolling;

  /// Update the scroll velocity based on scroll delta
  /// Call this from ScrollNotification callbacks
  void updateVelocity(double scrollDelta) {
    if (scrollDelta == 0) return;
    final wasScrolling = _isScrolling;
    _isScrolling = true;
    final now = DateTime.now();
    final deltaTime = wasScrolling
        ? now.difference(_lastUpdate).inMilliseconds
        : 16;

    // Calculate velocity (pixels per second approximation)
    if (deltaTime > 0) {
      // Use exponential moving average for smoother velocity tracking
      final instantVelocity = (scrollDelta.abs() / deltaTime) * 1000;
      _velocity = (_velocity * 0.7) + (instantVelocity * 0.3);
    } else {
      _velocity = scrollDelta.abs().toDouble();
    }

    _lastUpdate = now;

    // Determine if scrolling is fast
    final wasScrollingFast = _isScrollingFast;
    _isScrollingFast = _velocity > _fastScrollThreshold;

    // Notify listeners if state changed
    if (!wasScrolling || wasScrollingFast != _isScrollingFast) {
      notifyListeners();
    }

    // Cancel existing reset timer
    _resetTimer?.cancel();

    // Set timer to reset velocity after scroll stops
    _resetTimer = Timer(_resetDelay, reset);
  }

  /// Reset velocity (call when scroll ends)
  void reset() {
    final wasScrolling = _isScrolling || _isScrollingFast;
    _velocity = 0;
    _isScrolling = false;
    _isScrollingFast = false;
    _resetTimer?.cancel();
    if (wasScrolling) notifyListeners();
  }

  /// Dispose resources
  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }
}

/// A widget that listens to scroll notifications and updates the global
/// ScrollVelocityNotifier. Wrap this around scrollable views.
class ScrollVelocityListener extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const ScrollVelocityListener({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          final scrollDelta = notification.scrollDelta;
          if (scrollDelta != null && scrollDelta != 0) {
            ScrollVelocityNotifier.instance.updateVelocity(scrollDelta);
          }
        } else if (notification is ScrollEndNotification) {
          ScrollVelocityNotifier.instance.reset();
        }
        return false; // Don't consume the notification
      },
      child: child,
    );
  }
}

/// Mixin for widgets that need to react to scroll velocity changes
/// Usage: `class MyWidget extends StatefulWidget with ScrollVelocityAware`
mixin ScrollVelocityAware<T extends StatefulWidget> on State<T> {
  bool _isScrollingFast = false;

  bool get isScrollingFast => _isScrollingFast;

  @override
  void initState() {
    super.initState();
    ScrollVelocityNotifier.instance.addListener(_onVelocityChanged);
  }

  @override
  void dispose() {
    ScrollVelocityNotifier.instance.removeListener(_onVelocityChanged);
    super.dispose();
  }

  void _onVelocityChanged() {
    final newValue = ScrollVelocityNotifier.instance.isScrollingFast;
    if (_isScrollingFast != newValue) {
      setState(() {
        _isScrollingFast = newValue;
      });
      onScrollVelocityChanged(newValue);
    }
  }

  /// Override this to react to scroll velocity changes
  void onScrollVelocityChanged(bool isScrollingFast) {}
}

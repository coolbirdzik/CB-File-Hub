import 'dart:async';

import 'package:flutter/material.dart';

/// App-wide "busy" mouse cursor.
///
/// Windows Explorer switches to the app-starting cursor (arrow + spinner) the
/// moment a file is double-clicked and keeps it until the handler has been
/// launched. Flutter has no global cursor, so this holds a single flag that
/// [AppBusyCursorOverlay] — mounted once at the app root — turns into a real
/// cursor for every route in the window.
///
/// Two ways to drive it:
/// * [pulse] for fire-and-forget opens (the caller has no future to await).
/// * [run] / [begin] + [end] to keep it up for exactly as long as an async
///   launch takes. Scopes are ref-counted, so nested calls are safe.
class AppBusyCursor {
  AppBusyCursor._();

  /// Minimum on-screen time. Shorter than this the cursor only flickers.
  static const Duration minimumHold = Duration(milliseconds: 700);

  /// Hard cap for a single scope so a launch that never completes cannot leave
  /// the whole window stuck on the busy cursor.
  static const Duration _scopeTimeout = Duration(seconds: 15);

  /// Watched by [AppBusyCursorOverlay].
  static final ValueNotifier<bool> isBusy = ValueNotifier<bool>(false);

  static int _scopes = 0;
  static DateTime? _holdUntil;
  static Timer? _holdTimer;
  static Timer? _scopeTimer;

  /// Shows the busy cursor now and keeps it for at least [hold].
  static void pulse([Duration hold = minimumHold]) {
    final DateTime until = DateTime.now().add(hold);
    if (_holdUntil != null && !until.isAfter(_holdUntil!)) {
      _sync();
      return;
    }
    _holdUntil = until;
    _holdTimer?.cancel();
    _holdTimer = Timer(hold, () {
      _holdTimer = null;
      _holdUntil = null;
      _sync();
    });
    _sync();
  }

  /// Opens a busy scope. Every call must be paired with [end].
  static void begin() {
    _scopes++;
    _scopeTimer ??= Timer(_scopeTimeout, () {
      _scopeTimer = null;
      _scopes = 0;
      _sync();
    });
    _sync();
  }

  /// Closes a scope opened by [begin].
  static void end() {
    if (_scopes > 0) _scopes--;
    if (_scopes == 0) {
      _scopeTimer?.cancel();
      _scopeTimer = null;
    }
    _sync();
  }

  /// Runs [action] with the busy cursor up, keeping it visible for at least
  /// [minimumHold] so quick launches still give feedback.
  static Future<T> run<T>(Future<T> Function() action) async {
    begin();
    pulse();
    try {
      return await action();
    } finally {
      end();
    }
  }

  static void _sync() {
    final bool busy = _scopes > 0 || _holdUntil != null;
    if (isBusy.value != busy) isBusy.value = busy;
  }

  @visibleForTesting
  static void resetForTest() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _scopeTimer?.cancel();
    _scopeTimer = null;
    _holdUntil = null;
    _scopes = 0;
    _sync();
  }
}

/// Paints [AppBusyCursor] over the whole window.
///
/// The region sits on top of the app so it wins cursor resolution against the
/// per-item cursors (rows use [SystemMouseCursors.click]), and is declared
/// non-opaque so hover highlights and taps still reach the widgets underneath.
class AppBusyCursorOverlay extends StatelessWidget {
  const AppBusyCursorOverlay({
    Key? key,
    required this.child,
  }) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The Stack stays in the tree at all times. Wrapping [child] only while
    // busy would reparent — and therefore remount — the whole app subtree on
    // every toggle; this way just the region on top rebuilds.
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: <Widget>[
        child,
        Positioned.fill(
          child: ValueListenableBuilder<bool>(
            valueListenable: AppBusyCursor.isBusy,
            builder: (context, busy, _) => MouseRegion(
              // `defer` hands the cursor back to whatever is underneath.
              cursor: busy ? SystemMouseCursors.progress : MouseCursor.defer,
              opaque: false,
            ),
          ),
        ),
      ],
    );
  }
}

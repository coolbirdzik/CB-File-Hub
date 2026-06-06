import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cb_file_manager/main.dart' show goHome;

/// A wrapper widget that provides safe navigation handling
/// This widget should wrap the entire app to catch navigation errors
class SafeNavigationWrapper extends StatefulWidget {
  final Widget child;

  const SafeNavigationWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<SafeNavigationWrapper> createState() => _SafeNavigationWrapperState();
}

class _SafeNavigationWrapperState extends State<SafeNavigationWrapper> {
  FlutterExceptionHandler? _previousOnError;
  @override
  void initState() {
    super.initState();

    // Set up global error handling for navigation
    _previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final message = details.exceptionAsString();
      // Filter extremely noisy, non-fatal render/semantics assertions
      if (message.contains("semantics.parentDataDirty") ||
          (message.contains("Semantics") &&
              message.contains("parentDataDirty")) ||
          message.contains("_debugDoingThisLayout") ||
          message.contains("RenderBox was not laid out") ||
          message.contains("hasSize") ||
          message.contains("NEEDS-COMPOSITING-BITS-UPDATE") ||
          // RenderParagraph system-font update called during midFrameMicrotasks.
          // This is a Flutter framework timing issue triggered by platform font
          // notifications arriving while a frame is in progress; it is non-fatal.
          message.contains("_scheduleSystemFontsUpdate") ||
          message.contains("schedulerPhase == SchedulerPhase.idle") ||
          message.contains("midFrameMicrotasks")) {
        // Forward to default handler without extra logging to avoid log spam
        if (_previousOnError != null) {
          _previousOnError!(details);
        } else {
          FlutterError.dumpErrorToConsole(details);
        }
        return;
      }

      debugPrint(
          'Flutter Error in SafeNavigationWrapper: ${details.exception}');

      // Check if this is a navigation-related error
      if (message.contains('_history.isNotEmpty') ||
          message.contains('Navigator') ||
          message.contains('pop')) {
        debugPrint('Navigation error detected, attempting recovery...');
        _handleNavigationError();
      }

      // Always forward to previous handler for completeness
      if (_previousOnError != null) {
        _previousOnError!(details);
      } else {
        FlutterError.dumpErrorToConsole(details);
      }
    };
  }

  void _handleNavigationError() {
    try {
      // Schedule the navigation recovery for the next frame to avoid layout conflicts
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              goHome(context);
            } catch (e) {
              debugPrint('Failed to recover from navigation error: $e');
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to schedule navigation recovery: $e');
    }
  }

  @override
  void dispose() {
    // Restore the previous error handler so the next test's SafeNavigationWrapper
    // starts from a clean slate. Without this, each testWidgets call chains a new
    // handler on top of a stale one that holds a reference to the disposed state.
    FlutterError.onError = _previousOnError;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Extension to provide safe navigation methods on BuildContext
extension SafeNavigation on BuildContext {
  /// Safely pop the current route
  void safePop() {
    try {
      if (mounted && Navigator.of(this).canPop()) {
        Navigator.of(this).pop();
      } else {
        debugPrint('Cannot pop, going home');
        goHome(this);
      }
    } catch (e) {
      debugPrint('Error in safePop: $e');
      goHome(this);
    }
  }

  /// Safely pop with result
  void safePopWithResult(dynamic result) {
    try {
      if (mounted && Navigator.of(this).canPop()) {
        Navigator.of(this).pop(result);
      } else {
        debugPrint('Cannot pop with result, going home');
        goHome(this);
      }
    } catch (e) {
      debugPrint('Error in safePopWithResult: $e');
      goHome(this);
    }
  }

  /// Check if navigation is safe
  bool get canNavigateSafely {
    return mounted && Navigator.of(this).canPop();
  }
}

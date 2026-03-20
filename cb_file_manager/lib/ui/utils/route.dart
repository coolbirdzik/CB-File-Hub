import 'package:flutter/material.dart';
import 'package:cb_file_manager/main.dart' show goHome, CBFileApp;
import 'package:cb_file_manager/services/windowing/window_acrylic_service.dart';

class RouteUtils {
  // Remove redundant methods and keep only the most robust navigation method

  // Add a safe navigation method that ensures we never get an empty stack
  static void safeNavigate(BuildContext context, Widget screen) {
    try {
      // First check if we can navigate at all
      if (!context.mounted) {
        return;
      }

      // Create a fresh route
      final route = MaterialPageRoute(builder: (_) => screen);

      // If we can pop, replace this route, otherwise push a new one
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pushReplacement(route);
      } else {
        Navigator.of(context).push(route);
      }
    } catch (e) {
      // Last resort fallback
      if (context.mounted) {
        goHome(context);
      }
    }
  }

  /// Safe back navigation that handles empty navigator stack
  static void safeBackNavigation(BuildContext context) {
    try {
      // Check if the context is still mounted
      if (!context.mounted) {
        debugPrint('Context not mounted, cannot handle back navigation');
        return;
      }

      // Get the navigator state
      final navigator = Navigator.of(context);

      // Check if we can pop before attempting to
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        // If we can't pop, check if we're at the root level
        final route = ModalRoute.of(context);
        if (route != null && route.isCurrent) {
          // We're at the root, navigate to home safely
          goHome(context);
        } else {
          // Fallback: try to go home anyway
          goHome(context);
        }
      }
    } catch (e) {
      debugPrint('Error in safe back navigation: $e');
      // Last resort: try to go home
      try {
        if (context.mounted) {
          goHome(context);
        }
      } catch (homeError) {
        debugPrint('Failed to go home: $homeError');
        // If even going home fails, restart the app
        runApp(CBFileApp(
          windowAcrylicService: WindowAcrylicService(),
        ));
      }
    }
  }

  /// Check if navigation is safe to perform
  static bool canNavigate(BuildContext context) {
    return context.mounted && Navigator.of(context).canPop();
  }

  /// Safe pop with fallback to home
  static void safePop(BuildContext context) {
    try {
      if (context.mounted && Navigator.of(context).canPop()) {
        RouteUtils.safePopDialog(context);
      } else {
        goHome(context);
      }
    } catch (e) {
      debugPrint('Error in safe pop: $e');
      goHome(context);
    }
  }

  /// Safe pop for dialogs and modals - this is the main replacement for Navigator.pop(context)
  /// Use this instead of Navigator.pop(context) throughout the app
  static void safePopDialog(BuildContext context) {
    try {
      // Check if context is still mounted
      if (!context.mounted) {
        debugPrint('Context not mounted, cannot pop dialog');
        return;
      }

      // For dialogs, we can usually pop safely, but let's still check
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        // If we can't pop, this might be a root dialog, try to go home
        debugPrint('Cannot pop dialog, attempting to go home');
        goHome(context);
      }
    } catch (e) {
      debugPrint('Error in safe pop dialog: $e');
      // Last resort: try to go home
      try {
        if (context.mounted) {
          goHome(context);
        }
      } catch (homeError) {
        debugPrint('Failed to go home from dialog: $homeError');
      }
    }
  }

  /// Safe pop with result for dialogs
  static void safePopWithResult(BuildContext context, dynamic result) {
    try {
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
      } else {
        debugPrint('Cannot pop with result, going home');
        goHome(context);
      }
    } catch (e) {
      debugPrint('Error in safe pop with result: $e');
      goHome(context);
    }
  }
}

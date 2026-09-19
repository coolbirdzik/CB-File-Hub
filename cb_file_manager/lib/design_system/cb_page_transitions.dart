import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a platform page transition so that every page it builds stays clear
/// of the phone's status and navigation bars.
///
/// Android 15+ lays apps out edge-to-edge: the system bars are transparent
/// overlays on top of the app. Each screen used to be responsible for its own
/// insets, so any page without a [SafeArea] ran underneath them. Applying the
/// safe area here covers every page route at once, and the [SafeArea]s pages
/// already have become no-ops rather than double padding, because this one
/// consumes the insets. The bars sit over the canvas colour, so they read as
/// part of the flat surface.
///
/// Applied per page rather than once around the navigator, so that a page
/// drawn under the bars ([CbFullBleedPageRoute]) changes nothing for the
/// pages beneath it.
class CbSafePageTransitionsBuilder extends PageTransitionsBuilder {
  /// The transition the page actually runs.
  final PageTransitionsBuilder transition;

  const CbSafePageTransitionsBuilder(this.transition);

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      transition.delegatedTransition;

  @override
  Duration get transitionDuration => transition.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      transition.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return transition.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      route is CbFullBleedPageRoute ? child : _SafePage(child: child),
    );
  }
}

class _SafePage extends StatelessWidget {
  final Widget child;

  const _SafePage({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Brightness icons = theme.brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    // The bars now sit over this page's canvas rather than over its content,
    // so the page's own regions (an app bar's) no longer reach under them;
    // the icon colour is set here to contrast with the canvas.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons,
        // iOS reads the brightness of what is behind the bar, not the icons.
        statusBarBrightness: theme.brightness,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(child: child),
      ),
    );
  }
}

/// A page drawn edge to edge, under the system bars, which keeps its own
/// controls clear of them.
///
/// For media viewers that hide and show the bars as their controls come and
/// go: inside the safe area, every toggle would move the picture by the bar
/// height.
class CbFullBleedPageRoute<T> extends MaterialPageRoute<T> {
  CbFullBleedPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });
}

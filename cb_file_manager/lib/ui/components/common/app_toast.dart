import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/config/app_toast_theme.dart';

class AppToast {
  const AppToast._();

  static AppToastPresenter capture(BuildContext context) {
    final theme = Theme.of(context);
    return AppToastPresenter._(
      overlay: Overlay.maybeOf(context, rootOverlay: true),
      colorScheme: theme.colorScheme,
      toastTheme: theme.extension<AppToastTheme>(),
    );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    final p = capture(context);
    p.success(message, duration: duration);
  }

  static void info(BuildContext context, String message, {Duration? duration}) {
    capture(context).info(message, duration: duration);
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    capture(context).warning(message, duration: duration);
  }

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    capture(context).error(message, duration: duration);
  }

  static void show(
    BuildContext context,
    String message, {
    IconData icon = PhosphorIconsLight.info,
    Color? accentColor,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    capture(context).show(
      message,
      icon: icon,
      accentColor: accentColor,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class AppToastPresenter {
  final OverlayState? overlay;
  final ColorScheme colorScheme;
  final AppToastTheme? toastTheme;

  const AppToastPresenter._({
    required this.overlay,
    required this.colorScheme,
    this.toastTheme,
  });

  void success(String message, {Duration? duration}) {
    show(
      message,
      icon: PhosphorIconsLight.checkCircle,
      accentColor: colorScheme.primary,
      duration: duration ?? toastTheme?.durationSuccess,
    );
  }

  void info(String message, {Duration? duration}) {
    show(
      message,
      icon: PhosphorIconsLight.info,
      accentColor: colorScheme.primary,
      duration: duration ?? toastTheme?.durationInfo,
    );
  }

  void warning(String message, {Duration? duration}) {
    show(
      message,
      icon: PhosphorIconsLight.warningCircle,
      accentColor: colorScheme.tertiary,
      duration: duration ?? toastTheme?.durationWarning,
    );
  }

  void error(String message, {Duration? duration}) {
    show(
      message,
      icon: PhosphorIconsLight.xCircle,
      accentColor: colorScheme.error,
      duration: duration ?? toastTheme?.durationError,
    );
  }

  void show(
    String message, {
    IconData icon = PhosphorIconsLight.info,
    Color? accentColor,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (overlay == null) return;
    final resolvedAccentColor = accentColor ?? colorScheme.primary;
    final t = toastTheme;

    late final OverlayEntry entry;
    Timer? timer;

    void dismiss() {
      timer?.cancel();
      if (entry.mounted) {
        entry.remove();
      }
    }

    entry = OverlayEntry(
      builder: (overlayContext) => _AppToastOverlay(
        message: message,
        icon: icon,
        accentColor: resolvedAccentColor,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: dismiss,
        theme: t,
      ),
    );

    overlay!.insert(entry);
    timer = Timer(
      duration ?? t?.durationInfo ?? const Duration(milliseconds: 2200),
      dismiss,
    );
  }
}

class _AppToastOverlay extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final AppToastTheme? theme;

  const _AppToastOverlay({
    required this.message,
    required this.icon,
    required this.accentColor,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
    this.theme,
  });

  // ─── Token accessors ──────────────────────────────────────────────────
  // Falls back to hardcoded defaults only when no theme extension is present.

  double get _iconBoxSize => theme?.iconBoxSize ?? 30.0;
  double get _iconSize => theme?.iconSize ?? 18.0;
  double get _iconBoxRadius => theme?.iconBoxRadius ?? 8.0;
  double get _containerRadius => theme?.containerRadius ?? 12.0;
  double get _hPadding => theme?.hPadding ?? 12.0;
  double get _vPadding => theme?.vPadding ?? 10.0;
  double get _maxWidth => theme?.maxWidth ?? 360.0;

  double _blurSigma(bool isDesktop, bool isDark) {
    if (!isDesktop) return theme?.blurSigmaMobile ?? 8.0;
    return isDark
        ? (theme?.blurSigmaDesktopDark ?? 10.0)
        : (theme?.blurSigmaDesktopLight ?? 18.0);
  }

  double get _surfaceOpacity => theme?.surfaceOpacity ?? 0.82;
  double get _borderOpacity => theme?.borderOpacity ?? 0.22;
  double get _shadowOpacityLight => theme?.shadowOpacityLight ?? 0.16;
  double get _shadowOpacityDark => theme?.shadowOpacityDark ?? 0.40;
  double get _iconAccentOpacity => theme?.iconAccentOpacity ?? 0.14;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 700;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      right: isDesktop ? 24 : 16,
      left: isDesktop ? null : 16,
      bottom: isDesktop ? 24 : 16,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: 0, end: 1),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: child,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_containerRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _blurSigma(isDesktop, isDark),
                sigmaY: _blurSigma(isDesktop, isDark),
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? _maxWidth : double.infinity,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: _hPadding,
                  vertical: _vPadding,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: _surfaceOpacity),
                  borderRadius: BorderRadius.circular(_containerRadius),
                  border: Border.all(
                    color: colorScheme.outline.withValues(
                      alpha: _borderOpacity,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark
                            ? _shadowOpacityDark
                            : _shadowOpacityLight,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: _iconBoxSize,
                          height: _iconBoxSize,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(
                              alpha: _iconAccentOpacity,
                            ),
                            borderRadius: BorderRadius.circular(_iconBoxRadius),
                          ),
                          child: Icon(
                            icon,
                            color: accentColor,
                            size: _iconSize,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              message,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          onPressed: onDismiss,
                          icon: Icon(
                            PhosphorIconsLight.x,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (actionLabel != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            onAction?.call();
                            onDismiss();
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            actionLabel!,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

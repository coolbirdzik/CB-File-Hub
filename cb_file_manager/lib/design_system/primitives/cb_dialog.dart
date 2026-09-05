import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_button.dart';
import 'cb_surface.dart';

/// The dialog primitive.
///
/// Material's `AlertDialog` fixes the title/content/actions arrangement to
/// mobile conventions: 24px insets everywhere, actions right-aligned in a
/// `ButtonBar` with its own spacing rules, and a 280px minimum width. This
/// one is built on [CbSurface] so it inherits the same radius, border and
/// shadow as every other floating surface in the app, and it sizes for a
/// desktop window.
class CbDialog extends StatelessWidget {
  final String title;

  /// Secondary line under the title — the consequence of the action, the path
  /// being operated on, the count of affected items.
  final String? subtitle;

  final Widget? content;

  /// Footer buttons, laid out end-aligned. Put the confirming action last:
  /// on desktop the rightmost button is the default action.
  final List<Widget> actions;

  /// Leading icon, typically used to mark destructive or warning dialogs.
  final IconData? icon;

  /// Tints [icon] and its backing chip with the danger colour.
  final bool destructive;

  final double width;

  /// Shows the close affordance in the header.
  final bool showCloseButton;

  const CbDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.content,
    this.actions = const [],
    this.icon,
    this.destructive = false,
    this.width = 440,
    this.showCloseButton = true,
  });

  /// Shows this dialog and completes with the value passed to
  /// `Navigator.pop`.
  static Future<T?> show<T>({
    required BuildContext context,
    required CbDialog dialog,
    bool barrierDismissible = true,
  }) {
    final c = context.cbColors;
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: c.scrim,
      builder: (_) => dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final Color accentColor = destructive ? c.status.danger : c.accent.text;
    final Color accentSurface = destructive
        ? c.status.dangerSurface
        : c.accent.tint;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(CbSpacing.xl),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.of(context).size.height - CbSpacing.xxxl * 2,
        ),
        child: CbSurface(
          level: CbSurfaceLevel.modal,
          bordered: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CbSpacing.xl,
                  CbSpacing.xl,
                  CbSpacing.md,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: CbSizes.controlMd,
                        height: CbSizes.controlMd,
                        decoration: BoxDecoration(
                          color: accentSurface,
                          borderRadius: CbRadii.mdAll,
                        ),
                        child: Icon(
                          icon,
                          size: CbSizes.iconLg,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: CbSpacing.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: CbTypography.headingLg.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: CbSpacing.xs),
                            Text(
                              subtitle!,
                              style: CbTypography.body.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showCloseButton) ...[
                      const SizedBox(width: CbSpacing.sm),
                      CbButton.icon(
                        icon: Icons.close,
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        size: CbButtonSize.sm,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ],
                ),
              ),
              if (content != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CbSpacing.xl,
                      CbSpacing.lg,
                      CbSpacing.xl,
                      0,
                    ),
                    child: SingleChildScrollView(child: content),
                  ),
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(CbSpacing.xl),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (int i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: CbSpacing.sm),
                        actions[i],
                      ],
                    ],
                  ),
                )
              else
                const SizedBox(height: CbSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// A confirm/cancel dialog — the shape most call sites actually need.
///
/// Returns `true` when confirmed, `null` when dismissed.
Future<bool?> showCbConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  IconData? icon,
  bool destructive = false,
}) {
  final materialL10n = MaterialLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    barrierColor: context.cbColors.scrim,
    builder: (dialogContext) => CbDialog(
      title: title,
      subtitle: message,
      icon: icon,
      destructive: destructive,
      actions: [
        CbButton(
          label: cancelLabel ?? materialL10n.cancelButtonLabel,
          variant: CbButtonVariant.secondary,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CbButton(
          label: confirmLabel ?? materialL10n.okButtonLabel,
          variant: destructive
              ? CbButtonVariant.danger
              : CbButtonVariant.primary,
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
}

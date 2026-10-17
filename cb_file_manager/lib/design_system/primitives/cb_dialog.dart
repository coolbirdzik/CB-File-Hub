import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_button.dart';

/// The dialog primitive.
///
/// Material's `AlertDialog` fixes the title/content/actions arrangement to
/// mobile conventions: 24px insets everywhere, actions right-aligned in a
/// `ButtonBar` with its own spacing rules, and a 280px minimum width. This
/// one retains a desktop layout while using the same [DialogTheme] surface
/// as the app's other dialogs, including the desktop acrylic theme bridge.
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

  /// Tints [icon] with the danger colour.
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
    this.width = 520,
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
    final dialogTheme = DialogTheme.of(context);
    final iconColor = destructive ? c.status.danger : c.icon;
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 600;
    final padding = narrow ? CbSpacing.lg : CbSpacing.xxl;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? CbSpacing.lg : CbSpacing.xxl,
        vertical: CbSpacing.xl,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight:
              (media.size.height - media.viewInsets.vertical - CbSpacing.xxxl)
                  .clamp(0.0, double.infinity),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding, CbSpacing.xl, padding, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: CbSpacing.xs),
                          child: Icon(
                            icon,
                            size: CbSizes.iconLg,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: CbSpacing.md),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style:
                              dialogTheme.titleTextStyle ??
                              CbTypography.headingLg.copyWith(
                                color: c.textPrimary,
                              ),
                        ),
                      ),
                      if (showCloseButton) ...[
                        const SizedBox(width: CbSpacing.lg),
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
                  if (subtitle != null) ...[
                    const SizedBox(height: CbSpacing.sm),
                    Text(
                      subtitle!,
                      style: (dialogTheme.contentTextStyle ?? CbTypography.body)
                          .copyWith(color: c.textSecondary, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            if (content != null)
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    CbSpacing.xl,
                    padding,
                    CbSpacing.xl,
                  ),
                  child: SingleChildScrollView(child: content),
                ),
              ),
            if (actions.isNotEmpty)
              Container(
                margin: content == null
                    ? const EdgeInsets.only(top: CbSpacing.xl)
                    : EdgeInsets.zero,
                padding: EdgeInsets.fromLTRB(
                  padding,
                  CbSpacing.lg,
                  padding,
                  CbSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: c.fillSubtle,
                  border: Border(top: BorderSide(color: c.strokeSubtle)),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: CbSpacing.md,
                    runSpacing: CbSpacing.md,
                    children: actions,
                  ),
                ),
              )
            else if (content == null)
              const SizedBox(height: CbSpacing.xl),
          ],
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

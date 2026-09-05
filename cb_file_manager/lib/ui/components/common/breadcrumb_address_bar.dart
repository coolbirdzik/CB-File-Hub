import 'dart:io' show Platform;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/design_system_config.dart';
import '../../../design_system/fluent_surface_tokens.dart';
import '../../../design_system/tokens/cb_geometry_tokens.dart';

/// A single item in a [BreadcrumbAddressBar].
class BreadcrumbSegment {
  /// Display text for the chip.
  final String label;

  /// Optional icon shown to the left of the label.
  final IconData? icon;

  /// Called when this segment chip is tapped.
  /// Set to null to make the segment non-interactive (current/active segment).
  final VoidCallback? onTap;

  /// Optional short badge text shown after the label (e.g. item count).
  final String? badge;

  const BreadcrumbSegment({
    required this.label,
    this.icon,
    this.onTap,
    this.badge,
  });
}

/// An address-bar-style breadcrumb row that displays [segments] as small pill
/// chips separated by caret-right icons.
///
/// - Non-last segments whose [BreadcrumbSegment.onTap] is set are tappable for
///   navigation.
/// - If [editController] and [onPathSubmitted] are both provided, the last
///   segment (and any empty space) becomes tappable to enter a text-editing
///   mode where the user can type a raw path.  Blur or Enter exits edit mode.
class BreadcrumbAddressBar extends StatefulWidget {
  final List<BreadcrumbSegment> segments;

  /// Provide both to enable click-to-type editing mode.
  final TextEditingController? editController;
  final void Function(String)? onPathSubmitted;

  const BreadcrumbAddressBar({
    super.key,
    required this.segments,
    this.editController,
    this.onPathSubmitted,
  });

  @override
  State<BreadcrumbAddressBar> createState() => _BreadcrumbAddressBarState();
}

class _BreadcrumbAddressBarState extends State<BreadcrumbAddressBar> {
  bool _isEditing = false;
  final FocusNode _focusNode = FocusNode();
  final FocusNode _addressFocusNode = FocusNode();

  bool get _canEdit =>
      widget.editController != null && widget.onPathSubmitted != null;

  @override
  void dispose() {
    _focusNode.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (!_canEdit || _isEditing) return;
    final controller = widget.editController!;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _stopEditing() {
    if (!mounted) return;
    setState(() => _isEditing = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _addressFocusNode,
      canRequestFocus: _canEdit && !_isEditing,
      onFocusChange: (focused) {
        if (focused && _addressFocusNode.hasPrimaryFocus) _startEditing();
      },
      child: _isEditing
          ? _buildEditField(context)
          : MouseRegion(
              cursor: _canEdit ? SystemMouseCursors.text : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _canEdit ? _startEditing : null,
                child: SizedBox(
                  width: double.infinity,
                  height: FluentSurfaceTokens.controlHeight,
                  child: _buildBreadcrumbs(context),
                ),
              ),
            ),
    );
  }

  Widget _buildBreadcrumbs(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final useFluentDesktopShell =
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        DesignSystemConfig.enableFluentDesktopShell &&
        !DesignSystemConfig.enableLegacyMaterialDesktopShell;
    final surfaces = useFluentDesktopShell
        ? FluentSurfaceTokens.of(context)
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth &&
            _estimatedNaturalWidth(context) > constraints.maxWidth;
        final items = <Widget>[];

        for (int i = 0; i < widget.segments.length; i++) {
          final seg = widget.segments[i];
          final isLast = i == widget.segments.length - 1;

          if (i > 0) {
            items.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  PhosphorIconsLight.caretRight,
                  size: 11,
                  color:
                      surfaces?.textSecondary ?? colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }

          // For the last segment: fall back to _startEditing if canEdit and no
          // explicit onTap was provided.
          final effectiveTap =
              seg.onTap ?? (isLast && _canEdit ? _startEditing : null);

          final chip = _BreadcrumbChip(
            key: ValueKey(i),
            segment: seg,
            isLast: isLast,
            colorScheme: colorScheme,
            surfaces: surfaces,
            onTap: effectiveTap,
          );

          // Keep short paths content-sized. Only deep paths need flex shares;
          // applying Flexible all the time makes Fluent controls consume their
          // entire allocation and visually spreads folder names apart.
          items.add(
            compact
                ? Flexible(
                    // Icons need roughly the same horizontal space as eight
                    // label characters. Account for that in the flex share so
                    // the root drive icon is not squeezed too aggressively.
                    flex: (seg.label.length + 4 + (seg.icon == null ? 0 : 8))
                        .clamp(1, 100),
                    child: chip,
                  )
                : chip,
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: items,
        );
      },
    );
  }

  double _estimatedNaturalWidth(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    double width = (widget.segments.length - 1).clamp(0, 100000) * 15.0;

    for (int i = 0; i < widget.segments.length; i++) {
      final segment = widget.segments[i];
      width += 16; // Chip horizontal padding.
      width += _measureTextWidth(
        segment.label,
        TextStyle(
          fontSize: 13,
          fontWeight: i == widget.segments.length - 1
              ? FontWeight.w500
              : FontWeight.normal,
        ),
        textScaler,
      );
      if (segment.icon != null) width += 18;
      if (segment.badge != null) {
        width +=
            6 +
            _measureTextWidth(
              segment.badge!,
              const TextStyle(fontSize: 11),
              textScaler,
            );
      }
    }
    return width;
  }

  double _measureTextWidth(
    String text,
    TextStyle style,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return painter.width;
  }

  Widget _buildEditField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final useFluentDesktopShell =
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        DesignSystemConfig.enableFluentDesktopShell &&
        !DesignSystemConfig.enableLegacyMaterialDesktopShell;
    if (useFluentDesktopShell) {
      final surfaces = FluentSurfaceTokens.of(context);
      return fluent.TextBox(
        controller: widget.editController,
        focusNode: _focusNode,
        autofocus: true,
        onSubmitted: (value) {
          widget.onPathSubmitted?.call(value);
          _stopEditing();
        },
        onTapOutside: (_) => _stopEditing(),
        placeholder: 'Enter path...',
        style: TextStyle(fontSize: 13, color: surfaces.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const WidgetStatePropertyAll(
          BoxDecoration(color: Colors.transparent, border: Border()),
        ),
        foregroundDecoration: const WidgetStatePropertyAll(
          BoxDecoration(border: Border()),
        ),
      );
    }

    return TextField(
      controller: widget.editController,
      focusNode: _focusNode,
      onSubmitted: (value) {
        widget.onPathSubmitted?.call(value);
        _stopEditing();
      },
      onTapOutside: (_) => _stopEditing(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        border: InputBorder.none,
        hintText: 'Enter path...',
        hintStyle: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// Internal stateful chip that shows one breadcrumb segment.
class _BreadcrumbChip extends StatefulWidget {
  final BreadcrumbSegment segment;
  final bool isLast;
  final ColorScheme colorScheme;
  final FluentSurfaceTokens? surfaces;
  final VoidCallback? onTap;

  const _BreadcrumbChip({
    super.key,
    required this.segment,
    required this.isLast,
    required this.colorScheme,
    this.surfaces,
    this.onTap,
  });

  @override
  State<_BreadcrumbChip> createState() => _BreadcrumbChipState();
}

class _BreadcrumbChipState extends State<_BreadcrumbChip> {
  /// Below these widths the leading icon and the trailing badge cost more
  /// horizontal space than the label they decorate, so they are dropped.
  static const double _minWidthForIcon = 48;
  static const double _minWidthForBadge = 84;

  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final seg = widget.segment;
    final colorScheme = widget.colorScheme;
    final surfaces = widget.surfaces;
    final tappable = widget.onTap != null;
    final textColor = surfaces?.textPrimary ?? colorScheme.onSurface;
    final secondaryColor =
        surfaces?.textSecondary ?? colorScheme.onSurfaceVariant;

    if (surfaces != null && tappable) {
      return _buildFluentChip(
        surfaces,
        textColor: textColor,
        secondaryColor: secondaryColor,
      );
    }

    return MouseRegion(
      onEnter: tappable ? (_) => setState(() => _hovering = true) : null,
      onExit: tappable ? (_) => setState(() => _hovering = false) : null,
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovering
                ? surfaces?.controlHover ??
                      colorScheme.onSurface.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: surfaces != null
                ? FluentSurfaceTokens.controlRadius
                : BorderRadius.circular(14),
          ),
          // The parent shares the address bar width across every crumb, so a
          // deep path on a narrow window can squeeze one chip down to a few
          // pixels. The icon and the badge gap are fixed width and overflow
          // once that happens, so they are dropped before the label is.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth;
              final showIcon =
                  seg.icon != null && available >= _minWidthForIcon;
              final showBadge =
                  seg.badge != null && available >= _minWidthForBadge;

              return Row(
                // Stay content-sized when the address bar has spare room so
                // neighbouring breadcrumb names sit beside their separators
                // instead of stretching across the full bar. The surrounding
                // Flexible still lets this row shrink and ellipsize on deep
                // paths in narrow windows.
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIcon) ...[
                    Icon(seg.icon, size: 13, color: secondaryColor),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      seg.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isLast
                            ? FontWeight.w500
                            : FontWeight.normal,
                        color: widget.isLast ? textColor : secondaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showBadge) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        seg.badge!,
                        style: TextStyle(fontSize: 11, color: secondaryColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFluentChip(
    FluentSurfaceTokens surfaces, {
    required Color textColor,
    required Color secondaryColor,
  }) {
    final seg = widget.segment;
    return fluent.HoverButton(
      cursor: SystemMouseCursors.click,
      semanticLabel: seg.label,
      onPressed: widget.onTap,
      builder: (context, states) {
        final isPressed = states.contains(WidgetState.pressed);
        final isHovered = states.contains(WidgetState.hovered);
        final isFocused = states.contains(WidgetState.focused);
        final Color backgroundColor = isPressed
            ? surfaces.controlPressed
            : isHovered
            ? surfaces.controlHover
            : Colors.transparent;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: FluentSurfaceTokens.controlRadius,
            border: isFocused
                ? Border.all(
                    color: surfaces.focusRing,
                    width: CbStrokes.emphasis,
                  )
                : null,
          ),
          child: _buildChipContent(
            textColor: textColor,
            secondaryColor: secondaryColor,
          ),
        );
      },
    );
  }

  Widget _buildChipContent({
    required Color textColor,
    required Color secondaryColor,
  }) {
    final seg = widget.segment;
    return Row(
      // HoverButton otherwise adopts the full flex allocation and leaves a
      // large empty gap after short folder names.
      mainAxisSize: MainAxisSize.min,
      children: [
        if (seg.icon != null) ...[
          Icon(seg.icon, size: 13, color: secondaryColor),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            seg.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: widget.isLast ? FontWeight.w500 : FontWeight.normal,
              color: widget.isLast ? textColor : secondaryColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (seg.badge != null) ...[
          const SizedBox(width: 6),
          Text(
            seg.badge!,
            style: TextStyle(fontSize: 11, color: secondaryColor),
          ),
        ],
      ],
    );
  }
}

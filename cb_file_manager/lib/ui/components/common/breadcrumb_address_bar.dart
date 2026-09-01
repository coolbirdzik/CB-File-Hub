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
    Key? key,
    required this.segments,
    this.editController,
    this.onPathSubmitted,
  }) : super(key: key);

  @override
  State<BreadcrumbAddressBar> createState() => _BreadcrumbAddressBarState();
}

class _BreadcrumbAddressBarState extends State<BreadcrumbAddressBar> {
  bool _isEditing = false;
  final FocusNode _focusNode = FocusNode();

  bool get _canEdit =>
      widget.editController != null && widget.onPathSubmitted != null;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (!_canEdit) return;
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
    if (_isEditing) return _buildEditField(context);
    return _buildBreadcrumbs(context);
  }

  Widget _buildBreadcrumbs(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final useFluentDesktopShell =
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
            DesignSystemConfig.enableFluentDesktopShell &&
            !DesignSystemConfig.enableLegacyMaterialDesktopShell;
    final surfaces =
        useFluentDesktopShell ? FluentSurfaceTokens.of(context) : null;
    final items = <Widget>[];

    for (int i = 0; i < widget.segments.length; i++) {
      final seg = widget.segments[i];
      final isLast = i == widget.segments.length - 1;

      if (i > 0) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            PhosphorIconsLight.caretRight,
            size: 11,
            color: surfaces?.textSecondary ?? colorScheme.onSurfaceVariant,
          ),
        ));
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

      // Every segment must be allowed to shrink. Windows CI paths commonly
      // contain several long parent segments (for example RUNNER~1/AppData/
      // Local/Temp/cb_e2e_*); keeping all parents inflexible makes the Row
      // overflow before the final segment gets a chance to truncate.
      items.add(
        Flexible(
          // Icons need roughly the same horizontal space as eight label
          // characters. Account for that in the flex share so the root drive
          // icon is not squeezed into a text-only allocation.
          flex:
              (seg.label.length + 4 + (seg.icon == null ? 0 : 8)).clamp(1, 100),
          child: chip,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: items,
    );
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
        style: TextStyle(
          fontSize: 13,
          color: surfaces.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: WidgetStatePropertyAll(
          BoxDecoration(
            color: surfaces.control,
            borderRadius: FluentSurfaceTokens.controlRadius,
            border: Border.all(color: surfaces.stroke),
          ),
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
    Key? key,
    required this.segment,
    required this.isLast,
    required this.colorScheme,
    this.surfaces,
    this.onTap,
  }) : super(key: key);

  @override
  State<_BreadcrumbChip> createState() => _BreadcrumbChipState();
}

class _BreadcrumbChipState extends State<_BreadcrumbChip> {
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
          child: Row(
            mainAxisSize: MainAxisSize.max,
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
                    fontWeight:
                        widget.isLast ? FontWeight.w500 : FontWeight.normal,
                    color: widget.isLast ? textColor : secondaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (seg.badge != null) ...[
                const SizedBox(width: 6),
                Text(
                  seg.badge!,
                  style: TextStyle(
                    fontSize: 11,
                    color: secondaryColor,
                  ),
                ),
              ],
            ],
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
      mainAxisSize: MainAxisSize.max,
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
            style: TextStyle(
              fontSize: 11,
              color: secondaryColor,
            ),
          ),
        ],
      ],
    );
  }
}

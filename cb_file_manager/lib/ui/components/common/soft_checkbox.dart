import 'package:flutter/material.dart';

import '../../../design_system/cb_tokens.dart';

/// Flat checkbox box shared by [SoftCheckbox] and [SoftCheckboxInline]:
/// a solid accent square when on, a tonal fill square when off — no outline
/// in either state.
BoxDecoration _softCheckboxDecoration(
  BuildContext context, {
  required bool active,
  required double radius,
  Color? activeColor,
}) {
  final theme = Theme.of(context);
  return BoxDecoration(
    shape: BoxShape.rectangle,
    borderRadius: BorderRadius.circular(radius),
    color: active
        ? activeColor ?? theme.colorScheme.primary
        : context.cbColors.fillPressed,
  );
}

/// A soft, rounded checkbox component for better UI/UX
/// Supports 3 states: unchecked, checked, and tristate (indeterminate)
class SoftCheckbox extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  final double size;
  final Color? activeColor;
  final Color? checkColor;
  final bool compact;

  const SoftCheckbox({
    super.key,
    this.value,
    this.onChanged,
    this.tristate = false,
    this.size = 24,
    this.activeColor,
    this.checkColor,
    this.compact = false,
  });

  bool get _isActive => value == true || (value == null && tristate);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveSize = compact ? size - 4 : size;

    return GestureDetector(
      onTap: onChanged != null ? () => _handleTap() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: effectiveSize,
        height: effectiveSize,
        decoration: _softCheckboxDecoration(
          context,
          active: _isActive,
          radius: effectiveSize / 3,
          activeColor: activeColor,
        ),
        child: _buildCheckMark(theme, effectiveSize),
      ),
    );
  }

  void _handleTap() {
    if (tristate) {
      // Cycle: false -> true -> null -> false
      if (value == true) {
        onChanged?.call(null);
      } else {
        onChanged?.call(true);
      }
    } else {
      onChanged?.call!(value != true);
    }
  }

  Widget? _buildCheckMark(ThemeData theme, double effectiveSize) {
    if (value == true) {
      return Center(
        child: Icon(
          Icons.check,
          size: effectiveSize * 0.65,
          color: checkColor ?? theme.colorScheme.onPrimary,
        ),
      );
    }
    if (value == null && tristate) {
      // Indeterminate state - show minus
      return Center(
        child: Container(
          width: effectiveSize * 0.5,
          height: 3,
          decoration: BoxDecoration(
            color: checkColor ?? theme.colorScheme.onPrimary,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      );
    }
    return null;
  }
}

/// A smaller, inline version for use in list items
class SoftCheckboxInline extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  const SoftCheckboxInline({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: _softCheckboxDecoration(
          context,
          active: value,
          radius: size / 3.5,
        ),
        child: value
            ? Center(
                child: Icon(
                  Icons.check,
                  size: size * 0.6,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : null,
      ),
    );
  }
}

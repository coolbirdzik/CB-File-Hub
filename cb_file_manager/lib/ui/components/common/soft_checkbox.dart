import 'package:flutter/material.dart';

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
    Key? key,
    this.value,
    this.onChanged,
    this.tristate = false,
    this.size = 24,
    this.activeColor,
    this.checkColor,
    this.compact = false,
  }) : super(key: key);

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
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(effectiveSize / 3),
          color: _getBackgroundColor(theme),
          border: Border.all(
            color: _getBorderColor(theme),
            width: 2,
          ),
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

  Color _getBackgroundColor(ThemeData theme) {
    if (value == true) {
      return activeColor ?? theme.colorScheme.primary;
    }
    if (value == null && tristate) {
      return activeColor ?? theme.colorScheme.primary;
    }
    return Colors.transparent;
  }

  Color _getBorderColor(ThemeData theme) {
    if (value == true) {
      return activeColor ?? theme.colorScheme.primary;
    }
    if (value == null && tristate) {
      return activeColor ?? theme.colorScheme.primary;
    }
    return theme.colorScheme.outline;
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
    Key? key,
    required this.value,
    this.onChanged,
    this.size = 20,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(size / 3.5),
          color: value ? theme.colorScheme.primary : Colors.transparent,
          border: Border.all(
            color:
                value ? theme.colorScheme.primary : theme.colorScheme.outline,
            width: 1.5,
          ),
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

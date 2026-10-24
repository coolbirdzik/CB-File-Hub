import 'package:cb_file_manager/design_system/primitives/cb_slider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../providers/theme_provider.dart';

/// Shared slider with platform-specific labels, rendering and persistence.
class DesktopBackdropStrengthControl extends StatelessWidget {
  const DesktopBackdropStrengthControl({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final value = themeProvider.desktopBackdropStrength;
    final percentage = (value * 100).round();
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        _BackdropSlider(
          title: themeProvider.usesMacosGlass
              ? l10n.desktopGlassStrength
              : l10n.desktopAcrylicStrength,
          description: themeProvider.usesMacosGlass
              ? l10n.desktopGlassStrengthDescription(percentage)
              : l10n.desktopAcrylicStrengthDescription(percentage),
          value: value,
          onChanged: (nextValue) => themeProvider.setDesktopBackdropStrength(
            nextValue,
            persist: false,
          ),
          onChangeEnd: (nextValue) =>
              themeProvider.setDesktopBackdropStrength(nextValue),
        ),
        if (themeProvider.usesMacosGlass)
          _BackdropSlider(
            title: l10n.desktopGlassBlur,
            description: l10n.desktopGlassBlurDescription(
              (themeProvider.desktopGlassBlurStrength * 100).round(),
            ),
            value: themeProvider.desktopGlassBlurStrength,
            onChanged: (nextValue) => themeProvider.setDesktopGlassBlurStrength(
              nextValue,
              persist: false,
            ),
            onChangeEnd: (nextValue) =>
                themeProvider.setDesktopGlassBlurStrength(nextValue),
          ),
      ],
    );
  }
}

class _BackdropSlider extends StatelessWidget {
  final String title;
  final String description;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BackdropSlider({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Semantics(
            container: true,
            label: title,
            child: CbSlider(
              min: 0,
              max: 2,
              divisions: 20,
              value: value,
              label: '${(value * 100).round()}%',
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

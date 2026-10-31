import 'dart:async';

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
    final glass = themeProvider.usesMacosGlass;
    final scale = glass ? 1.0 : 2.0;
    final value = themeProvider.desktopBackdropStrength / scale;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        _BackdropSlider(
          title: themeProvider.usesMacosGlass
              ? l10n.desktopGlassStrength
              : l10n.desktopAcrylicStrength,
          description: themeProvider.usesMacosGlass
              ? l10n.desktopGlassStrengthDescription
              : l10n.desktopAcrylicStrengthDescription,
          value: value,
          max: glass ? 2 : 1,
          divisions: glass ? 20 : 100,
          previewInterval: glass
              ? Duration.zero
              : const Duration(milliseconds: 80),
          onChanged: (nextValue) => themeProvider.setDesktopBackdropStrength(
            nextValue * scale,
            persist: false,
          ),
          onChangeEnd: (nextValue) =>
              themeProvider.setDesktopBackdropStrength(nextValue * scale),
        ),
        if (themeProvider.usesMacosGlass)
          _BackdropSlider(
            title: l10n.desktopGlassBlur,
            description: l10n.desktopGlassBlurDescription,
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

class _BackdropSlider extends StatefulWidget {
  final String title;
  final String Function(int percentage) description;
  final double value;
  final double max;
  final int divisions;
  final Duration previewInterval;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _BackdropSlider({
    required this.title,
    required this.description,
    required this.value,
    this.max = 2,
    this.divisions = 20,
    this.previewInterval = Duration.zero,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<_BackdropSlider> createState() => _BackdropSliderState();
}

class _BackdropSliderState extends State<_BackdropSlider> {
  double? _dragValue;
  Timer? _previewTimer;
  double? _pendingPreview;

  void _preview(double value) {
    setState(() => _dragValue = value);
    if (widget.previewInterval == Duration.zero) {
      widget.onChanged(value);
      return;
    }
    _pendingPreview = value;
    _previewTimer ??= Timer(widget.previewInterval, () {
      _previewTimer = null;
      final latest = _pendingPreview;
      _pendingPreview = null;
      if (latest != null) widget.onChanged(latest);
    });
  }

  void _commit(double value) {
    _previewTimer?.cancel();
    _previewTimer = null;
    _pendingPreview = null;
    setState(() => _dragValue = null);
    widget.onChangeEnd(value);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            widget.description((value * 100).round()),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Semantics(
            container: true,
            label: widget.title,
            child: CbSlider(
              min: 0,
              max: widget.max,
              divisions: widget.divisions,
              value: value,
              label: '${(value * 100).round()}%',
              onChanged: _preview,
              onChangeEnd: _commit,
            ),
          ),
        ],
      ),
    );
  }
}

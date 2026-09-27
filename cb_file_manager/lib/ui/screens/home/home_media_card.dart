import 'dart:io';

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A library entry point with bounded image decoding and no thumbnail jobs.
class HomeMediaCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> previews;
  final bool video;
  final VoidCallback onPressed;

  const HomeMediaCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.previews,
    required this.onPressed,
    this.video = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return CbPressable(
      onPressed: onPressed,
      semanticLabel: title,
      builder: (context, state) => AnimatedScale(
        scale: reduced ? 1 : (state.pressed ? 0.985 : 1),
        duration: reduced ? Duration.zero : CbDurations.fast,
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : CbDurations.fast,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              cs.primary.withValues(alpha: state.hovered ? 0.10 : 0.04),
              cs.surface.withValues(alpha: 0.65),
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: state.focused ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 132,
                width: double.infinity,
                child: ExcludeSemantics(
                  child: ClipRect(
                    child: AnimatedScale(
                      scale: state.hovered && !reduced ? 1.025 : 1,
                      duration: reduced ? Duration.zero : CbDurations.normal,
                      child: video ? _videoPreview(cs) : _photoPreview(cs),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    PhosphorIconsLight.arrowUpRight,
                    size: 20,
                    color: cs.primary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPreview(ColorScheme cs) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth * 0.46).clamp(70.0, 150.0);
      return Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset((i - 1) * width * 0.60, i == 1 ? -3 : 9),
              child: Transform.rotate(
                angle: (i - 1) * 0.10,
                child: Container(
                  width: width,
                  height: 105,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: _image(
                      i < previews.length ? previews[i] : null,
                      cs,
                      i,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _videoPreview(ColorScheme cs) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _image(previews.firstOrNull, cs, 1),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.90),
              shape: BoxShape.circle,
            ),
            child: Icon(PhosphorIconsFill.play, color: cs.primary, size: 26),
          ),
        ),
      ],
    ),
  );

  Widget _image(String? path, ColorScheme cs, int index) {
    final fallback = ColoredBox(
      color: Color.alphaBlend(
        cs.primary.withValues(alpha: 0.08 + index * 0.035),
        cs.surfaceContainer,
      ),
      child: Center(
        child: Icon(
          video ? PhosphorIconsLight.filmStrip : PhosphorIconsLight.mountains,
          size: 38,
          color: cs.primary.withValues(alpha: 0.45),
        ),
      ),
    );
    if (path == null) return fallback;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: video ? 720 : 320,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

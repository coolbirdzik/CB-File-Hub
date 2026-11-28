import 'package:material_ui/material_ui.dart';

import '../../config/languages/app_localizations.dart';
import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_loading_text.dart';
import 'cb_surface.dart';

/// Keeps Flutter's pull-to-refresh gesture and lifecycle, but uses the same
/// text-based loading treatment as the rest of the application.
class CbRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final double displacement;

  const CbRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 40,
  });

  @override
  State<CbRefreshIndicator> createState() => _CbRefreshIndicatorState();
}

class _CbRefreshIndicatorState extends State<CbRefreshIndicator> {
  RefreshIndicatorStatus? _status;

  @override
  Widget build(BuildContext context) {
    final loading =
        _status == RefreshIndicatorStatus.snap ||
        _status == RefreshIndicatorStatus.refresh;
    final dragging =
        _status == RefreshIndicatorStatus.drag ||
        _status == RefreshIndicatorStatus.armed;
    final l = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: widget.onRefresh,
          onStatusChange: (status) {
            if (mounted && status != _status) setState(() => _status = status);
          },
          child: widget.child,
        ),
        if (loading || dragging)
          Positioned(
            top: (widget.displacement - CbSizes.controlXs / 2).clamp(
              0.0,
              double.infinity,
            ),
            left: CbSpacing.sm,
            right: CbSpacing.sm,
            child: IgnorePointer(
              child: Center(
                child: CbSurface(
                  level: CbSurfaceLevel.overlay,
                  radius: CbRadii.sm,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CbSpacing.md,
                    vertical: CbSpacing.xs,
                  ),
                  child: loading
                      ? CbLoadingText(text: l?.loading)
                      : Text(
                          l?.refresh ?? 'Refresh',
                          style: CbTypography.bodySm.copyWith(
                            color: context.cbColors.textSecondary,
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

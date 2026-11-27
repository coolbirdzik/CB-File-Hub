import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/services/pending_file_deletions.dart';
import 'package:material_ui/material_ui.dart';

/// Rebuilds only when this item's pending state changes, never per progress tick.
class FileDeletionOverlay extends StatefulWidget {
  const FileDeletionOverlay({
    super.key,
    required this.path,
    required this.child,
  });
  final String path;
  final Widget child;

  @override
  State<FileDeletionOverlay> createState() => _FileDeletionOverlayState();
}

class _FileDeletionOverlayState extends State<FileDeletionOverlay> {
  final _pending = PendingFileDeletions.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _busy = _pending.contains(widget.path);
    _pending.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(FileDeletionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _busy = _pending.contains(widget.path);
  }

  void _onChanged() {
    final busy = _pending.contains(widget.path);
    if (busy != _busy) setState(() => _busy = busy);
  }

  @override
  void dispose() {
    _pending.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_busy) return widget.child;
    final colors = Theme.of(context).colorScheme;
    final label =
        AppLocalizations.of(context)?.deletingFiles ?? 'Deleting files…';
    return AbsorbPointer(
      child: ExcludeFocus(
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: Semantics(
                label: label,
                liveRegion: true,
                child: RepaintBoundary(
                  key: ValueKey('deleting-${widget.path}'),
                  child: _DeletionSweep(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paint-only animation: selection, thumbnail layout and loading stay untouched.
class _DeletionSweep extends StatefulWidget {
  const _DeletionSweep({required this.color});
  final Color color;

  @override
  State<_DeletionSweep> createState() => _DeletionSweepState();
}

class _DeletionSweepState extends State<_DeletionSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _animation.value = 0.5;
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: const ValueKey('delete-sweep-paint'),
    painter: _DeletionSweepPainter(animation: _animation, color: widget.color),
  );
}

class _DeletionSweepPainter extends CustomPainter {
  _DeletionSweepPainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(bounds, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(shape);
    // Enter fully from the left, travel across the item, and leave fully right.
    // The wrap happens offscreen so the next pass has no visible backwards jump.
    final bandWidth = size.width;
    final left = -bandWidth + (size.width + bandWidth) * animation.value;
    final band = Rect.fromLTWH(left, 0, bandWidth, size.height);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.20),
            color.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DeletionSweepPainter oldDelegate) =>
      color != oldDelegate.color || animation != oldDelegate.animation;
}

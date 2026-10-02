import 'package:flutter/widgets.dart';

/// Reuses the same widget subtree while a discrete layout value is unchanged.
/// Render objects still receive every new constraint (so resizing stays live),
/// but a one-pixel width change does not recreate a grid's item delegate and
/// all its thumbnails when its column count and item size are unchanged.
class StableLayoutBuilder<T> extends StatefulWidget {
  const StableLayoutBuilder({
    super.key,
    required this.layoutValue,
    required this.builder,
  });

  final T Function(BoxConstraints constraints) layoutValue;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<StableLayoutBuilder<T>> createState() => _StableLayoutBuilderState<T>();
}

class _StableLayoutBuilderState<T> extends State<StableLayoutBuilder<T>> {
  T? _value;
  Widget? _child;

  @override
  void didUpdateWidget(covariant StableLayoutBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An ancestor update can carry new files, selection, or callbacks even
    // when geometry is unchanged. The cache is per widget, never per folder.
    _child = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _child = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final value = widget.layoutValue(constraints);
      if (_child == null || value != _value) {
        _value = value;
        // Use this State's context so inherited changes invalidate the cache.
        _child = widget.builder(context, value);
      }
      return _child!;
    },
  );
}

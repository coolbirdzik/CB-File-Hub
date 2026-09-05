import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class ValueListenableBuilder3<A, B, C> extends StatelessWidget {
  final ValueListenable<A> valueListenable1;
  final ValueListenable<B> valueListenable2;
  final ValueListenable<C> valueListenable3;
  final Widget Function(
    BuildContext context,
    A value1,
    B value2,
    C value3,
    Widget? child,
  )
  builder;
  final Widget? child;

  const ValueListenableBuilder3({
    super.key,
    required this.valueListenable1,
    required this.valueListenable2,
    required this.valueListenable3,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: valueListenable1,
      builder: (context, value1, _) {
        return ValueListenableBuilder<B>(
          valueListenable: valueListenable2,
          builder: (context, value2, _) {
            return ValueListenableBuilder<C>(
              valueListenable: valueListenable3,
              builder: (context, value3, _) =>
                  builder(context, value1, value2, value3, child),
            );
          },
        );
      },
    );
  }
}

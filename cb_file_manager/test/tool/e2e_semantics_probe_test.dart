import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/e2e_semantics_probe.dart';

void main() {
  bool same(int? before, int? after, {String label = 'Close tab'}) =>
      isSameSemanticsSlot(
        oldLabel: 'Close tab',
        newLabel: label,
        oldRect: const Rect.fromLTWH(0, 0, 22, 22),
        newRect: const Rect.fromLTWH(0, 0, 22, 22),
        oldParent: before,
        newParent: after,
      );

  test('identical close buttons in different tabs are not remounts', () {
    expect(same(10, 20), isFalse);
    expect(same(null, null), isFalse);
  });
  test('a replacement in the same surviving parent is still detected', () {
    expect(same(10, 10), isTrue);
    expect(same(10, 10, label: 'Open tab'), isFalse);
  });
}

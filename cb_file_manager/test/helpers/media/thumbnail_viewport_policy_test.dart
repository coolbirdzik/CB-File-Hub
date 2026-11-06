import 'package:cb_file_manager/helpers/media/thumbnail_viewport_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefetch stays around visible items in display order', () {
    final policy = ThumbnailViewportPolicy(nearbyCount: 2);
    final paths = List.generate(1000, (i) => 'video_$i');
    policy.updateDisplayPaths(paths.reversed.toList());
    policy.setVisible('tile', 'video_500');
    expect(policy.wantedPaths, {
      'video_502',
      'video_501',
      'video_500',
      'video_499',
      'video_498',
    });
    policy.setVisible('tile', 'video_10');
    expect(policy.wantedPaths, {
      'video_12',
      'video_11',
      'video_10',
      'video_9',
      'video_8',
    });
    policy.setVisible('tile', null);
    expect(policy.wantedPaths, isEmpty);
  });

  test('duplicate tiles keep interest until both views leave', () {
    final policy = ThumbnailViewportPolicy();
    policy.updateDisplayPaths(['first', 'second', 'third']);
    policy.setVisible('tab-a', 'second');
    policy.setVisible('tab-b', 'second');
    policy.setVisible('tab-a', null);
    expect(policy.wantedPaths, {'first', 'second', 'third'});
    policy.setVisible('tab-b', null);
    expect(policy.wantedPaths, isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';

import '../../tool/e2e_parallel.dart' as runner;

void main() {
  test('Windows app suites can share the parallel phase', () {
    for (final group in [
      '01 Navigation',
      '02 File Operations',
      '11 Extended File Operations',
    ]) {
      expect(
        runner.requiresExclusiveDesktopRun(group, isWindows: true),
        isFalse,
        reason: group,
      );
    }
  });

  test('Windows suites with separate entrypoints build in isolation', () {
    for (final group in [
      'Video Thumbnails',
      'Media Kit Playback',
      'FFmpeg Thumbnails',
      'File Drag Drop',
      'Breadcrumb Overflow',
    ]) {
      expect(
        runner.requiresExclusiveDesktopRun(group, isWindows: true),
        isTrue,
        reason: '$group must not overwrite another Flutter build entrypoint',
      );
    }
  });

  test('torrent keeps exclusive foreground focus on every host', () {
    for (final isWindows in [false, true]) {
      expect(
        runner.requiresExclusiveDesktopRun(
          'Torrent Library',
          isWindows: isWindows,
        ),
        isTrue,
      );
    }
  });

  test('other hosts retain their existing media scheduling', () {
    expect(
      runner.requiresExclusiveDesktopRun('Video Thumbnails', isWindows: false),
      isFalse,
    );
  });
}

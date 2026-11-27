import 'package:cb_file_manager/services/media/subtitle_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SubtitleProgress progress(
    Duration duration,
    List<SubtitleTimeRange> ranges,
  ) => SubtitleProgress(
    phase: SubtitlePhase.ready,
    duration: duration,
    position: Duration.zero,
    completed: ranges,
  );

  test(
    'sub-millisecond duration completes at the persisted timeline precision',
    () {
      expect(
        progress(const Duration(microseconds: 16000500), const [
          SubtitleTimeRange(Duration.zero, Duration(seconds: 16)),
        ]).reachedEnd,
        isTrue,
      );
    },
  );

  test('rounded 100 percent is not completed when a real gap remains', () {
    expect(
      progress(const Duration(seconds: 100), const [
        SubtitleTimeRange(Duration.zero, Duration(seconds: 50)),
        SubtitleTimeRange(
          Duration(milliseconds: 50001),
          Duration(seconds: 100),
        ),
      ]).reachedEnd,
      isFalse,
    );
    expect(
      progress(const Duration(seconds: 100), const [
        SubtitleTimeRange(Duration.zero, Duration(milliseconds: 99999)),
      ]).reachedEnd,
      isFalse,
    );
  });
}

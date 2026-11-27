import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_auto_scaler.dart';
import 'package:cb_file_manager/services/media/subtitle_batch/subtitle_batch_models.dart';
import 'package:cb_file_manager/services/system/system_resources.dart';
import 'package:flutter_test/flutter_test.dart';

const _gb = 1 << 30;

/// Plenty of free memory.
const _roomy = SystemResourceSample(
  ramTotal: 64 * _gb,
  ramAvailable: 40 * _gb,
  vramTotal: 16 * _gb,
  vramUsed: 4 * _gb,
);

void main() {
  group('auto scaler', () {
    late SubtitleBatchAutoScaler scaler;
    late DateTime now;
    var processed = 0;

    setUp(() {
      scaler = SubtitleBatchAutoScaler(
        window: const Duration(seconds: 60),
        warmup: const Duration(seconds: 30),
        holdAfterRevert: const Duration(minutes: 10),
      );
      now = DateTime(2026, 11, 25);
      processed = 0;
    });

    /// Advances time with every running video processing [speed] media
    /// milliseconds per second, updating every 5 s.
    int run(
      Duration time, {
      required double speed,
      int? running,
      bool pending = true,
      SystemResourceSample resources = _roomy,
    }) {
      var limit = scaler.limit;
      for (var t = 0; t < time.inSeconds; t += 5) {
        now = now.add(const Duration(seconds: 5));
        processed += (speed * 5).round();
        limit = scaler.update(
          now: now,
          processedMs: processed,
          running: running ?? limit,
          pending: pending,
          resources: resources,
        );
      }
      return limit;
    }

    test('starts at one video and tries a second', () {
      expect(scaler.limit, 1);
      expect(run(const Duration(seconds: 100), speed: 2000), 2);
      expect(scaler.reason, SubtitleBatchAutoReason.probing);
    });

    test('keeps more videos while they make the queue faster', () {
      run(const Duration(seconds: 100), speed: 2000);
      expect(scaler.limit, 2);
      // Two videos process twice as much media per second.
      run(const Duration(seconds: 95), speed: 4000);
      expect(scaler.limit, 3);
      expect(scaler.baseline, closeTo(4, .2));
    });

    test('goes back when another video is not faster, and waits', () {
      run(const Duration(seconds: 100), speed: 2000);
      expect(scaler.limit, 2);
      // A busy disk: two videos are not faster than one.
      run(const Duration(seconds: 95), speed: 2100);
      expect(scaler.limit, 1);
      expect(scaler.reason, SubtitleBatchAutoReason.noGain);
      run(const Duration(minutes: 9), speed: 2000);
      expect(scaler.limit, 1, reason: 'held after the revert');
      run(const Duration(minutes: 2), speed: 2000);
      expect(scaler.limit, 2, reason: 'tries again later');
      expect(scaler.reason, SubtitleBatchAutoReason.probing);
    });

    test('does not add videos without free memory', () {
      const tight = SystemResourceSample(
        ramTotal: 64 * _gb,
        ramAvailable: 2 * _gb,
        vramTotal: 16 * _gb,
        vramUsed: 15 * _gb,
      );
      expect(run(const Duration(minutes: 5), speed: 2000, resources: tight), 1);
      expect(scaler.reason, SubtitleBatchAutoReason.lowMemory);
    });

    test('drops a video when memory runs out while running', () {
      run(const Duration(seconds: 100), speed: 2000);
      run(const Duration(seconds: 95), speed: 4000);
      expect(scaler.limit, 3);
      const full = SystemResourceSample(
        ramTotal: 64 * _gb,
        ramAvailable: 40 * _gb,
        vramTotal: 16 * _gb,
        vramUsed: 16 * _gb - (100 << 20),
      );
      run(const Duration(seconds: 5), speed: 4000, resources: full);
      expect(scaler.limit, 2);
      expect(scaler.reason, SubtitleBatchAutoReason.lowMemory);
    });

    test('a read timeout lowers the limit', () {
      run(const Duration(seconds: 100), speed: 2000);
      expect(scaler.limit, 2);
      scaler.onTransientFailure(now, processed);
      expect(scaler.limit, 1);
      expect(scaler.reason, SubtitleBatchAutoReason.failures);
    });

    test('adds nothing while slots are free or nothing waits', () {
      expect(run(const Duration(minutes: 3), speed: 2000, pending: false), 1);
      expect(run(const Duration(minutes: 3), speed: 2000, running: 0), 1);
    });

    test('the model loading time is not measured', () {
      // Nothing is processed during the warm-up, then full speed.
      run(const Duration(seconds: 30), speed: 0);
      run(const Duration(seconds: 65), speed: 2000);
      expect(scaler.baseline, closeTo(2, .2));
    });
  });

  group('failure', () {
    test('raw messages map to a kind', () {
      for (final (message, kind) in [
        ('Bad state: Audio read failed', SubtitleBatchFailureKind.slowRead),
        ('Bad state: Audio read timed out', SubtitleBatchFailureKind.slowRead),
        (
          'Bad state: Cannot open media audio',
          SubtitleBatchFailureKind.slowRead,
        ),
        (
          'Bad state: Audio read timed out: Cannot inspect audio streams: Immediate exit requested',
          SubtitleBatchFailureKind.slowRead,
        ),
        (
          'Cannot open media audio: Invalid data found when processing input',
          SubtitleBatchFailureKind.unreadable,
        ),
        (
          'Cannot open media audio: No such file or directory',
          SubtitleBatchFailureKind.fileMissing,
        ),
        ('File not found', SubtitleBatchFailureKind.fileMissing),
        ('Cannot read the video duration', SubtitleBatchFailureKind.unreadable),
        (
          'Bad state: Selected audio track is unavailable',
          SubtitleBatchFailureKind.noAudio,
        ),
        (
          'Bad state: Subtitle runtime exited',
          SubtitleBatchFailureKind.runtimeCrashed,
        ),
        (
          '${SubtitleBatchFailure.stalledIdle} 97%',
          SubtitleBatchFailureKind.stalledIdle,
        ),
        (
          '${SubtitleBatchFailure.stalledSlow} 40% (translating)',
          SubtitleBatchFailureKind.stalledSlow,
        ),
        ('something odd', SubtitleBatchFailureKind.unknown),
        (null, SubtitleBatchFailureKind.unknown),
      ]) {
        expect(SubtitleBatchFailure.kind(message), kind, reason: message);
      }
    });

    test(
      'recoverable I/O failures and stalls are retried, invalid files are not',
      () {
        expect(SubtitleBatchFailure.transient('Audio read failed'), isTrue);
        expect(
          SubtitleBatchFailure.transient('Subtitle runtime exited'),
          isTrue,
        );
        expect(SubtitleBatchFailure.transient('File not found'), isFalse);
        expect(
          SubtitleBatchFailure.transient(
            '${SubtitleBatchFailure.stalledIdle} 9%',
          ),
          isTrue,
        );
        expect(
          SubtitleBatchFailure.transient(
            '${SubtitleBatchFailure.stalledSlow} 40%',
          ),
          isTrue,
        );
        expect(
          SubtitleBatchFailure.transient('Cannot open media audio'),
          isTrue,
        );
        expect(
          SubtitleBatchFailure.transient(
            'Cannot open media audio: Invalid data found when processing input',
          ),
          isFalse,
        );
      },
    );

    test('details drop the exception prefix', () {
      expect(
        SubtitleBatchFailure.detail('Bad state: Audio read failed'),
        'Audio read failed',
      );
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/media/lossless_cut_service.dart';
import 'package:cb_file_manager/services/media/source_file_timestamps.dart';
import 'package:crypto/crypto.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ranges reject zero, reversed and out-of-bounds cuts', () {
    const total = Duration(seconds: 8);
    expect(
      const VideoCutSegment(Duration.zero, total).isValidFor(total),
      isTrue,
    );
    for (final cut in [
      const VideoCutSegment(Duration.zero, Duration.zero),
      const VideoCutSegment(Duration(seconds: 4), Duration(seconds: 2)),
      const VideoCutSegment(Duration(seconds: -1), total),
      const VideoCutSegment(Duration.zero, Duration(seconds: 9)),
    ]) {
      expect(cut.isValidFor(total), isFalse);
    }
  });

  test(
    'stream copy seeks before input, preserves tracks and never overwrites',
    () {
      final args = LosslessCutService.cutArguments(
        input: "C:/video's/đầu vào.mkv",
        output: 'out.mkv',
        segment: const VideoCutSegment(
          Duration(milliseconds: 1250),
          Duration(seconds: 3),
        ),
      );
      expect(args.indexOf('-ss'), lessThan(args.indexOf('-i')));
      expect(args[args.indexOf('-ss') + 1], '1.250000');
      expect(args[args.indexOf('-t') + 1], '1.750000');
      expect(args[args.indexOf('-c') + 1], 'copy');
      expect(args[args.indexOf('-map') + 1], '0');
      expect(args, contains('-n'));
      expect(args, isNot(contains('-y')));
    },
  );

  test(
    'numbered output names retain the source basename and selected container',
    () {
      expect(
        LosslessCutService.segmentFileName(
          p.join('videos', "phim's đêm.MKV"),
          1,
        ),
        "phim's đêm_1.mkv",
      );
      expect(
        LosslessCutService.segmentFileName('sample.mkv', 12, container: 'mp4'),
        'sample_12.mp4',
      );
    },
  );

  final ffmpeg =
      Platform.environment['CB_TEST_FFMPEG'] ??
      p.join(Directory.current.path, 'windows', 'ffmpeg', 'bin', 'ffmpeg.exe');
  final ffprobe = p.join(
    p.dirname(ffmpeg),
    Platform.isWindows ? 'ffprobe.exe' : 'ffprobe',
  );
  final hasRuntime = File(ffmpeg).existsSync() && File(ffprobe).existsSync();

  for (final useNativeProcess in [false, true]) {
    group(
      'real FFmpeg export (${useNativeProcess ? 'Rust' : 'Dart'})',
      () {
        late Directory sandbox;
        late Directory destination;
        late String input;
        late String originalHash;

        Future<ProcessResult> run(String executable, List<String> args) async {
          final result = await Process.run(executable, args);
          expect(result.exitCode, 0, reason: result.stderr.toString());
          return result;
        }

        Future<Map<String, dynamic>> probe(String file) async {
          final result = await run(ffprobe, [
            '-v',
            'error',
            '-show_streams',
            '-show_format',
            '-of',
            'json',
            file,
          ]);
          return jsonDecode(result.stdout as String) as Map<String, dynamic>;
        }

        if (useNativeProcess) {
          test(
            'native process job is supported by the loaded library',
            () async {
              final process = NativeMediaProcess.start(
                executable: ffmpeg,
                arguments: ['-version'],
                duration: const Duration(seconds: 1),
              );
              expect(process, isNotNull);
              expect((await process!.result())!.exitCode, 0);
            },
          );
        }

        if (useNativeProcess) {
          test(
            'native cancellation releases output handles before returning',
            () async {
              final output = File(p.join(destination.path, 'cancel.mkv'));
              final process = NativeMediaProcess.start(
                executable: ffmpeg,
                arguments: [
                  '-nostdin',
                  '-loglevel',
                  'error',
                  '-re',
                  '-f',
                  'lavfi',
                  '-i',
                  'testsrc2=size=16x16:rate=25',
                  '-c:v',
                  'libx264',
                  '-preset',
                  'ultrafast',
                  '-progress',
                  'pipe:1',
                  output.path,
                ],
                duration: const Duration(seconds: 30),
              );
              expect(process, isNotNull);
              final timer = Timer(
                const Duration(milliseconds: 300),
                process!.cancel,
              );
              try {
                expect(
                  await process.result().timeout(const Duration(seconds: 5)),
                  isNull,
                );
                if (await output.exists()) await output.delete();
                expect(await output.exists(), isFalse);
              } finally {
                timer.cancel();
                process.cancel();
              }
            },
          );
        }

        setUp(() async {
          sandbox = await Directory.systemTemp.createTemp(
            "CB-cut-đường dẫn's-",
          );
          destination = await Directory(
            p.join(sandbox.path, 'output'),
          ).create();
          input = p.join(sandbox.path, 'source.mkv');
          final subtitles = File(p.join(sandbox.path, 'subtitles.srt'));
          await subtitles.writeAsString(
            '1\n00:00:01,000 --> 00:00:06,000\nSubtitle track\n',
          );
          await run(ffmpeg, [
            '-hide_banner',
            '-loglevel',
            'error',
            '-nostdin',
            '-f',
            'lavfi',
            '-i',
            'testsrc2=size=96x64:rate=25:duration=8',
            '-f',
            'lavfi',
            '-i',
            'sine=frequency=440:duration=8',
            '-i',
            subtitles.path,
            '-map',
            '0',
            '-map',
            '1',
            '-map',
            '2',
            '-c:v',
            'libx264',
            '-threads',
            '1',
            '-g',
            '25',
            '-bf',
            '0',
            '-sc_threshold',
            '0',
            '-c:a',
            'aac',
            '-c:s',
            'srt',
            '-metadata',
            'title=Original title',
            input,
          ]);
          originalHash = sha256
              .convert(await File(input).readAsBytes())
              .toString();
        });

        tearDown(() async {
          expect(
            sha256.convert(await File(input).readAsBytes()).toString(),
            originalHash,
          );
          await sandbox.delete(recursive: true);
        });

        const cuts = [
          VideoCutSegment(Duration(milliseconds: 1250), Duration(seconds: 3)),
          VideoCutSegment(Duration(milliseconds: 4250), Duration(seconds: 6)),
        ];

        for (final createSubfolder in [false, true]) {
          for (final merge in [false, true]) {
            test(
              'source dates survive final publication (subfolder=$createSubfolder, merge=$merge)',
              () async {
                await File(
                  input,
                ).setLastModified(DateTime.utc(2019, 3, 4, 5, 6, 7));
                final sourceDates = await SourceFileTimestamps.capture(input);
                final outputs =
                    await LosslessCutService(
                      useNativeProcess: useNativeProcess,
                    ).export(
                      executable: ffmpeg,
                      input: input,
                      destination: createSubfolder
                          ? destination.path
                          : sandbox.path,
                      duration: const Duration(seconds: 8),
                      segments: cuts,
                      merge: merge,
                      createSubfolder: createSubfolder,
                      timestampMode: VideoCutTimestampMode.sourceTime,
                    );
                expect(outputs, hasLength(merge ? 1 : 2));
                for (final output in outputs) {
                  final dates = await SourceFileTimestamps.capture(output);
                  expect(dates.modified, sourceDates.modified);
                  if (Platform.isWindows) {
                    expect(dates.created, sourceDates.created);
                  }
                }
                final after = await SourceFileTimestamps.capture(input);
                expect(after.modified, sourceDates.modified);
                expect(after.created, sourceDates.created);
              },
            );
          }
        }

        test('default mode uses fresh dates instead of source dates', () async {
          await File(input).setLastModified(DateTime.utc(2019, 3, 4));
          final before = DateTime.now().subtract(const Duration(seconds: 2));
          final outputs =
              await LosslessCutService(
                useNativeProcess: useNativeProcess,
              ).export(
                executable: ffmpeg,
                input: input,
                destination: sandbox.path,
                duration: const Duration(seconds: 8),
                segments: cuts,
                createSubfolder: false,
              );
          for (final output in outputs) {
            expect((await File(output).lastModified()).isAfter(before), isTrue);
          }
        });

        test(
          'exports separate clips with original packet data, audio and metadata',
          () async {
            final progress = <double>[];
            final outputs =
                await LosslessCutService(
                  useNativeProcess: useNativeProcess,
                ).export(
                  executable: ffmpeg,
                  input: input,
                  destination: destination.path,
                  duration: const Duration(seconds: 8),
                  segments: cuts,
                  onProgress: progress.add,
                );
            expect(outputs, hasLength(2));
            expect(outputs.map(p.basename), ['source_1.mkv', 'source_2.mkv']);
            for (final file in outputs) {
              final data = await probe(file);
              expect((data['streams'] as List).map((s) => s['codec_name']), [
                'h264',
                'aac',
              ]);
              expect(data['format']['tags']['title'], 'Original title');
              expect(
                double.parse(data['format']['duration'] as String),
                closeTo(2, 0.4),
              );
              await run(ffmpeg, [
                '-v',
                'error',
                '-i',
                file,
                '-map',
                '0:v',
                '-map',
                '0:a',
                '-f',
                'null',
                '-',
              ]);
            }
            Future<List<String>> hashes(String file) async {
              final result = await run(ffprobe, [
                '-v',
                'error',
                '-select_streams',
                'v:0',
                '-show_packets',
                '-show_data_hash',
                'sha256',
                '-show_entries',
                'packet=data_hash',
                '-of',
                'json',
                file,
              ]);
              final packets =
                  (jsonDecode(result.stdout as String)['packets'] as List);
              return packets
                  .map((packet) => packet['data_hash'] as String)
                  .toList();
            }

            final originalPackets = (await hashes(input)).toSet();
            for (final output in outputs) {
              final exportedPackets = await hashes(output);
              expect(exportedPackets, isNotEmpty);
              expect(exportedPackets.every(originalPackets.contains), isTrue);
            }
            expect(progress.last, 1);
            expect(progress, orderedEquals([...progress]..sort()));
          },
        );

        test(
          'batch export preserves Unicode basenames in numbered output files',
          () async {
            input = (await File(
              input,
            ).rename(p.join(sandbox.path, "phim's đêm.mkv"))).path;
            final outputs =
                await LosslessCutService(
                  useNativeProcess: useNativeProcess,
                ).export(
                  executable: ffmpeg,
                  input: input,
                  destination: destination.path,
                  duration: const Duration(seconds: 8),
                  segments: cuts,
                );
            expect(outputs.map(p.basename), [
              "phim's đêm_1.mkv",
              "phim's đêm_2.mkv",
            ]);
            expect(await Directory(p.dirname(outputs.first)).list().length, 2);
            for (final output in outputs) {
              expect(await File(output).exists(), isTrue);
            }
          },
        );

        test(
          'in-place batch saves beside the source without leaving a subfolder',
          () async {
            final before = (await sandbox.list().toList())
                .map((entry) => entry.path)
                .toSet();
            final outputs =
                await LosslessCutService(
                  useNativeProcess: useNativeProcess,
                ).export(
                  executable: ffmpeg,
                  input: input,
                  destination: sandbox.path,
                  duration: const Duration(seconds: 8),
                  segments: cuts,
                  createSubfolder: false,
                );
            expect(outputs.map(p.dirname).toSet(), {sandbox.path});
            expect(outputs.map(p.basename), ['source_1.mkv', 'source_2.mkv']);
            final after = (await sandbox.list().toList())
                .map((entry) => entry.path)
                .toSet();
            expect(after.difference(before), outputs.toSet());
            for (final output in outputs) {
              expect((await probe(output))['streams'], hasLength(2));
            }
          },
        );

        test(
          'in-place export skips existing files and folders without overwriting',
          () async {
            final existing = File(p.join(sandbox.path, 'source_1.mkv'));
            await existing.writeAsString('existing export');
            final existingFolder = await Directory(
              p.join(sandbox.path, 'source_2.mkv'),
            ).create();
            final outputs =
                await LosslessCutService(
                  useNativeProcess: useNativeProcess,
                ).export(
                  executable: ffmpeg,
                  input: input,
                  destination: sandbox.path,
                  duration: const Duration(seconds: 8),
                  segments: cuts,
                  createSubfolder: false,
                );
            expect(outputs.map(p.basename), ['source_3.mkv', 'source_4.mkv']);
            expect(await existing.readAsString(), 'existing export');
            expect(await existingFolder.exists(), isTrue);
          },
        );

        test(
          'in-place joined export uses a source-based name and keeps earlier exports',
          () async {
            final service = LosslessCutService(
              useNativeProcess: useNativeProcess,
            );
            Future<List<String>> export() => service.export(
              executable: ffmpeg,
              input: input,
              destination: sandbox.path,
              duration: const Duration(seconds: 8),
              segments: cuts,
              merge: true,
              createSubfolder: false,
            );
            final first = await export();
            final firstHash = sha256
                .convert(await File(first.single).readAsBytes())
                .toString();
            final second = await export();
            expect(p.basename(first.single), 'source_merged.mkv');
            expect(p.basename(second.single), 'source_merged_1.mkv');
            expect(
              sha256.convert(await File(first.single).readAsBytes()).toString(),
              firstHash,
            );
            expect((await probe(second.single))['streams'], hasLength(2));
          },
        );

        test(
          'cancelled in-place export removes its staging files and preserves neighbours',
          () async {
            final existing = File(p.join(sandbox.path, 'source_1.mkv'));
            await existing.writeAsString('keep this');
            final before = (await sandbox.list().toList())
                .map((entry) => entry.path)
                .toSet();
            final service = LosslessCutService(
              useNativeProcess: useNativeProcess,
            );
            await expectLater(
              service.export(
                executable: ffmpeg,
                input: input,
                destination: sandbox.path,
                duration: const Duration(seconds: 8),
                segments: cuts,
                createSubfolder: false,
                onProgress: (_) => service.cancel(),
              ),
              throwsA(isA<LosslessCutCancelled>()),
            );
            final after = (await sandbox.list().toList())
                .map((entry) => entry.path)
                .toSet();
            expect(after, before);
            expect(await existing.readAsString(), 'keep this');
          },
        );

        test(
          'concurrent in-place exports reserve distinct output names',
          () async {
            Future<List<String>> export() =>
                LosslessCutService(useNativeProcess: useNativeProcess).export(
                  executable: ffmpeg,
                  input: input,
                  destination: sandbox.path,
                  duration: const Duration(seconds: 8),
                  segments: cuts,
                  createSubfolder: false,
                );
            final results = await Future.wait([export(), export()]);
            final outputs = results.expand((result) => result).toList();
            expect(outputs.toSet(), hasLength(4));
            expect(outputs.map(p.basename).toSet(), {
              'source_1.mkv',
              'source_2.mkv',
              'source_3.mkv',
              'source_4.mkv',
            });
            expect(
              await sandbox
                  .list()
                  .where(
                    (entry) => p.basename(entry.path).startsWith('CB-cuts-'),
                  )
                  .length,
              0,
            );
          },
        );

        test(
          'joins segments from paths containing accents and apostrophes',
          () async {
            final outputs =
                await LosslessCutService(
                  useNativeProcess: useNativeProcess,
                ).export(
                  executable: ffmpeg,
                  input: input,
                  destination: destination.path,
                  duration: const Duration(seconds: 8),
                  segments: cuts,
                  merge: true,
                );
            expect(outputs, hasLength(1));
            final data = await probe(outputs.single);
            expect(
              double.parse(data['format']['duration'] as String),
              closeTo(4, 0.6),
            );
            expect((data['streams'] as List).map((s) => s['codec_name']), [
              'h264',
              'aac',
            ]);
            expect(await Directory(p.dirname(outputs.single)).list().length, 1);
            await run(ffmpeg, [
              '-v',
              'error',
              '-i',
              outputs.single,
              '-map',
              '0:v',
              '-map',
              '0:a',
              '-f',
              'null',
              '-',
            ]);
          },
        );

        test(
          'embedded subtitles are retained only when explicitly requested',
          () async {
            final outputs =
                await LosslessCutService(
                  useNativeProcess: useNativeProcess,
                ).export(
                  executable: ffmpeg,
                  input: input,
                  destination: destination.path,
                  duration: const Duration(seconds: 8),
                  segments: [cuts.first],
                  includeSubtitles: true,
                );
            final data = await probe(outputs.single);
            expect(
              (data['streams'] as List).map((stream) => stream['codec_name']),
              ['h264', 'aac', 'subrip'],
            );
            // A stream-copied subtitle packet keeps its original cue duration.
            expect(
              double.parse(data['format']['duration'] as String),
              greaterThan(2),
            );
          },
        );

        test(
          'unsupported track/container fails visibly and removes partial outputs',
          () async {
            await expectLater(
              LosslessCutService(useNativeProcess: useNativeProcess).export(
                executable: ffmpeg,
                input: input,
                destination: destination.path,
                duration: const Duration(seconds: 8),
                segments: cuts,
                container: 'mp4',
                includeSubtitles: true,
              ),
              throwsA(isA<ProcessException>()),
            );
            expect(await destination.list().length, 0);
          },
        );

        test(
          'cancellation cleans its outputs and a later export can reuse the service',
          () async {
            final service = LosslessCutService(
              useNativeProcess: useNativeProcess,
            );
            await expectLater(
              service.export(
                executable: ffmpeg,
                input: input,
                destination: destination.path,
                duration: const Duration(seconds: 8),
                segments: cuts,
                onProgress: (_) => service.cancel(),
              ),
              throwsA(isA<LosslessCutCancelled>()),
            );
            expect(await destination.list().length, 0);
            final first = await service.export(
              executable: ffmpeg,
              input: input,
              destination: destination.path,
              duration: const Duration(seconds: 8),
              segments: [cuts.first],
            );
            final second = await service.export(
              executable: ffmpeg,
              input: input,
              destination: destination.path,
              duration: const Duration(seconds: 8),
              segments: [cuts.first],
            );
            expect(first.single, isNot(second.single));
            expect(await File(first.single).exists(), isTrue);
          },
        );

        test(
          'invalid ranges and startup failures leave destination untouched',
          () async {
            final service = LosslessCutService(
              useNativeProcess: useNativeProcess,
            );
            await expectLater(
              service.export(
                executable: ffmpeg,
                input: input,
                destination: destination.path,
                duration: const Duration(seconds: 8),
                segments: [],
              ),
              throwsArgumentError,
            );
            await expectLater(
              service.export(
                executable: p.join(sandbox.path, 'missing.exe'),
                input: input,
                destination: destination.path,
                duration: const Duration(seconds: 8),
                segments: cuts,
              ),
              throwsA(isA<ProcessException>()),
            );
            expect(await destination.list().length, 0);
          },
        );
      },
      skip: !hasRuntime
          ? 'Set CB_TEST_FFMPEG to a runtime with ffprobe to run media export checks.'
          : useNativeProcess && !CbNative.isAvailable
          ? 'Rust library not built'
          : false,
    );
  }
}

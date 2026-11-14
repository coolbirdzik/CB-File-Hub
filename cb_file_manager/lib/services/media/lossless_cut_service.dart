import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:cb_native/cb_native.dart';

import '../local_ai/windows_process_reaper.dart';
import 'source_file_timestamps.dart';

enum VideoCutTimestampMode { exportTime, sourceTime }

class VideoCutSegment {
  final Duration start;
  final Duration end;

  const VideoCutSegment(this.start, this.end);

  Duration get duration => end - start;

  bool isValidFor(Duration total) =>
      start >= Duration.zero && end > start && end <= total;
}

class LosslessCutCancelled implements Exception {
  const LosslessCutCancelled();
}

/// One export at a time. Every stream is copied; no encoder is selected.
/// Each export owns a fresh staging directory and, for direct output, only
/// the final paths it reserved exclusively. Failures remove only those files.
class LosslessCutService {
  LosslessCutService({this.useNativeProcess = true});

  final bool useNativeProcess;
  NativeMediaProcess? _nativeProcess;
  Process? _process;
  bool _cancelled = false;
  bool _running = false;

  void cancel() {
    _cancelled = true;
    _nativeProcess?.cancel();
    _process?.kill();
  }

  static String timestamp(Duration value) =>
      (value.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(
        6,
      );

  static String segmentFileName(String input, int number, {String? container}) {
    final extension =
        container ?? p.extension(input).replaceFirst('.', '').toLowerCase();
    return '${p.basenameWithoutExtension(input)}_$number.$extension';
  }

  static List<String> cutArguments({
    required String input,
    required String output,
    required VideoCutSegment segment,
    bool includeSubtitles = false,
  }) => [
    '-hide_banner', '-nostdin', '-loglevel', 'error', '-n',
    '-ss', timestamp(segment.start), '-i', input,
    '-t', timestamp(segment.duration),
    '-map', '0',
    if (!includeSubtitles) ...['-map', '-0:s?'],
    '-c', 'copy', '-map_metadata', '0',
    // Source chapters refer to the original timeline.
    '-map_chapters', '-1', '-avoid_negative_ts', 'make_zero',
    '-progress', 'pipe:1', '-nostats', output,
  ];

  /// Windows ships the CLI with the same shared libraries as thumbnails.
  /// macOS/Linux may use an installed FFmpeg or a user-selected executable.
  static Future<String?> findExecutable() async {
    final executableName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final appDirectory = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      p.join(appDirectory, 'ffmpeg', executableName),
      p.join(appDirectory, executableName),
      if (Platform.isMacOS) ...[
        '/opt/homebrew/bin/ffmpeg',
        '/usr/local/bin/ffmpeg',
      ],
      for (final directory in (Platform.environment['PATH'] ?? '').split(
        Platform.isWindows ? ';' : ':',
      ))
        if (directory.isNotEmpty) p.join(directory, executableName),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  Future<List<String>> export({
    required String executable,
    required String input,
    required String destination,
    required Duration duration,
    required List<VideoCutSegment> segments,
    bool merge = false,
    // False publishes directly into destination, choosing free suffixes.
    bool createSubfolder = true,
    bool includeSubtitles = false,
    VideoCutTimestampMode timestampMode = VideoCutTimestampMode.exportTime,
    String? container,
    void Function(double progress)? onProgress,
  }) async {
    if (_running) throw StateError('An export is already running.');
    final cuts = List<VideoCutSegment>.of(segments);
    if (cuts.isEmpty || cuts.any((segment) => !segment.isValidFor(duration))) {
      throw ArgumentError('Invalid video segments.');
    }
    final extension =
        container ?? p.extension(input).replaceFirst('.', '').toLowerCase();
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(extension)) {
      throw ArgumentError('Unsupported output extension.');
    }
    _running = true;
    _cancelled = false;
    Directory? outputDirectory;
    final publishedFiles = <File>[];
    try {
      if (!await File(input).exists()) {
        throw ArgumentError('Source file is missing.');
      }
      if (!await Directory(destination).exists()) {
        throw ArgumentError('Output folder is missing.');
      }
      final sourceTimes = timestampMode == VideoCutTimestampMode.sourceTime
          ? await SourceFileTimestamps.capture(input)
          : null;
      _checkCancelled();
      // createTemp atomically allocates a unique name even for concurrent players.
      outputDirectory = await Directory(destination).createTemp('CB-cuts-');
      final totalUs = cuts.fold<int>(
        0,
        (sum, cut) => sum + cut.duration.inMicroseconds,
      );
      final willMerge = merge && cuts.length > 1;
      final workUs = totalUs * (willMerge ? 2 : 1);
      var completedUs = 0;
      final outputs = <String>[];
      for (var index = 0; index < cuts.length; index++) {
        _checkCancelled();
        final output = p.join(
          outputDirectory.path,
          'segment-${(index + 1).toString().padLeft(3, '0')}.$extension',
        );
        await _run(
          executable,
          cutArguments(
            input: p.absolute(input),
            output: output,
            segment: cuts[index],
            includeSubtitles: includeSubtitles,
          ),
          duration: cuts[index].duration,
          onProgress: (progress) => onProgress?.call(
            (completedUs + progress * cuts[index].duration.inMicroseconds) /
                workUs,
          ),
        );
        if (!await File(output).exists() || await File(output).length() == 0) {
          throw StateError('FFmpeg produced an empty segment.');
        }
        outputs.add(output);
        completedUs += cuts[index].duration.inMicroseconds;
      }
      if (willMerge) {
        final manifest = File(
          p.join(outputDirectory.path, 'segments.ffconcat'),
        );
        // Only generated ASCII basenames enter the manifest, never user paths.
        await manifest.writeAsString(
          'ffconcat version 1.0\n${outputs.map((file) => "file '${p.basename(file)}'").join('\n')}\n',
        );
        final merged = p.join(outputDirectory.path, 'merged.$extension');
        await _run(
          executable,
          [
            '-hide_banner',
            '-nostdin',
            '-loglevel',
            'error',
            '-n',
            '-f',
            'concat',
            '-safe',
            '1',
            '-i',
            manifest.path,
            '-map',
            '0',
            '-c',
            'copy',
            '-map_metadata',
            '0',
            '-map_chapters',
            '-1',
            '-avoid_negative_ts',
            'make_zero',
            '-progress',
            'pipe:1',
            '-nostats',
            merged,
          ],
          duration: Duration(microseconds: totalUs),
          onProgress: (progress) =>
              onProgress?.call((totalUs + progress * totalUs) / workUs),
        );
        if (!await File(merged).exists() || await File(merged).length() == 0) {
          throw StateError('FFmpeg produced an empty video.');
        }
        _checkCancelled();
        for (final output in outputs) {
          await File(output).delete();
        }
        await manifest.delete();
        outputs
          ..clear()
          ..add(merged);
      } else {
        for (var index = 0; index < outputs.length; index++) {
          _checkCancelled();
          final namedOutput = p.join(
            outputDirectory.path,
            segmentFileName(input, index + 1, container: extension),
          );
          outputs[index] = (await File(
            outputs[index],
          ).rename(namedOutput)).path;
        }
      }
      if (!createSubfolder) {
        // Reserve destination names atomically. Rename only over our own empty
        // reservation; never let File.rename replace a pre-existing user file.
        var nextNumber = 1;
        final published = <String>[];
        for (final output in outputs) {
          File reserved;
          while (true) {
            _checkCancelled();
            final name = willMerge
                ? '${p.basenameWithoutExtension(input)}_merged${nextNumber == 1 ? '' : '_${nextNumber - 1}'}.$extension'
                : segmentFileName(input, nextNumber, container: extension);
            nextNumber++;
            reserved = File(p.join(p.absolute(destination), name));
            try {
              await reserved.create(exclusive: true);
              publishedFiles.add(reserved);
              break;
            } on FileSystemException {
              if (await FileSystemEntity.type(
                    reserved.path,
                    followLinks: false,
                  ) ==
                  FileSystemEntityType.notFound) {
                rethrow;
              }
            }
          }
          _checkCancelled();
          await File(output).rename(reserved.path);
          published.add(reserved.path);
        }
        await outputDirectory.delete(recursive: true);
        outputs
          ..clear()
          ..addAll(published);
      }
      _checkCancelled();
      // Set dates after final rename: Windows may restore cached creation times
      // when a name is replaced, including our exclusively owned reservation.
      await sourceTimes?.applyTo(outputs);
      _checkCancelled();
      onProgress?.call(1);
      return outputs;
    } catch (error, stack) {
      // This exact directory was allocated above; input and existing outputs
      // are never touched, including when cancellation races process startup.
      final cleanupErrors = <Object>[];
      for (final file in publishedFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (cleanupError) {
          cleanupErrors.add(cleanupError);
        }
      }
      try {
        if (outputDirectory != null && await outputDirectory.exists()) {
          await outputDirectory.delete(recursive: true);
        }
      } catch (cleanupError) {
        cleanupErrors.add(cleanupError);
      }
      if (cleanupErrors.isNotEmpty) {
        throw FileSystemException(
          'Export failed: $error. Cleanup failed: ${cleanupErrors.join('; ')}',
          destination,
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      _process = null;
      _running = false;
    }
  }

  void _checkCancelled() {
    if (_cancelled) throw const LosslessCutCancelled();
  }

  Future<void> _run(
    String executable,
    List<String> arguments, {
    required Duration duration,
    required void Function(double) onProgress,
  }) async {
    _checkCancelled();
    final native = useNativeProcess
        ? NativeMediaProcess.start(
            executable: executable,
            arguments: arguments,
            duration: duration,
          )
        : null;
    if (native != null) {
      _nativeProcess = native;
      if (_cancelled) native.cancel();
      try {
        final result = await native.result(onProgress: onProgress);
        _checkCancelled();
        if (result == null) throw const LosslessCutCancelled();
        if (result.exitCode != 0) {
          throw ProcessException(
            executable,
            arguments,
            result.diagnostic,
            result.exitCode,
          );
        }
        onProgress(1);
        return;
      } on NativeJobException catch (error) {
        throw ProcessException(executable, arguments, error.message);
      } finally {
        _nativeProcess = null;
      }
    }
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
    );
    _process = process;
    if (Platform.isWindows) {
      WindowsProcessReaper.instance.assignProcess(
        process.pid,
        background: true,
      );
    }
    if (_cancelled) process.kill();
    var diagnostic = '';
    var lastProgress = 0.0;
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach((chunk) {
          diagnostic += chunk;
          if (diagnostic.length > 16000) {
            diagnostic = diagnostic.substring(diagnostic.length - 16000);
          }
        });
    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          if (!line.startsWith('out_time_us=')) return;
          final microseconds = int.tryParse(
            line.substring('out_time_us='.length),
          );
          if (microseconds == null) return;
          final progress = (microseconds / duration.inMicroseconds).clamp(
            lastProgress,
            1.0,
          );
          lastProgress = progress;
          onProgress(progress);
        });
    final exitCode = await process.exitCode;
    await Future.wait([stderrDone, stdoutDone]);
    _process = null;
    _checkCancelled();
    if (exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        diagnostic.trim(),
        exitCode,
      );
    }
    onProgress(1);
  }
}

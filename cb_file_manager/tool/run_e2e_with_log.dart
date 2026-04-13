// Runs `flutter test` for desktop E2E, mirrors output to build/e2e_last_run.log (or JSON log),
// then runs e2e_summarize_failures.dart on non-zero exit. Used by Makefile on Windows (no bash).

import 'dart:io';

/// Matches [windows/CMakeLists.txt] BINARY_NAME — kill stray instances before E2E
/// (file locks, duplicate windows) when `dart run tool/run_e2e_with_log.dart` is used without `make`.
Future<void> _killCbFileHubOnWindows() async {
  if (!Platform.isWindows) return;
  final r = await Process.run(
    'taskkill',
    <String>['/F', '/IM', 'cb_file_hub.exe', '/T'],
    runInShell: false,
  );
  // 0 = processes terminated; 128 = not found — both OK.
  if (r.exitCode != 0 && r.exitCode != 128) {
    stderr.writeln(
      '[E2E] taskkill cb_file_hub.exe exit ${r.exitCode} (continuing)',
    );
  }
}

Future<void> main(List<String> args) async {
  await _killCbFileHubOnWindows();

  final jsonReport = args.contains('--json-report');
  final fullStartup = args.contains('--full-startup');
  final fullScreenshots = args.contains('--full-screenshots');
  final passthrough = args
      .where((a) =>
          a != '--json-report' &&
          a != '--full-startup' &&
          a != '--full-screenshots')
      .toList();

  final device = Platform.environment['E2E_DEVICE'] ?? 'windows';
  final reporter = jsonReport
      ? 'json'
      : (Platform.environment['TEST_REPORTER'] ?? 'expanded');

  final logRelative =
      jsonReport ? 'build/e2e_report.jsonl' : 'build/e2e_last_run.log';
  final logFile = File(logRelative);
  await logFile.parent.create(recursive: true);
  final logSink = logFile.openWrite();

  final flutterArgs = <String>[
    'test',
    'integration_test/app_e2e_test.dart',
    '-d',
    device,
    '--dart-define=CB_E2E=true',
    '--dart-define=CB_E2E_FAST=${!fullStartup}',
    '--dart-define=CB_E2E_FULL_SCREENSHOTS=$fullScreenshots',
    '--reporter',
    reporter,
    ...passthrough,
  ];

  final proc = await Process.start(
    'flutter',
    flutterArgs,
    mode: ProcessStartMode.normal,
    runInShell: true,
  );

  Future<void> drain(Stream<List<int>> input, IOSink human) async {
    await for (final chunk in input) {
      human.add(chunk);
      logSink.add(chunk);
    }
  }

  await Future.wait<void>([
    drain(proc.stdout, stdout),
    drain(proc.stderr, stderr),
  ]);

  final code = await proc.exitCode;
  await logSink.close();

  if (code != 0) {
    final sum = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'run',
        'tool/e2e_summarize_failures.dart',
        logRelative,
      ],
      workingDirectory: Directory.current.path,
    );
    final out = sum.stdout;
    final err = sum.stderr;
    if (out != null && '$out'.isNotEmpty) {
      stdout.write(out);
    }
    if (err != null && '$err'.isNotEmpty) {
      stderr.write(err);
    }
  }

  exit(code);
}

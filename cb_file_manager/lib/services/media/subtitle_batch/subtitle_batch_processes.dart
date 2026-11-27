import 'dart:async';
import 'dart:io';

/// Only processes started explicitly for batch subtitles are registered here.
/// Keep them until OS exit, including workers replaced during GPU fallback.
class SubtitleBatchProcesses {
  static final instance = SubtitleBatchProcesses();
  final _processes = <int, Process>{};

  List<int> get ids => _processes.keys.toList()..sort();

  void register(Process process) {
    _processes[process.pid] = process;
    unawaited(
      process.exitCode.then((_) {
        if (identical(_processes[process.pid], process)) {
          _processes.remove(process.pid);
        }
      }),
    );
  }
}

import 'dart:math';

import 'package:flutter/foundation.dart';

const int _defaultFinishedHistoryLimit = 20;
const Duration _defaultFinishedRetention = Duration(minutes: 5);

enum OperationProgressStatus { running, success, error }

enum OperationProgressKind {
  generic,
  copy,
  move,
  delete,
  scan,
  thumbnail,
  tag,
  network,
}

@immutable
class OperationProgressEntry {
  final String id;
  final String title;
  final String? detail;
  final int total;
  final int completed;
  final OperationProgressStatus status;
  final bool isMinimized;
  final bool isIndeterminate;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final OperationProgressKind kind;
  final bool canCancel;
  final VoidCallback? cancelAction;
  final String? sourcePath;
  final String? destinationPath;
  final int? bytesTotal;
  final int? bytesCompleted;
  final bool showInStatusCenter;

  const OperationProgressEntry({
    required this.id,
    required this.title,
    required this.total,
    required this.completed,
    required this.status,
    required this.isMinimized,
    required this.isIndeterminate,
    required this.startedAt,
    this.finishedAt,
    this.detail,
    this.kind = OperationProgressKind.generic,
    this.canCancel = false,
    this.cancelAction,
    this.sourcePath,
    this.destinationPath,
    this.bytesTotal,
    this.bytesCompleted,
    this.showInStatusCenter = true,
  });

  double get progressFraction {
    if (isIndeterminate) return 0;
    if (bytesTotal != null && bytesTotal! > 0) {
      return ((bytesCompleted ?? 0) / bytesTotal!).clamp(0.0, 1.0);
    }
    if (total <= 0) return 0;
    return (completed / total).clamp(0.0, 1.0);
  }

  bool get isRunning => status == OperationProgressStatus.running;
  bool get isFinished => status != OperationProgressStatus.running;

  OperationProgressEntry copyWith({
    String? title,
    String? detail,
    int? total,
    int? completed,
    OperationProgressStatus? status,
    bool? isMinimized,
    bool? isIndeterminate,
    DateTime? finishedAt,
    bool clearDetail = false,
    OperationProgressKind? kind,
    bool? canCancel,
    VoidCallback? cancelAction,
    bool clearCancelAction = false,
    String? sourcePath,
    bool clearSourcePath = false,
    String? destinationPath,
    bool clearDestinationPath = false,
    int? bytesTotal,
    bool clearBytesTotal = false,
    int? bytesCompleted,
    bool clearBytesCompleted = false,
    bool? showInStatusCenter,
  }) {
    return OperationProgressEntry(
      id: id,
      title: title ?? this.title,
      detail: clearDetail ? null : (detail ?? this.detail),
      total: total ?? this.total,
      completed: completed ?? this.completed,
      status: status ?? this.status,
      isMinimized: isMinimized ?? this.isMinimized,
      isIndeterminate: isIndeterminate ?? this.isIndeterminate,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      kind: kind ?? this.kind,
      canCancel: canCancel ?? this.canCancel,
      cancelAction: clearCancelAction
          ? null
          : (cancelAction ?? this.cancelAction),
      sourcePath: clearSourcePath ? null : (sourcePath ?? this.sourcePath),
      destinationPath: clearDestinationPath
          ? null
          : (destinationPath ?? this.destinationPath),
      bytesTotal: clearBytesTotal ? null : (bytesTotal ?? this.bytesTotal),
      bytesCompleted: clearBytesCompleted
          ? null
          : (bytesCompleted ?? this.bytesCompleted),
      showInStatusCenter: showInStatusCenter ?? this.showInStatusCenter,
    );
  }
}

@immutable
class OperationAggregateProgress {
  final bool hasRunning;
  final bool hasError;
  final bool isIndeterminate;
  final double? fraction;
  final int runningCount;

  const OperationAggregateProgress({
    required this.hasRunning,
    required this.hasError,
    required this.isIndeterminate,
    required this.fraction,
    required this.runningCount,
  });

  static const idle = OperationAggregateProgress(
    hasRunning: false,
    hasError: false,
    isIndeterminate: false,
    fraction: null,
    runningCount: 0,
  );
}

/// Global Status Center controller for app-wide foreground/background work.
class OperationProgressController extends ChangeNotifier {
  final int finishedHistoryLimit;
  final Duration finishedRetention;
  final Map<String, OperationProgressEntry> _entriesById = {};
  final Set<String> _seenEntryIds = <String>{};
  int _sequence = 0;

  OperationProgressController({
    this.finishedHistoryLimit = _defaultFinishedHistoryLimit,
    this.finishedRetention = _defaultFinishedRetention,
  });

  OperationProgressEntry? get active {
    for (final entry in runningEntries) {
      if (!entry.isMinimized) return entry;
    }
    return runningEntries.isNotEmpty ? runningEntries.first : null;
  }

  List<OperationProgressEntry> get entries {
    final visible = _entriesById.values
        .where((entry) => entry.showInStatusCenter)
        .toList(growable: false);
    visible.sort(_compareEntries);
    return visible;
  }

  List<OperationProgressEntry> get runningEntries =>
      entries.where((entry) => entry.isRunning).toList(growable: false);

  List<OperationProgressEntry> get finishedEntries =>
      entries.where((entry) => entry.isFinished).toList(growable: false);

  List<OperationProgressEntry> get unseenEntries => entries
      .where((entry) => !_seenEntryIds.contains(entry.id))
      .toList(growable: false);

  int get unseenCount => unseenEntries.length;

  int get runningCount => runningEntries.length;

  OperationAggregateProgress get aggregateProgress {
    final running = runningEntries;
    if (running.isEmpty) {
      final hasRecentError = finishedEntries.any(
        (entry) => entry.status == OperationProgressStatus.error,
      );
      return OperationAggregateProgress(
        hasRunning: false,
        hasError: hasRecentError,
        isIndeterminate: false,
        fraction: null,
        runningCount: 0,
      );
    }

    final hasError = running.any(
      (entry) => entry.status == OperationProgressStatus.error,
    );
    final determinate = running.where((entry) => !entry.isIndeterminate);
    final hasIndeterminate = running.any((entry) => entry.isIndeterminate);
    var completed = 0;
    var total = 0;
    for (final entry in determinate) {
      if (entry.bytesTotal != null && entry.bytesTotal! > 0) {
        completed += entry.bytesCompleted ?? 0;
        total += entry.bytesTotal!;
      } else if (entry.total > 0) {
        completed += entry.completed;
        total += entry.total;
      }
    }

    final fraction = total > 0 ? (completed / total).clamp(0.0, 1.0) : null;
    return OperationAggregateProgress(
      hasRunning: true,
      hasError: hasError,
      isIndeterminate: fraction == null || hasIndeterminate,
      fraction: fraction,
      runningCount: running.length,
    );
  }

  String begin({
    required String title,
    required int total,
    String? detail,
    bool isIndeterminate = false,
    bool showModal = false,
    OperationProgressKind kind = OperationProgressKind.generic,
    bool canCancel = false,
    VoidCallback? cancelAction,
    String? sourcePath,
    String? destinationPath,
    int? bytesTotal,
    int? bytesCompleted,
    bool showInStatusCenter = true,
  }) {
    final id = _newId();
    _entriesById[id] = OperationProgressEntry(
      id: id,
      title: title,
      detail: detail,
      total: max(0, total),
      completed: 0,
      status: OperationProgressStatus.running,
      isMinimized: !showModal,
      isIndeterminate: isIndeterminate,
      startedAt: DateTime.now(),
      kind: kind,
      canCancel: canCancel,
      cancelAction: cancelAction,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      bytesTotal: bytesTotal == null ? null : max(0, bytesTotal),
      bytesCompleted: bytesCompleted == null ? null : max(0, bytesCompleted),
      showInStatusCenter: showInStatusCenter,
    );
    _pruneFinished();
    notifyListeners();
    return id;
  }

  void update(
    String id, {
    int? completed,
    String? detail,
    int? total,
    bool? isIndeterminate,
    int? bytesTotal,
    int? bytesCompleted,
  }) {
    final current = _entriesById[id];
    if (current == null || !current.isRunning) return;

    final nextCompleted = completed == null
        ? current.completed
        : max(0, completed);
    final nextTotal = total == null ? current.total : max(0, total);
    final nextBytesTotal = bytesTotal == null
        ? current.bytesTotal
        : max(0, bytesTotal);
    final nextBytesCompleted = bytesCompleted == null
        ? current.bytesCompleted
        : max(0, bytesCompleted);

    _entriesById[id] = current.copyWith(
      completed: min(nextCompleted, nextTotal == 0 ? nextCompleted : nextTotal),
      total: nextTotal,
      detail: detail,
      isIndeterminate: isIndeterminate,
      bytesTotal: nextBytesTotal,
      bytesCompleted: nextBytesTotal == null || nextBytesTotal == 0
          ? nextBytesCompleted
          : min(nextBytesCompleted ?? 0, nextBytesTotal),
    );
    notifyListeners();
  }

  void succeed(String id, {String? detail}) {
    final current = _entriesById[id];
    if (current == null) return;

    _entriesById[id] = current.copyWith(
      completed: current.total == 0 ? current.completed : current.total,
      bytesCompleted: current.bytesTotal,
      status: OperationProgressStatus.success,
      detail: detail,
      finishedAt: DateTime.now(),
    );
    _pruneFinished();
    notifyListeners();
  }

  void fail(String id, {String? detail}) {
    final current = _entriesById[id];
    if (current == null) return;

    _entriesById[id] = current.copyWith(
      status: OperationProgressStatus.error,
      detail: detail,
      finishedAt: DateTime.now(),
    );
    _pruneFinished();
    notifyListeners();
  }

  void minimize([String? id]) {
    _setMinimized(id ?? active?.id, true);
  }

  void show([String? id]) {
    _setMinimized(id ?? active?.id, false);
  }

  void dismiss([String? id]) {
    final targetId = id ?? active?.id;
    if (targetId == null) return;
    if (_entriesById.remove(targetId) == null) return;
    _seenEntryIds.remove(targetId);
    notifyListeners();
  }

  void dismissFinished() {
    final ids = _entriesById.entries
        .where((entry) => entry.value.isFinished)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (ids.isEmpty) return;
    for (final id in ids) {
      _entriesById.remove(id);
      _seenEntryIds.remove(id);
    }
    notifyListeners();
  }

  void markAllSeen() {
    final oldCount = _seenEntryIds.length;
    _seenEntryIds.addAll(entries.map((entry) => entry.id));
    if (_seenEntryIds.length == oldCount) return;
    notifyListeners();
  }

  void cancel(String id) {
    final entry = _entriesById[id];
    if (entry == null || !entry.canCancel) return;
    entry.cancelAction?.call();
  }

  void _setMinimized(String? id, bool value) {
    if (id == null) return;
    final current = _entriesById[id];
    if (current == null || current.isMinimized == value) return;
    _entriesById[id] = current.copyWith(isMinimized: value);
    notifyListeners();
  }

  int _compareEntries(OperationProgressEntry a, OperationProgressEntry b) {
    if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
    if (a.isRunning) return b.startedAt.compareTo(a.startedAt);
    final aFinished = a.finishedAt ?? a.startedAt;
    final bFinished = b.finishedAt ?? b.startedAt;
    return bFinished.compareTo(aFinished);
  }

  void _pruneFinished() {
    final now = DateTime.now();
    final expired = _entriesById.entries
        .where(
          (entry) =>
              entry.value.isFinished &&
              entry.value.finishedAt != null &&
              now.difference(entry.value.finishedAt!) > finishedRetention,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in expired) {
      _entriesById.remove(id);
      _seenEntryIds.remove(id);
    }

    final finished =
        _entriesById.values
            .where((entry) => entry.isFinished)
            .toList(growable: false)
          ..sort((a, b) {
            final aFinished = a.finishedAt ?? a.startedAt;
            final bFinished = b.finishedAt ?? b.startedAt;
            return bFinished.compareTo(aFinished);
          });
    if (finished.length <= finishedHistoryLimit) return;
    for (final entry in finished.skip(finishedHistoryLimit)) {
      _entriesById.remove(entry.id);
      _seenEntryIds.remove(entry.id);
    }
  }

  String _newId() {
    _sequence = (_sequence + 1) & 0xFFFFFFFF;
    return '${DateTime.now().microsecondsSinceEpoch}-${_rand32()}-$_sequence';
  }

  int _rand32() {
    final v = DateTime.now().microsecondsSinceEpoch;
    return (v ^ (v >> 16)) & 0xFFFFFFFF;
  }
}

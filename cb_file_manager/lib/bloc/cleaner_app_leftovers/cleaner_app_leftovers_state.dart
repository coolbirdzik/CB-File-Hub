import 'package:equatable/equatable.dart';

import '../../helpers/core/text_utils.dart';
import '../../services/app_insights/app_leftover_finder.dart';
import '../../services/app_insights/app_leftover_scanner.dart';

enum CleanerAppLeftoversStatus { idle, loading, ready, failure }

/// Zero shows folders regardless of activity.
const List<int> cleanerLeftoverInactiveDayPresets = <int>[0, 90, 180, 365];

const int defaultCleanerLeftoverInactiveDays = 90;

/// Measured folders smaller than this are not worth listing.
const int cleanerLeftoverMinimumBytes = 1024 * 1024;

const Object _notSet = Object();

class CleanerAppLeftoversState extends Equatable {
  final CleanerAppLeftoversStatus status;

  /// Discovered folders. Each is listed once [measurements] has its entry.
  final AppLeftoverReport? report;
  final Map<String, AppLeftoverMeasurement> measurements;

  /// Folders are still being measured.
  final bool isScanning;
  final String searchQuery;
  final int inactiveDays;
  final Set<String> selectedPaths;
  final DateTime evaluatedAt;
  final String? errorMessage;

  CleanerAppLeftoversState({
    required this.evaluatedAt,
    this.status = CleanerAppLeftoversStatus.idle,
    this.report,
    this.measurements = const <String, AppLeftoverMeasurement>{},
    this.isScanning = false,
    this.searchQuery = '',
    this.inactiveDays = defaultCleanerLeftoverInactiveDays,
    this.selectedPaths = const <String>{},
    this.errorMessage,
  });

  final _Memo _memo = _Memo();

  int get totalCount => report?.candidates.length ?? 0;

  int get measuredCount => measurements.length;

  /// Measured folders above the size floor, largest first, with their
  /// measured size.
  List<AppLeftoverCandidate> get measuredCandidates {
    final cached = _memo.measured;
    if (cached != null) return cached;
    final measured = <AppLeftoverCandidate>[
      for (final candidate
          in report?.candidates ?? const <AppLeftoverCandidate>[])
        if (measurements[candidate.path] case final measurement?)
          if (measurement.sizeBytes >= cleanerLeftoverMinimumBytes)
            candidate.withMeasurement(
              sizeBytes: measurement.sizeBytes,
              fileCount: measurement.fileCount,
              isPartial: candidate.isPartial || !measurement.isComplete,
            ),
    ]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return _memo.measured = List<AppLeftoverCandidate>.unmodifiable(measured);
  }

  List<AppLeftoverCandidate> get visibleCandidates {
    final cached = _memo.visible;
    if (cached != null) return cached;
    final query = TextUtils.normalizeForSearch(searchQuery.trim());
    final visible = measuredCandidates
        .where((candidate) {
          if (isHiddenByActivity(candidate)) return false;
          if (query.isEmpty) return true;
          return TextUtils.normalizeForSearch(
            '${candidate.displayName}\n${candidate.path}\n'
            '${candidate.relatedAppName ?? ''}',
          ).contains(query);
        })
        .toList(growable: false);
    return _memo.visible = List<AppLeftoverCandidate>.unmodifiable(visible);
  }

  bool isHiddenByActivity(AppLeftoverCandidate candidate) {
    if (inactiveDays <= 0) return false;
    final last = measurements[candidate.path]?.lastModified;
    if (last == null) return false;
    return evaluatedAt.difference(last) < Duration(days: inactiveDays);
  }

  int get hiddenByActivityCount {
    if (inactiveDays <= 0) return 0;
    return measuredCandidates.where(isHiddenByActivity).length;
  }

  int get visibleBytes =>
      visibleCandidates.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  List<AppLeftoverCandidate> get selectedCandidates => visibleCandidates
      .where((candidate) => selectedPaths.contains(candidate.path))
      .toList(growable: false);

  int get selectedBytes =>
      selectedCandidates.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  CleanerAppLeftoversState copyWith({
    CleanerAppLeftoversStatus? status,
    Object? report = _notSet,
    Map<String, AppLeftoverMeasurement>? measurements,
    bool? isScanning,
    String? searchQuery,
    int? inactiveDays,
    Set<String>? selectedPaths,
    DateTime? evaluatedAt,
    Object? errorMessage = _notSet,
  }) {
    final next = CleanerAppLeftoversState(
      status: status ?? this.status,
      report: identical(report, _notSet)
          ? this.report
          : report as AppLeftoverReport?,
      measurements: measurements ?? this.measurements,
      isScanning: isScanning ?? this.isScanning,
      searchQuery: searchQuery ?? this.searchQuery,
      inactiveDays: inactiveDays ?? this.inactiveDays,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      errorMessage: identical(errorMessage, _notSet)
          ? this.errorMessage
          : errorMessage as String?,
    );
    if (identical(next.report, this.report) &&
        identical(next.measurements, this.measurements)) {
      next._memo.measured = _memo.measured;
      if (next.searchQuery == this.searchQuery &&
          next.inactiveDays == this.inactiveDays &&
          next.evaluatedAt == this.evaluatedAt) {
        next._memo.visible = _memo.visible;
      }
    }
    return next;
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    report,
    measurements,
    isScanning,
    searchQuery,
    inactiveDays,
    selectedPaths,
    evaluatedAt,
    errorMessage,
  ];
}

class _Memo {
  List<AppLeftoverCandidate>? measured;
  List<AppLeftoverCandidate>? visible;
}

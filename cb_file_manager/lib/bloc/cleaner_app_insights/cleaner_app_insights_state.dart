import 'package:equatable/equatable.dart';

import '../../services/app_insights/app_insights_models.dart';

enum CleanerAppInsightsStatus { idle, loading, ready, failure }

enum CleanerAppFilter { all, attention, large, stale, cleanable }

enum CleanerAppSort {
  attentionDescending,
  sizeDescending,
  nameAscending,
  lastOpenedOldest,
}

const List<int> cleanerAppLargeThresholdPresets = <int>[
  500 * 1024 * 1024,
  1024 * 1024 * 1024,
  5 * 1024 * 1024 * 1024,
];

const List<int> cleanerAppStaleDayPresets = <int>[90, 180, 365];

const int defaultCleanerAppLargeThresholdBytes = 1024 * 1024 * 1024;
const int defaultCleanerAppStaleThresholdDays = 180;

const Object _notSet = Object();

class CleanerAppInsightsState extends Equatable {
  final CleanerAppInsightsStatus status;
  final AppStorageReport? report;
  final String searchQuery;
  final CleanerAppFilter filter;
  final CleanerAppSort sort;
  final int largeThresholdBytes;
  final int staleThresholdDays;
  final String? selectedAppId;
  final DateTime evaluatedAt;
  final String? errorMessage;

  CleanerAppInsightsState({
    required this.evaluatedAt,
    this.status = CleanerAppInsightsStatus.idle,
    this.report,
    this.searchQuery = '',
    this.filter = CleanerAppFilter.all,
    this.sort = CleanerAppSort.attentionDescending,
    this.largeThresholdBytes = defaultCleanerAppLargeThresholdBytes,
    this.staleThresholdDays = defaultCleanerAppStaleThresholdDays,
    this.selectedAppId,
    this.errorMessage,
  });

  // Filtering/sorting scans every app (and every entry path when searching),
  // so the result is computed once per state instead of once per read: the
  // UI touches these getters several times during a single rebuild.
  final _Memo _memo = _Memo();

  List<AppStorageProfile> get visibleApps {
    final cached = _memo.visibleApps;
    if (cached != null) return cached;
    final currentReport = report;
    final computed = currentReport == null
        ? const <AppStorageProfile>[]
        : filterAndSortAppProfiles(
            profiles: currentReport.apps,
            searchQuery: searchQuery,
            filter: filter,
            sort: sort,
            largeThresholdBytes: largeThresholdBytes,
            staleThresholdDays: staleThresholdDays,
            evaluatedAt: evaluatedAt,
          );
    return _memo.visibleApps = computed;
  }

  _AppCounters get _appCounters {
    final cached = _memo.counters;
    if (cached != null) return cached;
    var large = 0;
    var stale = 0;
    var attention = 0;
    var attentionSize = 0;
    final staleThreshold = Duration(days: staleThresholdDays);
    for (final profile in report?.apps ?? const <AppStorageProfile>[]) {
      final isLarge = profile.bestKnownSizeBytes >= largeThresholdBytes;
      final isStale = profile.isStale(
        now: evaluatedAt,
        threshold: staleThreshold,
      );
      if (isLarge) large++;
      if (isStale) stale++;
      if (isLarge && isStale) {
        attention++;
        attentionSize += profile.bestKnownSizeBytes;
      }
    }
    return _memo.counters = _AppCounters(
      large,
      stale,
      attention,
      attentionSize,
    );
  }

  AppStorageProfile? get selectedProfile {
    final appId = selectedAppId;
    if (appId == null) return null;
    return report?.findApp(appId);
  }

  int get largeAppCount => _appCounters.large;

  int get staleAppCount => _appCounters.stale;

  int get attentionAppCount => _appCounters.attention;

  int get attentionBytes => _appCounters.attentionBytes;

  CleanerAppInsightsState copyWith({
    CleanerAppInsightsStatus? status,
    Object? report = _notSet,
    String? searchQuery,
    CleanerAppFilter? filter,
    CleanerAppSort? sort,
    int? largeThresholdBytes,
    int? staleThresholdDays,
    Object? selectedAppId = _notSet,
    DateTime? evaluatedAt,
    Object? errorMessage = _notSet,
  }) {
    final next = CleanerAppInsightsState(
      status: status ?? this.status,
      report: identical(report, _notSet)
          ? this.report
          : report as AppStorageReport?,
      searchQuery: searchQuery ?? this.searchQuery,
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
      largeThresholdBytes: largeThresholdBytes ?? this.largeThresholdBytes,
      staleThresholdDays: staleThresholdDays ?? this.staleThresholdDays,
      selectedAppId: identical(selectedAppId, _notSet)
          ? this.selectedAppId
          : selectedAppId as String?,
      evaluatedAt: evaluatedAt ?? this.evaluatedAt,
      errorMessage: identical(errorMessage, _notSet)
          ? this.errorMessage
          : errorMessage as String?,
    );

    // Selection-only changes leave the filtered list identical, so hand the
    // memoized results over instead of recomputing them.
    if (identical(next.report, this.report) &&
        next.searchQuery == this.searchQuery &&
        next.filter == this.filter &&
        next.sort == this.sort &&
        next.largeThresholdBytes == this.largeThresholdBytes &&
        next.staleThresholdDays == this.staleThresholdDays &&
        next.evaluatedAt == this.evaluatedAt) {
      next._memo.visibleApps = _memo.visibleApps;
      next._memo.counters = _memo.counters;
    }
    return next;
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    report,
    searchQuery,
    filter,
    sort,
    largeThresholdBytes,
    staleThresholdDays,
    selectedAppId,
    evaluatedAt,
    errorMessage,
  ];
}

List<AppStorageProfile> filterAndSortAppProfiles({
  required Iterable<AppStorageProfile> profiles,
  required String searchQuery,
  required CleanerAppFilter filter,
  required CleanerAppSort sort,
  required int largeThresholdBytes,
  required int staleThresholdDays,
  required DateTime evaluatedAt,
}) {
  final normalizedQuery = searchQuery.trim().toLowerCase();
  final staleThreshold = Duration(days: staleThresholdDays);

  final result = profiles
      .where((profile) {
        if (normalizedQuery.isNotEmpty &&
            !_matchesSearch(profile, normalizedQuery)) {
          return false;
        }

        switch (filter) {
          case CleanerAppFilter.all:
            return true;
          case CleanerAppFilter.attention:
            return appNeedsAttention(
              profile,
              evaluatedAt: evaluatedAt,
              largeThresholdBytes: largeThresholdBytes,
              staleThresholdDays: staleThresholdDays,
            );
          case CleanerAppFilter.large:
            return profile.bestKnownSizeBytes >= largeThresholdBytes;
          case CleanerAppFilter.stale:
            return profile.isStale(now: evaluatedAt, threshold: staleThreshold);
          case CleanerAppFilter.cleanable:
            return profile.cleanableBytes > 0;
        }
      })
      .toList(growable: false);

  result.sort((left, right) {
    int comparison;
    switch (sort) {
      case CleanerAppSort.attentionDescending:
        final leftAttention = appNeedsAttention(
          left,
          evaluatedAt: evaluatedAt,
          largeThresholdBytes: largeThresholdBytes,
          staleThresholdDays: staleThresholdDays,
        );
        final rightAttention = appNeedsAttention(
          right,
          evaluatedAt: evaluatedAt,
          largeThresholdBytes: largeThresholdBytes,
          staleThresholdDays: staleThresholdDays,
        );
        comparison = (rightAttention ? 1 : 0).compareTo(leftAttention ? 1 : 0);
        if (comparison == 0) {
          comparison = right.bestKnownSizeBytes.compareTo(
            left.bestKnownSizeBytes,
          );
        }
        break;
      case CleanerAppSort.sizeDescending:
        comparison = right.bestKnownSizeBytes.compareTo(
          left.bestKnownSizeBytes,
        );
        break;
      case CleanerAppSort.nameAscending:
        comparison = left.app.displayName.toLowerCase().compareTo(
          right.app.displayName.toLowerCase(),
        );
        break;
      case CleanerAppSort.lastOpenedOldest:
        comparison = _compareLastOpened(left, right);
        break;
    }

    if (comparison != 0) return comparison;
    comparison = left.app.displayName.toLowerCase().compareTo(
      right.app.displayName.toLowerCase(),
    );
    if (comparison != 0) return comparison;
    return left.app.id.compareTo(right.app.id);
  });

  return List<AppStorageProfile>.unmodifiable(result);
}

bool appNeedsAttention(
  AppStorageProfile profile, {
  required DateTime evaluatedAt,
  required int largeThresholdBytes,
  required int staleThresholdDays,
}) {
  return profile.bestKnownSizeBytes >= largeThresholdBytes &&
      profile.isStale(
        now: evaluatedAt,
        threshold: Duration(days: staleThresholdDays),
      );
}

/// Mutable memo holder so the state object itself stays all-final.
class _Memo {
  List<AppStorageProfile>? visibleApps;
  _AppCounters? counters;
}

class _AppCounters {
  final int large;
  final int stale;
  final int attention;
  final int attentionBytes;

  const _AppCounters(
    this.large,
    this.stale,
    this.attention,
    this.attentionBytes,
  );
}

// Lowercasing every searchable field of every app on each keystroke is what
// made typing stutter; the haystack only depends on the profile, so it is
// built once and kept alive as long as the profile is.
final Expando<String> _searchHaystacks = Expando<String>('appSearchHaystack');

String _searchHaystack(AppStorageProfile profile) {
  final cached = _searchHaystacks[profile];
  if (cached != null) return cached;
  final app = profile.app;
  final buffer = StringBuffer()
    ..write(app.displayName)
    ..write('\n')
    ..write(app.publisher ?? '')
    ..write('\n')
    ..write(app.version ?? '')
    ..write('\n')
    ..write(app.installLocation ?? '')
    ..write('\n')
    ..write(app.packageFamilyName ?? '');
  for (final entry in profile.entries) {
    buffer
      ..write('\n')
      ..write(entry.path);
  }
  final haystack = buffer.toString().toLowerCase();
  _searchHaystacks[profile] = haystack;
  return haystack;
}

bool _matchesSearch(AppStorageProfile profile, String normalizedQuery) {
  return _searchHaystack(profile).contains(normalizedQuery);
}

int _compareLastOpened(AppStorageProfile left, AppStorageProfile right) {
  final leftDate = left.usage.lastOpenedAt;
  final rightDate = right.usage.lastOpenedAt;
  if (leftDate == null && rightDate == null) return 0;
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  return leftDate.compareTo(rightDate);
}

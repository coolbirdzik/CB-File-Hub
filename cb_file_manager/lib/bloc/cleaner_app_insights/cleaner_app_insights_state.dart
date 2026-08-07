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

  const CleanerAppInsightsState({
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

  List<AppStorageProfile> get visibleApps {
    final currentReport = report;
    if (currentReport == null) return const <AppStorageProfile>[];
    return filterAndSortAppProfiles(
      profiles: currentReport.apps,
      searchQuery: searchQuery,
      filter: filter,
      sort: sort,
      largeThresholdBytes: largeThresholdBytes,
      staleThresholdDays: staleThresholdDays,
      evaluatedAt: evaluatedAt,
    );
  }

  AppStorageProfile? get selectedProfile {
    final appId = selectedAppId;
    if (appId == null) return null;
    return report?.findApp(appId);
  }

  int get largeAppCount =>
      report?.apps
          .where((profile) => profile.bestKnownSizeBytes >= largeThresholdBytes)
          .length ??
      0;

  int get staleAppCount =>
      report?.apps
          .where(
            (profile) => profile.isStale(
              now: evaluatedAt,
              threshold: Duration(days: staleThresholdDays),
            ),
          )
          .length ??
      0;

  int get attentionAppCount =>
      report?.apps
          .where(
            (profile) => appNeedsAttention(
              profile,
              evaluatedAt: evaluatedAt,
              largeThresholdBytes: largeThresholdBytes,
              staleThresholdDays: staleThresholdDays,
            ),
          )
          .length ??
      0;

  int get attentionBytes =>
      report?.apps
          .where(
            (profile) => appNeedsAttention(
              profile,
              evaluatedAt: evaluatedAt,
              largeThresholdBytes: largeThresholdBytes,
              staleThresholdDays: staleThresholdDays,
            ),
          )
          .fold<int>(
            0,
            (total, profile) => total + profile.bestKnownSizeBytes,
          ) ??
      0;

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
    return CleanerAppInsightsState(
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

  final result = profiles.where((profile) {
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
        return profile.isStale(
          now: evaluatedAt,
          threshold: staleThreshold,
        );
      case CleanerAppFilter.cleanable:
        return profile.cleanableBytes > 0;
    }
  }).toList(growable: false);

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
        comparison = (rightAttention ? 1 : 0).compareTo(
          leftAttention ? 1 : 0,
        );
        if (comparison == 0) {
          comparison =
              right.bestKnownSizeBytes.compareTo(left.bestKnownSizeBytes);
        }
        break;
      case CleanerAppSort.sizeDescending:
        comparison =
            right.bestKnownSizeBytes.compareTo(left.bestKnownSizeBytes);
        break;
      case CleanerAppSort.nameAscending:
        comparison = left.app.displayName
            .toLowerCase()
            .compareTo(right.app.displayName.toLowerCase());
        break;
      case CleanerAppSort.lastOpenedOldest:
        comparison = _compareLastOpened(left, right);
        break;
    }

    if (comparison != 0) return comparison;
    comparison = left.app.displayName
        .toLowerCase()
        .compareTo(right.app.displayName.toLowerCase());
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

bool _matchesSearch(AppStorageProfile profile, String normalizedQuery) {
  final app = profile.app;
  final values = <String?>[
    app.displayName,
    app.publisher,
    app.version,
    app.installLocation,
    app.packageFamilyName,
    ...profile.entries.map((entry) => entry.path),
  ];
  return values.any(
    (value) => value?.toLowerCase().contains(normalizedQuery) ?? false,
  );
}

int _compareLastOpened(
  AppStorageProfile left,
  AppStorageProfile right,
) {
  final leftDate = left.usage.lastOpenedAt;
  final rightDate = right.usage.lastOpenedAt;
  if (leftDate == null && rightDate == null) return 0;
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  return leftDate.compareTo(rightDate);
}

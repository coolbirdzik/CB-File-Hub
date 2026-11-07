import 'package:equatable/equatable.dart';

import '../../services/disk_cleaner/cleaner_installed_apps.dart';
import '../../services/disk_cleaner/cleaner_item_origin.dart';
import '../../services/disk_cleaner/cleaner_models.dart';
import '../../services/disk_cleaner/cleaner_paths.dart';
import '../../services/disk_cleaner/cleaner_review_candidates.dart';

enum CleanerSmartCleanStatus { idle, scanning, ready, cleaning, done, failure }

/// Why a Smart Clean scan could not produce results.
enum CleanerSmartCleanError { busy, failed }

/// Files in one group that the same app made and that are the same kind of
/// thing, shown as one row with its own checkbox.
class CleanerSmartCleanSource extends Equatable {
  /// Unique within its group.
  final String key;

  final CleanerItemOrigin origin;

  /// Largest first.
  final List<JunkItem> items;

  final int bytes;

  /// Smaller sources folded into this one; 0 for an ordinary source.
  final int mergedCount;

  CleanerSmartCleanSource({
    required this.key,
    required this.origin,
    required List<JunkItem> items,
    this.mergedCount = 0,
  }) : items = List.unmodifiable(
         [...items]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes)),
       ),
       bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  @override
  List<Object?> get props => [key, origin, items, mergedCount];
}

/// One category of found junk, shown as one card.
class CleanerSmartCleanGroup extends Equatable {
  /// Sources past this many are folded into one "other sources" row, so a
  /// %TEMP% full of small app folders stays readable.
  static const int maxSources = 10;

  static const String otherSourcesKey = 'other';

  final String categoryId;

  /// Largest first.
  final List<JunkItem> items;

  /// [items] by the app that made them and what they are, largest first.
  final List<CleanerSmartCleanSource> sources;

  /// Recycle Bin entries: deleted permanently, so never pre-checked.
  final bool isPermanent;

  final int bytes;

  CleanerSmartCleanGroup._(
    this.categoryId,
    this.items,
    this.sources,
    this.isPermanent,
  ) : bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  factory CleanerSmartCleanGroup({
    required String categoryId,
    required List<JunkItem> items,
    bool isPermanent = false,

    /// Names the apps that made the items; without it only built-in names
    /// and folder names are used.
    CleanerInstalledApps? installedApps,
  }) {
    final sorted = List<JunkItem>.unmodifiable(
      [...items]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes)),
    );
    return CleanerSmartCleanGroup._(
      categoryId,
      sorted,
      _sourcesOf(sorted, installedApps),
      isPermanent,
    );
  }

  static List<CleanerSmartCleanSource> _sourcesOf(
    List<JunkItem> items,
    CleanerInstalledApps? installedApps,
  ) {
    final origins = <String, CleanerItemOrigin>{};
    final byKey = <String, List<JunkItem>>{};
    for (final item in items) {
      final origin = CleanerItemOrigins.of(item, apps: installedApps);
      origins[origin.key] = origin;
      (byKey[origin.key] ??= <JunkItem>[]).add(item);
    }
    final sources = [
      for (final entry in byKey.entries)
        CleanerSmartCleanSource(
          key: entry.key,
          origin: origins[entry.key]!,
          items: entry.value,
        ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    if (sources.length <= maxSources) return List.unmodifiable(sources);

    final tail = sources.sublist(maxSources - 1);
    // Keep the kind when the folded sources agree on it, so a crash report
    // is not described as an unused leftover.
    final kinds = {for (final source in tail) source.origin.kind};
    return List.unmodifiable([
      ...sources.take(maxSources - 1),
      CleanerSmartCleanSource(
        key: otherSourcesKey,
        origin: CleanerItemOrigin(
          kind: kinds.length == 1 ? kinds.single : CleanerItemKind.other,
        ),
        items: [for (final source in tail) ...source.items],
        mergedCount: tail.length,
      ),
    ]);
  }

  /// Names of the recognised apps holding most of this group, largest first.
  List<String> topApps({int limit = 3}) {
    final names = <String>[];
    for (final source in sources) {
      final app = source.origin.app;
      if (app == null || source.origin.appIsFolder || names.contains(app)) {
        continue;
      }
      names.add(app);
      if (names.length == limit) break;
    }
    return names;
  }

  CleanerSmartCleanGroup withoutPaths(Set<String> paths) {
    if (paths.isEmpty) return this;
    return withoutKeys(paths.map(CleanerPaths.key).toSet());
  }

  /// [withoutPaths] for paths already turned into [CleanerPaths.key]s, so
  /// callers filtering several groups build the set once.
  CleanerSmartCleanGroup withoutKeys(Set<String> keys) {
    if (keys.isEmpty) return this;
    final sources = <CleanerSmartCleanSource>[];
    var changed = false;
    for (final source in this.sources) {
      final items = source.items
          .where(
            (item) => !CleanerPaths.ancestors(item.path).any(keys.contains),
          )
          .toList();
      if (items.length != source.items.length) changed = true;
      if (items.isEmpty) continue;
      sources.add(
        items.length == source.items.length
            ? source
            : CleanerSmartCleanSource(
                key: source.key,
                origin: source.origin,
                items: items,
                mergedCount: source.mergedCount,
              ),
      );
    }
    if (!changed) return this;
    return CleanerSmartCleanGroup._(
      categoryId,
      List.unmodifiable(sources.expand((source) => source.items)),
      List.unmodifiable(sources),
      isPermanent,
    );
  }

  @override
  List<Object?> get props => [categoryId, items, sources, isPermanent];
}

/// What a finished clean did, split by whether it can still be undone.
class CleanerSmartCleanResult extends Equatable {
  /// Moved to the Recycle Bin / Trash.
  final int movedBytes;
  final int movedCount;

  /// Emptied from the Recycle Bin.
  final int permanentBytes;
  final int permanentCount;

  /// In use, failed or otherwise left in place.
  final int skippedCount;

  const CleanerSmartCleanResult({
    this.movedBytes = 0,
    this.movedCount = 0,
    this.permanentBytes = 0,
    this.permanentCount = 0,
    this.skippedCount = 0,
  });

  @override
  List<Object?> get props => [
    movedBytes,
    movedCount,
    permanentBytes,
    permanentCount,
    skippedCount,
  ];
}

const Object _notSet = Object();

class CleanerSmartCleanState extends Equatable {
  final CleanerSmartCleanStatus status;
  final List<CleanerSmartCleanGroup> groups;
  final List<CleanerFileReviewCandidate> reviewCandidates;
  final List<String> scanWarnings;

  /// [sourceId]s of the sources the user unchecked.
  final Set<String> excluded;
  final Set<String> pendingPaths;

  /// Category being scanned, null before the first progress event.
  final String? scanCategoryId;
  final String scanPath;

  /// 0..1, null when unknown.
  final double? scanFraction;

  final int cleanDone;
  final int cleanTotal;
  final String cleanPath;

  final CleanerSmartCleanResult? result;
  final CleanerSmartCleanError? error;
  final String? errorMessage;

  const CleanerSmartCleanState({
    this.status = CleanerSmartCleanStatus.idle,
    this.groups = const <CleanerSmartCleanGroup>[],
    this.reviewCandidates = const [],
    this.scanWarnings = const [],
    this.excluded = const <String>{},
    this.pendingPaths = const <String>{},
    this.scanCategoryId,
    this.scanPath = '',
    this.scanFraction,
    this.cleanDone = 0,
    this.cleanTotal = 0,
    this.cleanPath = '',
    this.result,
    this.error,
    this.errorMessage,
  });

  static String sourceId(String categoryId, String sourceKey) =>
      '$categoryId/$sourceKey';

  bool isSourceSelected(String categoryId, String sourceKey) =>
      !excluded.contains(sourceId(categoryId, sourceKey));

  /// True when every source of the group is checked, false when none is, and
  /// null when only some are.
  bool? groupSelection(String categoryId) {
    var any = false, all = true;
    for (final group in groups) {
      if (group.categoryId != categoryId) continue;
      for (final source in group.sources) {
        if (isSourceSelected(categoryId, source.key)) {
          any = true;
        } else {
          all = false;
        }
      }
    }
    if (!any) return false;
    return all ? true : null;
  }

  /// The selection derived from [groups], [pendingPaths] and [excluded].
  ///
  /// Every clean progress tick is a new state from [copyWith] that shares
  /// those three objects, and the footer reads several totals per build.
  /// Filtering tens of thousands of pending paths for each read froze the UI
  /// while cleaning, so the result is kept per [groups] list and reused while
  /// the other two inputs are the same objects.
  static final Expando<_SmartCleanSelection> _selectionCache = Expando();

  _SmartCleanSelection get _selection {
    final cached = _selectionCache[groups];
    if (cached != null &&
        identical(cached.pendingPaths, pendingPaths) &&
        identical(cached.excluded, excluded)) {
      return cached;
    }
    final pendingKeys = pendingPaths.map(CleanerPaths.key).toSet();
    final selection = _SmartCleanSelection(
      pendingPaths: pendingPaths,
      excluded: excluded,
      byGroup:
          Map<CleanerSmartCleanGroup, List<CleanerSmartCleanSource>>.identity()
            ..addEntries([
              for (final group in groups)
                MapEntry(
                  group,
                  group
                      .withoutKeys(pendingKeys)
                      .sources
                      .where(
                        (source) =>
                            isSourceSelected(group.categoryId, source.key),
                      )
                      .toList(growable: false),
                ),
            ]),
    );
    _selectionCache[groups] = selection;
    return selection;
  }

  List<CleanerSmartCleanSource> selectedSources(CleanerSmartCleanGroup group) {
    final cached = _selection.byGroup[group];
    if (cached != null) return cached;
    // A group that is not one of [groups] (callers holding an older state).
    final pendingKeys = pendingPaths.map(CleanerPaths.key).toSet();
    return group
        .withoutKeys(pendingKeys)
        .sources
        .where((source) => isSourceSelected(group.categoryId, source.key))
        .toList(growable: false);
  }

  List<JunkItem> get selectedItems => [
    for (final group in groups)
      for (final source in selectedSources(group)) ...source.items,
  ];

  int get selectedBytes => _selection.bytes;

  int get selectedCount => _selection.count;

  /// Bytes of selected Recycle Bin entries, which are deleted permanently.
  int get selectedPermanentBytes => _selection.permanentBytes;

  bool get selectedIncludesPermanent => _selection.includesPermanent;

  CleanerSmartCleanState copyWith({
    CleanerSmartCleanStatus? status,
    List<CleanerSmartCleanGroup>? groups,
    List<CleanerFileReviewCandidate>? reviewCandidates,
    List<String>? scanWarnings,
    Set<String>? excluded,
    Set<String>? pendingPaths,
    Object? scanCategoryId = _notSet,
    String? scanPath,
    Object? scanFraction = _notSet,
    int? cleanDone,
    int? cleanTotal,
    String? cleanPath,
    Object? result = _notSet,
    Object? error = _notSet,
    Object? errorMessage = _notSet,
  }) {
    return CleanerSmartCleanState(
      status: status ?? this.status,
      groups: groups ?? this.groups,
      reviewCandidates: reviewCandidates ?? this.reviewCandidates,
      scanWarnings: scanWarnings ?? this.scanWarnings,
      excluded: excluded ?? this.excluded,
      pendingPaths: pendingPaths ?? this.pendingPaths,
      scanCategoryId: identical(scanCategoryId, _notSet)
          ? this.scanCategoryId
          : scanCategoryId as String?,
      scanPath: scanPath ?? this.scanPath,
      scanFraction: identical(scanFraction, _notSet)
          ? this.scanFraction
          : scanFraction as double?,
      cleanDone: cleanDone ?? this.cleanDone,
      cleanTotal: cleanTotal ?? this.cleanTotal,
      cleanPath: cleanPath ?? this.cleanPath,
      result: identical(result, _notSet)
          ? this.result
          : result as CleanerSmartCleanResult?,
      error: identical(error, _notSet)
          ? this.error
          : error as CleanerSmartCleanError?,
      errorMessage: identical(errorMessage, _notSet)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    status,
    groups,
    reviewCandidates,
    scanWarnings,
    excluded,
    pendingPaths,
    scanCategoryId,
    scanPath,
    scanFraction,
    cleanDone,
    cleanTotal,
    cleanPath,
    result,
    error,
    errorMessage,
  ];
}

/// What [CleanerSmartCleanState] selects, computed once per input set.
class _SmartCleanSelection {
  final Set<String> pendingPaths;
  final Set<String> excluded;

  /// The checked sources of each group, minus paths a clean already took.
  final Map<CleanerSmartCleanGroup, List<CleanerSmartCleanSource>> byGroup;

  late final int bytes = _sum(byGroup.keys, (source) => source.bytes);
  late final int count = _sum(byGroup.keys, (source) => source.items.length);
  late final int permanentBytes = _sum(
    byGroup.keys.where((group) => group.isPermanent),
    (source) => source.bytes,
  );
  late final bool includesPermanent = byGroup.entries.any(
    (entry) => entry.key.isPermanent && entry.value.isNotEmpty,
  );

  _SmartCleanSelection({
    required this.pendingPaths,
    required this.excluded,
    required this.byGroup,
  });

  int _sum(
    Iterable<CleanerSmartCleanGroup> groups,
    int Function(CleanerSmartCleanSource source) value,
  ) {
    var total = 0;
    for (final group in groups) {
      for (final source in byGroup[group]!) {
        total += value(source);
      }
    }
    return total;
  }
}

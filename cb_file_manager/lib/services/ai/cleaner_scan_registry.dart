import '../disk_cleaner/cleaner_models.dart';

class CleanerScanEntry {
  final ScanReport report;
  final String? ownerTabId;
  final DateTime cachedAt;

  CleanerScanEntry({
    required this.report,
    required this.ownerTabId,
  }) : cachedAt = DateTime.now();
}

class CleanerScanRegistry {
  final int maxEntries;
  final Map<String, CleanerScanEntry> _entries = {};

  CleanerScanRegistry({this.maxEntries = 5}) : assert(maxEntries > 0);

  CleanerScanEntry? operator [](String scanId) => _entries[scanId];

  void store(
    String scanId,
    ScanReport report, {
    required String? ownerTabId,
  }) {
    _entries.remove(scanId);
    while (_entries.length >= maxEntries && _entries.isNotEmpty) {
      _entries.remove(_entries.keys.first);
    }
    _entries[scanId] = CleanerScanEntry(
      report: report,
      ownerTabId: ownerTabId,
    );
  }

  void remove(String scanId) {
    _entries.remove(scanId);
  }

  String? resolveId(
    Object? requestedScanId, {
    required String? ownerTabId,
  }) {
    final requested = requestedScanId?.toString().trim() ?? '';
    final exact = _entries[requested];
    if (exact != null && exact.ownerTabId == ownerTabId) {
      return requested;
    }

    if (!isPlaceholder(requested)) {
      return null;
    }

    for (final entry in _entries.entries.toList().reversed) {
      if (entry.value.ownerTabId == ownerTabId) {
        return entry.key;
      }
    }
    return null;
  }

  static bool isPlaceholder(String scanId) {
    final normalized =
        scanId.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (normalized.isEmpty) return true;
    if (normalized.contains('PLACEHOLDER')) return true;
    return normalized == 'SCAN_ID' ||
        normalized == 'SCANNED_ID' ||
        normalized == 'SC_XXX' ||
        normalized == '<SCAN_ID>' ||
        normalized == '{SCAN_ID}';
  }
}

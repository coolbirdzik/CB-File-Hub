import 'dart:io';

import 'app_insights_models.dart';

/// When each macOS app was last opened, from Spotlight's
/// `kMDItemLastUsedDate`, read for every bundle in one `mdls` call.
abstract final class MacAppUsage {
  static Future<Map<String, AppUsageEvidence>> load(
    List<InstalledAppInfo> apps, {
    Future<ProcessResult> Function(List<String> args)? run,
  }) async {
    final bundles = <(String, String)>[
      for (final app in apps)
        if (app.source == InstalledAppSource.macApp &&
            (app.installLocation?.endsWith('.app') ?? false))
          (app.id, app.installLocation!),
    ];
    if (bundles.isEmpty) return const {};
    final args = [
      '-name',
      'kMDItemLastUsedDate',
      '-raw',
      for (final (_, path) in bundles) path,
    ];
    final ProcessResult result;
    try {
      result = await (run ?? (a) => Process.run('mdls', a))(args);
    } on ProcessException {
      return const {};
    }
    if (result.exitCode != 0) return const {};
    return parse(
      '${result.stdout}',
      [for (final (id, _) in bundles) id],
      bundles: {for (final (id, path) in bundles) id: path},
    );
  }

  /// `mdls -raw` prints one value per file, NUL-separated, and `(null)`
  /// when the bundle was never opened.
  static Map<String, AppUsageEvidence> parse(
    String output,
    List<String> ids, {
    Map<String, String> bundles = const {},
  }) {
    final values = output.split('\u0000');
    final usage = <String, AppUsageEvidence>{};
    for (var i = 0; i < ids.length && i < values.length; i++) {
      final date = parseDate(values[i].trim());
      if (date == null) continue;
      usage[ids[i]] = AppUsageEvidence(
        lastOpenedAt: date,
        source: AppUsageSource.spotlight,
        confidence: UsageEvidenceConfidence.high,
        matchedTarget: bundles[ids[i]],
      );
    }
    return usage;
  }

  /// `2026-11-06 13:20:11 +0000`.
  static DateTime? parseDate(String value) {
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) ([+-])(\d{2})(\d{2})$',
    ).firstMatch(value);
    if (match == null) return null;
    final utc = DateTime.tryParse('${match[1]}T${match[2]}Z');
    if (utc == null) return null;
    final offset = Duration(
      hours: int.parse(match[4]!),
      minutes: int.parse(match[5]!),
    );
    return (match[3] == '+' ? utc.subtract(offset) : utc.add(offset)).toLocal();
  }
}

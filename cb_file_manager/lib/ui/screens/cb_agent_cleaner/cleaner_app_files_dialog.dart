import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/app_insights/app_insights_models.dart';
import '../../../services/app_insights/app_storage_file_browser.dart';
import '../../utils/format_utils.dart';

typedef AppStorageFilesLoader =
    Future<List<AppStorageFileEntry>> Function(String path);

/// Inspects app storage without changing Cleaner selection or reading contents.
class CleanerAppFilesDialog extends StatefulWidget {
  final AppStorageProfile profile;
  final AppStorageEntry? initialEntry;
  final FutureOr<void> Function(AppStorageEntry entry)? onOpenFolder;
  final FutureOr<void> Function(AppStorageProfile profile)? onReviewCleanable;
  final AppStorageFilesLoader loadDirectory;

  const CleanerAppFilesDialog({
    super.key,
    required this.profile,
    this.initialEntry,
    this.onOpenFolder,
    this.onReviewCleanable,
    this.loadDirectory = AppStorageFileBrowser.listDirectory,
  });

  @override
  State<CleanerAppFilesDialog> createState() => _CleanerAppFilesDialogState();
}

class _CleanerAppFilesDialogState extends State<CleanerAppFilesDialog> {
  AppStorageEntry? _root;
  final List<String> _trail = [];
  Future<List<AppStorageFileEntry>>? _listing;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    if (entry != null) {
      _root = entry;
      _trail.add(entry.path);
      _listing = _load(entry.path);
    }
  }

  // Future.sync also turns synchronous loader errors into the visible error state.
  Future<List<AppStorageFileEntry>> _load(String path) =>
      Future.sync(() => widget.loadDirectory(path));

  void _openRoot(AppStorageEntry entry) {
    setState(() {
      _root = entry;
      _trail
        ..clear()
        ..add(entry.path);
      _listing = _load(entry.path);
    });
  }

  void _openDirectory(String path) {
    setState(() {
      _trail.add(path);
      _listing = _load(path);
    });
  }

  void _back() {
    setState(() {
      _trail.removeLast();
      if (_trail.isEmpty) {
        _root = null;
        _listing = null;
      } else {
        _listing = _load(_trail.last);
      }
    });
  }

  void _review() {
    final root = _root;
    if (root == null || !root.isConfirmed || !root.isCleanable) return;
    final callback = widget.onReviewCleanable;
    if (callback == null) return;
    // Review only this rule-backed root, even when browsing a child folder.
    // The screen validates the path against Cleaner rules again.
    Navigator.of(context).pop();
    callback(
      AppStorageProfile(
        app: widget.profile.app,
        usage: widget.profile.usage,
        entries: [root],
        warnings: widget.profile.warnings,
      ),
    );
  }

  void _openInApp() {
    final root = _root;
    final callback = widget.onOpenFolder;
    if (root == null || callback == null) return;
    final entry = AppStorageEntry(
      path: _trail.last,
      kind: root.kind,
      sizeBytes: 0,
      measurementQuality: MeasurementQuality.unknown,
      attributionConfidence: root.attributionConfidence,
    );
    Navigator.of(context).pop();
    callback(entry);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final root = _root;
    final canReview = root != null && root.isConfirmed && root.isCleanable;
    return AlertDialog(
      key: const ValueKey('cleaner-app-files-dialog'),
      title: Text(
        '${l10n.cleanerAppsViewFiles} · ${widget.profile.app.displayName}',
      ),
      content: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.cleanerAppsFilesDescription),
            const SizedBox(height: 12),
            if (root != null) ...[
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('cleaner-app-files-back'),
                    tooltip: l10n.back,
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: SelectableText(
                      _trail.last,
                      key: const ValueKey('cleaner-app-files-path'),
                      maxLines: 2,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.refresh,
                    onPressed: () => setState(() {
                      _listing = _load(_trail.last);
                    }),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              Text(
                canReview
                    ? l10n.cleanerAppsCleanableFilesHint
                    : l10n.cleanerAppsDataFilesHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            const Divider(height: 1),
            Expanded(
              child: root == null ? _buildRoots(l10n) : _buildFiles(l10n),
            ),
          ],
        ),
      ),
      actions: [
        if (root != null && widget.onOpenFolder != null)
          TextButton.icon(
            onPressed: _openInApp,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(l10n.cleanerAppsOpenFolder),
          ),
        if (canReview && widget.onReviewCleanable != null)
          TextButton.icon(
            key: const ValueKey('cleaner-app-files-review'),
            onPressed: _review,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text(l10n.cleanerAppsReviewCleanable),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }

  Widget _buildRoots(AppLocalizations l10n) {
    final entries = widget.profile.entries;
    if (entries.isEmpty) {
      return Center(child: Text(l10n.cleanerAppsNoStorageDetails));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final attribution = switch (entry.attributionConfidence) {
          AttributionConfidence.confirmed =>
            l10n.cleanerAppsAttributionConfirmed,
          AttributionConfidence.likely => l10n.cleanerAppsAttributionPossible,
          AttributionConfidence.shared => l10n.cleanerAppsAttributionShared,
        };
        return ListTile(
          key: ValueKey('cleaner-app-files-root-${entry.path}'),
          leading: Icon(
            entry.isConfirmed && entry.isCleanable
                ? Icons.cleaning_services_outlined
                : Icons.folder_outlined,
          ),
          title: Text(entry.path, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '$attribution${entry.isConfirmed && entry.isCleanable ? ' · ${l10n.cleanerAppsCleanableBadge}' : ''}',
          ),
          trailing: Text(
            entry.measurementQuality == MeasurementQuality.unknown
                ? l10n.cleanerAppsUnknown
                : FormatUtils.formatFileSize(entry.sizeBytes),
          ),
          onTap: () => _openRoot(entry),
        );
      },
    );
  }

  Widget _buildFiles(AppLocalizations l10n) {
    return FutureBuilder<List<AppStorageFileEntry>>(
      future: _listing,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(l10n.loading),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.cleanerAppsFilesLoadFailed(snapshot.error.toString()),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _listing = _load(_trail.last);
                    }),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            ),
          );
        }
        final entries = snapshot.data!;
        if (entries.isEmpty) return Center(child: Text(l10n.emptyFolder));
        return ListView.builder(
          key: ValueKey(_trail.last),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ListTile(
              key: ValueKey('cleaner-app-file-${entry.path}'),
              leading: Icon(
                entry.isDirectory
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
              ),
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Tooltip(
                message: entry.path,
                child: Text(
                  entry.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              trailing: Text(
                entry.isDirectory
                    ? l10n.folder
                    : entry.sizeBytes == null
                    ? l10n.cleanerAppsUnknown
                    : FormatUtils.formatFileSize(entry.sizeBytes!),
              ),
              onTap: entry.isDirectory
                  ? () => _openDirectory(entry.path)
                  : null,
            );
          },
        );
      },
    );
  }
}

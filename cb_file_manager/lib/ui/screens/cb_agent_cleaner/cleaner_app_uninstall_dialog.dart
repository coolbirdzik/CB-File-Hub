import 'package:flutter/material.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/app_insights/app_insights_models.dart';
import '../../../services/app_insights/app_uninstall_service.dart';
import '../../../services/disk_cleaner/cleaner_models.dart';
import '../../utils/format_utils.dart';
import 'cleaner_leftovers_view.dart';

/// Removal and cleanup are separately confirmed. Nothing is checked by default.
class CleanerAppUninstallDialog extends StatefulWidget {
  final AppStorageProfile profile;
  final AppUninstallService service;
  final List<String> excludedPaths;
  final VoidCallback onUninstalled;
  final AppLeftoverPathAction onOpenFolder;
  final AppLeftoverCleanAction onClean;

  const CleanerAppUninstallDialog({
    super.key,
    required this.profile,
    required this.service,
    required this.excludedPaths,
    required this.onUninstalled,
    required this.onOpenFolder,
    required this.onClean,
  });

  @override
  State<CleanerAppUninstallDialog> createState() =>
      _CleanerAppUninstallDialogState();
}

class _CleanerAppUninstallDialogState extends State<CleanerAppUninstallDialog> {
  bool _busy = false;
  bool _removed = false;
  bool _scanned = false;
  AppUninstallScan? _scan;
  final Set<String> _selected = {};
  String? _error;
  String? _progress;

  Future<void> _uninstallAndScan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_removed) {
        await widget.service.uninstall(widget.profile.app);
        if (!mounted) return;
        setState(() => _removed = true);
        widget.onUninstalled();
      }
      final scan = await widget.service.scan(
        widget.profile,
        excludedPaths: widget.excludedPaths,
      );
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _scanned = true;
        _selected.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clean() async {
    final l = AppLocalizations.of(context)!;
    final paths = _selected.toList(growable: false);
    if (paths.isEmpty) return;
    final size = paths.fold<int>(
      0,
      (sum, path) => sum + _scan!.folders[path]!.sizeBytes,
    );
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          l.cleanerLeftoversConfirmTitle(l.diskCleanerRecycleBinLabel),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.cleanerLeftoversConfirmBody(
                    paths.length,
                    FormatUtils.formatFileSize(size),
                    l.diskCleanerRecycleBinLabel,
                  ),
                ),
                const SizedBox(height: 12),
                for (final path in paths)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(path),
                  ),
                Text(l.cleanerUninstallDataWarning),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('cleaner-uninstall-confirm-clean'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.diskCleanerMoveToRecycleBin),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Re-read inventory and filesystem immediately before queueing deletion.
      final fresh = await widget.service.scan(
        widget.profile,
        excludedPaths: widget.excludedPaths,
      );
      if (!paths.every(fresh.folders.containsKey)) {
        throw AppUninstallException(l.cleanerUninstallFilesChanged);
      }
      if (!mounted) return;
      final result = await widget.onClean(
        [
          for (final path in paths)
            JunkItem(
              path: path,
              sizeBytes: fresh.folders[path]!.sizeBytes,
              categoryId: 'selected_item',
              isContainerOnly: false,
              isUserSelected: true,
            ),
        ],
        (done, total, path) {
          if (mounted) {
            setState(() => _progress = '$done / $total\n${path ?? ''}');
          }
        },
      );
      if (!mounted) return;
      if (result == null) {
        throw AppUninstallException(l.cleanerUninstallCleanupFailed);
      }
      setState(() {
        _scan = AppUninstallScan(
          {...fresh.folders}
            ..removeWhere((path, _) => result.succeeded.contains(path)),
          warnings: fresh.warnings,
        );
        _selected.removeAll(result.succeeded);
        if (_selected.isNotEmpty) {
          _error = [
            l.cleanerUninstallCleanupFailed,
            for (final failure in result.failed.entries)
              '${failure.key}: ${failure.value}',
            ...result.skippedUnsafe,
            ...result.skippedInUse,
            ...result.skippedByUser,
          ].join('\n');
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final folders = _scan?.folders.entries.toList() ?? [];
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const ValueKey('cleaner-app-uninstall-dialog'),
        title: Text(
          '${l.cleanerUninstallApp}: ${widget.profile.app.displayName}',
        ),
        content: SizedBox(
          width: 660,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _removed
                      ? l.cleanerUninstallReview
                      : l.cleanerUninstallConfirm,
                ),
                const SizedBox(height: 12),
                Text(
                  l.cleanerUninstallDataWarning,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    _progress ??
                        (_removed
                            ? l.cleanerUninstallScanning
                            : l.cleanerUninstallRunning),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_scanned && folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(l.cleanerUninstallNoFiles),
                  ),
                if (_scan?.warnings.isNotEmpty ?? false) ...[
                  const SizedBox(height: 12),
                  Text(l.cleanerUninstallPartial),
                  for (final path in _scan!.warnings) SelectableText(path),
                ],
                for (final entry in folders)
                  CheckboxListTile(
                    key: ValueKey('cleaner-uninstall-folder-${entry.key}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(entry.key),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _selected.add(entry.key);
                            } else {
                              _selected.remove(entry.key);
                            }
                          }),
                    title: Text(entry.key),
                    subtitle: Text(
                      '${entry.value.isComplete ? '' : '≥ '}${FormatUtils.formatFileSize(entry.value.sizeBytes)}',
                    ),
                    secondary: IconButton(
                      tooltip: l.cleanerAppsOpenFolder,
                      onPressed: _busy
                          ? null
                          : () => widget.onOpenFolder(entry.key),
                      icon: const Icon(Icons.folder_open_outlined),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.close),
          ),
          if (_scanned)
            TextButton(
              onPressed: _busy ? null : _uninstallAndScan,
              child: Text(l.cleanerLeftoversScan),
            ),
          if (!_scanned)
            FilledButton(
              key: const ValueKey('cleaner-uninstall-start'),
              onPressed: _busy ? null : _uninstallAndScan,
              child: Text(
                _removed ? l.cleanerLeftoversScan : l.cleanerUninstallApp,
              ),
            ),
          if (_scanned)
            FilledButton.icon(
              key: const ValueKey('cleaner-uninstall-clean'),
              onPressed: _busy || _selected.isEmpty ? null : _clean,
              icon: const Icon(Icons.delete_outline),
              label: Text(l.diskCleanerMoveToRecycleBin),
            ),
        ],
      ),
    );
  }
}

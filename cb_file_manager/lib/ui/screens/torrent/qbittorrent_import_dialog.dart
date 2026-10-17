import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/torrent/qbittorrent_backup_importer.dart';

typedef QbittorrentImportAction =
    Future<QbittorrentImportResult> Function(
      QbittorrentImportPlan plan,
      String destination, {
      required bool removeSources,
      required bool confirmedRemoval,
      required bool Function() isCancelled,
      required void Function(int, int) onProgress,
    });

class QbittorrentImportDialog extends StatefulWidget {
  final String initialDestination;
  final String logPath;
  final Future<List<String>> Function() discover;
  final Future<QbittorrentImportPlan> Function(List<String>) loadPlan;
  final Future<void> Function(QbittorrentImportPlan) checkCleanup;
  final QbittorrentImportAction onImport;
  const QbittorrentImportDialog({
    super.key,
    required this.initialDestination,
    required this.logPath,
    required this.discover,
    required this.loadPlan,
    required this.checkCleanup,
    required this.onImport,
  });
  @override
  State<QbittorrentImportDialog> createState() =>
      _QbittorrentImportDialogState();
}

class _QbittorrentImportDialogState extends State<QbittorrentImportDialog> {
  late final _destination = TextEditingController(
    text: widget.initialDestination,
  );
  QbittorrentImportPlan? _plan;
  QbittorrentImportResult? _result;
  bool _busy = true;
  bool _importing = false;
  bool _confirming = false;
  bool _remove = false;
  bool _cancel = false;
  int _completed = 0;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  String? _error;
  AppLocalizations get l => AppLocalizations.of(context)!;
  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  String _message(Object error) => error is QbittorrentImportException
      ? l.qbittorrentProblem(error.problem.name)
      : '$error';

  String _sourceError(String message) {
    for (final problem in QbittorrentImportProblem.values) {
      message = message.replaceAll(
        'qBittorrent: ${problem.name}',
        l.qbittorrentProblem(problem.name),
      );
    }
    return message;
  }

  Future<void> _prepare([List<String>? sources]) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final roots = sources ?? await widget.discover();
      if (roots.isEmpty) throw StateError(l.qbittorrentProblem('noSources'));
      final plan = await widget.loadPlan(roots);
      if (mounted) setState(() => _plan = plan);
    } catch (error) {
      if (mounted) {
        setState(() {
          _plan = null;
          _error = _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview(QbittorrentImportPlan plan, {Key? key}) => Container(
    height: 192,
    decoration: BoxDecoration(
      color: context.cbColors.fillSubtle,
      borderRadius: CbRadii.mdAll,
      border: Border.all(color: context.cbColors.strokeSubtle),
    ),
    clipBehavior: Clip.antiAlias,
    child: ListView.builder(
      key: key,
      padding: const EdgeInsets.all(CbSpacing.lg),
      itemCount: plan.items.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: CbSpacing.sm),
        child: SelectableText(
          plan.items[index].files.map((file) => file.path).join('\n'),
          style: CbTypography.body.copyWith(height: 1.6),
        ),
      ),
    ),
  );

  Future<bool> _confirm(QbittorrentImportPlan plan) async =>
      await CbDialog.show<bool>(
        context: context,
        barrierDismissible: false,
        dialog: CbDialog(
          key: const ValueKey('qbittorrent-cleanup-confirmation'),
          title: l.qbittorrentConfirmTitle,
          subtitle: l.qbittorrentConfirmHint(plan.fileCount),
          width: 760,
          content: _preview(
            plan,
            key: const ValueKey('qbittorrent-cleanup-preview'),
          ),
          actions: [
            CbButton(
              key: const ValueKey('qbittorrent-cleanup-cancel'),
              label: l.cancel,
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
            ),
            CbButton(
              key: const ValueKey('qbittorrent-cleanup-confirm'),
              label: l.qbittorrentConfirm,
              variant: CbButtonVariant.primary,
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _submit() async {
    final plan = _plan;
    if (_busy || plan == null || plan.items.isEmpty) return;
    final destination = _destination.text.trim();
    if (destination.isEmpty) {
      setState(() => _error = l.qbittorrentProblem('destination'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_remove) {
        await widget.checkCleanup(plan);
        if (!mounted) return;
        setState(() => _confirming = true);
        final confirmed = await _confirm(plan);
        if (!mounted) return;
        setState(() => _confirming = false);
        if (!confirmed) return;
      }
      if (!mounted) return;
      setState(() {
        _importing = true;
        _cancel = false;
        _completed = 0;
      });
      final result = await widget.onImport(
        plan,
        destination,
        removeSources: _remove,
        confirmedRemoval: _remove,
        isCancelled: () => _cancel,
        onProgress: (completed, total) {
          _completed = completed;
          final now = DateTime.now();
          if (mounted &&
              (completed == total ||
                  now.difference(_lastProgress).inMilliseconds >= 100)) {
            _lastProgress = now;
            setState(() {});
          }
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _importing = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final result = _result;
    return PopScope(
      canPop: !_busy,
      child: CbDialog(
        title: l.qbittorrentImport,
        subtitle: l.qbittorrentImportHint,
        width: 800,
        showCloseButton: !_busy,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: CbSpacing.xl,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: CbSpacing.md,
              children: [
                Text(l.torrentSources, style: CbTypography.label),
                if (plan != null) ...[
                  for (final root in plan.roots)
                    SelectableText(
                      root,
                      style: CbTypography.body.copyWith(
                        color: context.cbColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  Text(l.qbittorrentFound(plan.items.length, plan.fileCount)),
                ],
                Wrap(
                  spacing: CbSpacing.md,
                  runSpacing: CbSpacing.md,
                  children: [
                    CbButton(
                      label: l.qbittorrentChooseSource,
                      icon: PhosphorIconsLight.folderOpen,
                      onPressed: _busy
                          ? null
                          : () async {
                              final path = await FilePicker.getDirectoryPath(
                                dialogTitle: l.qbittorrentChooseSource,
                              );
                              if (path != null && mounted) {
                                await _prepare([path]);
                              }
                            },
                    ),
                    CbButton(
                      label: l.refresh,
                      icon: PhosphorIconsLight.arrowClockwise,
                      onPressed: _busy ? null : () => _prepare(),
                    ),
                  ],
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CbTextField(
                    key: const ValueKey('qbittorrent-destination'),
                    controller: _destination,
                    label: l.torrentStorage,
                    enabled: !_busy,
                    mono: true,
                  ),
                ),
                const SizedBox(width: CbSpacing.md),
                CbButton(
                  label: l.browse,
                  onPressed: _busy
                      ? null
                      : () async {
                          final path = await FilePicker.getDirectoryPath(
                            dialogTitle: l.torrentStorage,
                          );
                          if (path != null && mounted) {
                            setState(() => _destination.text = path);
                          }
                        },
                ),
              ],
            ),
            if (plan != null && result == null) _preview(plan),
            CheckboxListTile(
              key: const ValueKey('qbittorrent-remove-sources'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: CbSpacing.lg,
                vertical: CbSpacing.sm,
              ),
              shape: const RoundedRectangleBorder(borderRadius: CbRadii.mdAll),
              tileColor: context.cbColors.fillSubtle,
              controlAffinity: ListTileControlAffinity.leading,
              titleAlignment: ListTileTitleAlignment.top,
              value: _remove,
              title: Text(
                l.qbittorrentRemoveSources,
                style: CbTypography.label,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: CbSpacing.sm),
                child: Text(
                  l.qbittorrentRemoveHint,
                  style: CbTypography.body.copyWith(
                    color: context.cbColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _remove = value!),
            ),
            if (_importing)
              Text(l.qbittorrentProgress(_completed, plan?.items.length ?? 0)),
            if (result != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: CbSpacing.md,
                children: [
                  Text(
                    l.qbittorrentResult(
                      result.stored,
                      result.cleaned,
                      result.failed,
                    ),
                  ),
                  if (result.cancelled) Text(l.cancel),
                  if (result.stoppedBy != null)
                    Text(l.qbittorrentProblem(result.stoppedBy!.name)),
                  for (final error in result.errors.take(3))
                    SelectableText(_sourceError(error)),
                  if (result.failed > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CbButton(
                        label: l.torrentScanLog,
                        onPressed: () => OpenFilex.open(widget.logPath),
                      ),
                    ),
                ],
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        actions: [
          CbButton(
            label: _importing ? l.cancel : l.close,
            onPressed: _importing
                ? (_cancel ? null : () => setState(() => _cancel = true))
                : (_busy ? null : () => Navigator.pop(context, result)),
          ),
          if (result == null)
            CbButton(
              key: const ValueKey('qbittorrent-import-confirm'),
              label: l.qbittorrentImport,
              loading: _busy && !_confirming,
              variant: CbButtonVariant.primary,
              onPressed: _busy || plan == null || plan.items.isEmpty
                  ? null
                  : _submit,
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/ssh/sftp_transfer.dart';
import '../../components/common/app_toast.dart';
import '../../utils/route.dart';
import 'sftp_name_dialog.dart';

/// File operations for a connected SFTP browser. The clipboard is scoped to
/// the live file system, so it survives tab navigation without crossing hosts.
class SftpBrowserActions extends ChangeNotifier {
  static final _clips =
      Expando<ValueNotifier<({List<TransferEntry> entries, bool cut})?>>();
  SftpBrowserActions(this.fs) {
    _clipboard.addListener(notifyListeners);
  }
  final TransferFileSystem fs;
  late final _clipboard = _clips[fs] ??=
      ValueNotifier<({List<TransferEntry> entries, bool cut})?>(null);
  bool busy = false;
  bool _disposed = false;
  SftpTransferTask? _task;
  bool get canPaste => _clipboard.value != null && !busy;
  bool isCut(String path) =>
      _clipboard.value?.cut == true &&
      _clipboard.value!.entries.any((e) => e.path == path);

  void hold(List<TransferEntry> entries, {required bool cut}) {
    if (!busy && entries.isNotEmpty) {
      _clipboard.value = (entries: List.of(entries), cut: cut);
    }
  }

  void cancelClipboard() => _clipboard.value = null;

  Future<void> _run(
    BuildContext context,
    Future<List<TransferFailure>> Function() work,
  ) async {
    if (busy || _disposed) return;
    busy = true;
    notifyListeners();
    try {
      final failures = await work();
      if (context.mounted && failures.isNotEmpty) {
        await RouteUtils.showAcrylicDialog<void>(
          context: context,
          builder: (context) => CbDialog(
            title: context.tr.sshTransferFailed(failures.length),
            icon: PhosphorIconsLight.warningCircle,
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: SelectableText(
                  failures
                      .map((f) {
                        final reason = switch (f.kind) {
                          TransferFailureKind.exists =>
                            context.tr.sshTransferExists,
                          TransferFailureKind.link =>
                            context.tr.sshTransferLinkSkipped,
                          TransferFailureKind.invalidName =>
                            context.tr.sshTransferInvalidName,
                          TransferFailureKind.typeConflict =>
                            context.tr.sshTransferTypeConflict,
                          TransferFailureKind.caseConflict =>
                            context.tr.sshTransferCaseConflict,
                          TransferFailureKind.error => '${f.error}',
                        };
                        return '${f.path}: $reason';
                      })
                      .join('\n'),
                ),
              ),
            ),
            actions: [
              CbButton(
                label: context.tr.close,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (context.mounted) AppToast.error(context, error.toString());
    } finally {
      _task = null;
      fs.releaseStreams();
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> paste(BuildContext context, String destination) async {
    final clip = _clipboard.value;
    if (clip == null || busy) return;
    if (clip.entries.any(
      (e) =>
          fs.paths.equals(fs.paths.dirname(e.path), destination) ||
          (e.isDirectory &&
              (fs.paths.equals(e.path, destination) ||
                  fs.paths.isWithin(e.path, destination))),
    )) {
      AppToast.warning(context, context.tr.sshPasteInvalidTarget);
      return;
    }
    await _run(context, () async {
      if (clip.cut) {
        final failures = await moveTransferEntries(
          fs,
          clip.entries,
          destination,
        );
        if (_clipboard.value == clip) {
          final failed = failures.map((f) => f.path).toSet();
          final remaining = clip.entries
              .where((e) => failed.contains(e.path))
              .toList();
          _clipboard.value = remaining.isEmpty
              ? null
              : (entries: remaining, cut: true);
        }
        return failures;
      }
      _task = SftpTransferTask(
        from: fs,
        to: fs,
        sources: clip.entries,
        destination: destination,
        resolveConflicts: (names) =>
            RouteUtils.showAcrylicDialog<TransferConflictPolicy>(
              context: context,
              builder: (context) => CbDialog(
                title: context.tr.sshTransferConflictTitle,
                subtitle: names.join('\n'),
                actions: [
                  CbButton(
                    label: context.tr.cancel,
                    onPressed: () => Navigator.pop(context),
                  ),
                  CbButton(
                    label: context.tr.sshTransferSkip,
                    onPressed: () =>
                        Navigator.pop(context, TransferConflictPolicy.skip),
                  ),
                  CbButton(
                    label: context.tr.sshTransferReplace,
                    onPressed: () =>
                        Navigator.pop(context, TransferConflictPolicy.replace),
                  ),
                ],
              ),
            ),
      );
      return (await _task!.run()).failures;
    });
  }

  Future<void> delete(BuildContext context, List<TransferEntry> entries) async {
    if (entries.isEmpty || busy) return;
    // Set busy before showing the modal so repeated Delete cannot stack it.
    await _run(context, () async {
      final confirmed = await RouteUtils.showAcrylicDialog<bool>(
        context: context,
        builder: (context) => CbDialog(
          title: context.tr.sshRemoteDeleteConfirm(entries.length),
          subtitle: entries.map((e) => e.name).join('\n'),
          icon: PhosphorIconsLight.trash,
          actions: [
            CbButton(
              label: context.tr.cancel,
              autofocus: true,
              onPressed: () => Navigator.pop(context),
            ),
            CbButton(
              key: const ValueKey('sftp-browser-confirm-delete'),
              label: context.tr.delete,
              variant: CbButtonVariant.danger,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      return confirmed == true && !_disposed
          ? deleteTransferEntries(fs, entries)
          : const [];
    });
  }

  Future<void> rename(BuildContext context, TransferEntry entry) => _run(
    context,
    () async {
      final name = await RouteUtils.showAcrylicDialog<String>(
        context: context,
        builder: (context) => SftpNameDialog(
          title: context.tr.rename,
          icon: PhosphorIconsLight.pencilSimple,
          action: context.tr.rename,
          placeholder: context.tr.newNameLabel,
          initial: entry.name,
        ),
      );
      if (name == null || name == entry.name || !context.mounted || _disposed) {
        return const [];
      }
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains('\x00')) {
        AppToast.error(context, context.tr.sshTransferInvalidName);
        return const [];
      }
      final target = fs.paths.join(fs.paths.dirname(entry.path), name);
      if (await fs.kind(target) != null) {
        return [TransferFailure(entry.path, TransferFailureKind.exists)];
      }
      await fs.rename(entry.path, target);
      return const [];
    },
  );

  @override
  void dispose() {
    _disposed = true;
    _task?.cancel();
    _clipboard.removeListener(notifyListeners);
    super.dispose();
  }
}

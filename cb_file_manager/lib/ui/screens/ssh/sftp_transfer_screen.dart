import 'dart:async';

import 'package:dartssh2/dartssh2.dart' show SSHClient, SftpClient;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../bloc/selection/selection.dart';
import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../helpers/core/text_utils.dart';
import '../../../helpers/core/desktop_shortcuts.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../components/common/collection_view_scale_controller.dart';
import '../../components/common/grid_list_collection.dart';
import '../../components/common/file_view_shell.dart';
import '../../components/common/shared_action_bar.dart';
import '../../utils/grid_zoom_constraints.dart';
import '../folder_list/folder_list_state.dart';
import '../../../services/ssh/sftp_transfer.dart';
import '../../../services/ssh/ssh_profile_store.dart';
import '../../components/common/app_toast.dart';
import '../../components/common/breadcrumb_address_bar.dart';
import '../../components/common/optimized_interaction_handler.dart';
import '../../components/common/screen_scaffold.dart';
import '../../components/common/shared_file_context_menu.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../tab_manager/core/tab_focus_gate.dart';
import '../../utils/format_utils.dart';
import '../../utils/item_interaction_style.dart';
import '../../utils/platform_utils.dart';
import '../../utils/route.dart';
import '../../widgets/drag_selection_region.dart';
import '../../widgets/selection_geometry_item.dart';
import '../../tab_manager/core/tabbed_folder/tabbed_folder_drag_selection_controller.dart';
import '../network_browsing/components/network_navigation_bar.dart';
import 'ssh_host_dialog.dart';
import 'sftp_name_dialog.dart';

/// Panes sit side by side from this width; below it the local pane stacks
/// above the remote one.
const double _sideBySideWidth = 720;

/// Locale-neutral and fixed-width, so the column lines up in every language.
final _modifiedFormat = DateFormat('yyyy-MM-dd HH:mm');

/// An open SFTP session the transfer screen owns.
class SftpTransferSession {
  final TransferFileSystem fileSystem;

  /// Completes when the transport closes.
  final Future<void> done;
  final void Function() close;
  const SftpTransferSession({
    required this.fileSystem,
    required this.done,
    required this.close,
  });
}

typedef SftpSessionOpener =
    Future<SftpTransferSession> Function(
      SshProfile profile,
      SshTrustPrompt trustPrompt,
    );

/// WinSCP-style transfer between this computer (left) and a saved SSH host
/// (right). Routed at `#ssh/transfer` and `#ssh/transfer/<profileId>`.
class SftpTransferScreen extends StatefulWidget {
  final String tabId;
  final String? profileId;
  final SshProfileStore? store;
  final TransferFileSystem? localFileSystem;
  final SftpSessionOpener? openSession;

  /// Overrides the native folder dialog, for tests.
  final Future<String?> Function()? directoryPicker;
  const SftpTransferScreen({
    super.key,
    required this.tabId,
    this.profileId,
    this.store,
    this.localFileSystem,
    this.openSession,
    this.directoryPicker,
  });

  @override
  State<SftpTransferScreen> createState() => _SftpTransferScreenState();
}

class _SftpTransferScreenState extends State<SftpTransferScreen> {
  late final _store = widget.store ?? SshProfileStore.instance;
  late final _local = _PaneController(
    widget.localFileSystem ?? LocalTransferFileSystem(),
  );
  final _remote = _PaneController(null);
  final _progress = ValueNotifier<TransferProgress?>(null);
  SftpTransferSession? _session;
  SshProfile? _profile;
  bool _connecting = false;
  String? _connectError;
  int _generation = 0;
  SftpTransferTask? _task;

  /// Remote entries waiting for Paste, and whether Paste moves them.
  ({List<TransferEntry> entries, bool cut})? _clip;

  /// A remote move, rename or delete is running.
  bool _working = false;
  bool _confirmingDelete = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    unawaited(_local.openHome());
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _store.load();
    } catch (e) {
      if (mounted) setState(() => _connectError = e.toString());
      return;
    }
    if (!mounted) return;
    final profile = _store.profiles
        .where((p) => p.id == widget.profileId)
        .firstOrNull;
    if (profile != null) {
      await _connect(profile);
    } else {
      _rename(context.tr.sshFileTransfer);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _rename(String name) =>
      context.read<TabManagerBloc>().add(UpdateTabName(widget.tabId, name));

  Future<SftpTransferSession> _openSftp(
    SshProfile profile,
    SshTrustPrompt trustPrompt,
  ) async {
    final connector = SshConnector(_store);
    // The subsystem closes first; a client closed under it aborts the
    // socket mid-write. A dead transport must not hold the client open.
    void shut(SftpClient sftp, SSHClient client) => unawaited(
      Future.sync(sftp.close)
          .timeout(const Duration(seconds: 2))
          .catchError((_) {})
          .whenComplete(client.close),
    );
    final client = await connector.connect(profile, trustPrompt: trustPrompt);
    try {
      final sftp = await client.sftp();
      final fileSystem = SftpTransferFileSystem(
        sftp,
        // More connections to the same host, opened while a transfer runs.
        openLane: () async {
          final extra = await connector.connect(
            profile,
            trustPrompt: trustPrompt,
          );
          try {
            final lane = await extra.sftp();
            return SftpLane(
              client: lane,
              done: extra.done,
              close: () => shut(lane, extra),
            );
          } catch (_) {
            extra.close();
            rethrow;
          }
        },
      );
      return SftpTransferSession(
        fileSystem: fileSystem,
        done: client.done,
        close: () {
          fileSystem.closeLanes();
          shut(sftp, client);
        },
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  void _closeSession() {
    _generation++;
    _task?.cancel();
    _session?.close();
    _session = null;
    _clip = null;
    _remote.detach();
  }

  Future<void> _connect(SshProfile profile) async {
    _closeSession();
    final generation = _generation;
    setState(() {
      _profile = profile;
      _connecting = true;
      _connectError = null;
    });
    _rename('${profile.name} · SFTP');
    try {
      final session = await (widget.openSession ?? _openSftp)(
        profile,
        (h, port, type, fp, old) =>
            promptSshHostTrust(context, h, port, type, fp, old),
      );
      if (!mounted || generation != _generation) {
        session.close();
        return;
      }
      _session = session;
      unawaited(
        session.done.then(
          (_) => _lost(generation),
          onError: (Object e) => _lost(generation, e.toString()),
        ),
      );
      await _remote.attach(session.fileSystem);
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _connectError = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _connecting = false);
      }
    }
  }

  void _lost(int generation, [String? message]) {
    if (!mounted || generation != _generation) return;
    _closeSession();
    setState(() => _connectError = message ?? context.tr.sshDisconnected);
  }

  void _disconnect() {
    _closeSession();
    setState(() => _connectError = context.tr.sshDisconnected);
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    _closeSession();
    _local.dispose();
    _remote.dispose();
    _progress.dispose();
    super.dispose();
  }

  // ─── Transfers ───────────────────────────────────────────────────────────

  Future<void> _transfer({required bool upload, List<TransferEntry>? entries}) {
    final source = upload ? _local : _remote;
    return _copyInto(
      from: source.fileSystem,
      target: upload ? _remote : _local,
      items: entries ?? source.selectedEntries,
    );
  }

  /// Copies [items] of [from] into the folder [target] shows.
  Future<void> _copyInto({
    required TransferFileSystem? from,
    required _PaneController target,
    required List<TransferEntry> items,
  }) async {
    final tr = context.tr;
    final to = target.fileSystem;
    if (_task != null ||
        _working ||
        from == null ||
        to == null ||
        items.isEmpty) {
      return;
    }
    // The Windows drive list is not a folder.
    if (target.path.isEmpty) {
      AppToast.warning(context, tr.sshTransferPickFolder);
      return;
    }
    final task = SftpTransferTask(
      from: from,
      to: to,
      sources: items,
      destination: target.path,
      resolveConflicts: _askConflict,
      onProgress: (progress) => _progress.value = progress,
    );
    setState(() => _task = task);
    TransferReport? report;
    Object? error;
    try {
      report = await task.run();
    } catch (e) {
      error = e;
    }
    from.releaseStreams();
    to.releaseStreams();
    if (!mounted) return;
    setState(() => _task = null);
    _progress.value = null;
    unawaited(target.refresh());
    if (error != null) {
      AppToast.error(context, error.toString());
    } else if (report!.cancelled) {
      AppToast.info(context, tr.sshTransferCancelled);
    } else if (report.failures.isNotEmpty) {
      await _showFailures(report.failures, from);
    } else {
      AppToast.success(context, tr.sshTransferComplete(report.transferred));
    }
  }

  Future<TransferConflictPolicy?> _askConflict(List<String> names) {
    if (!mounted) return Future.value();
    final tr = context.tr;
    const shown = 6;
    final listed = names.take(shown).join('\n');
    return RouteUtils.showAcrylicDialog<TransferConflictPolicy>(
      context: context,
      builder: (context) => CbDialog(
        title: tr.sshTransferConflictTitle,
        subtitle: names.length > shown
            ? '$listed\n+${names.length - shown}'
            : listed,
        icon: PhosphorIconsLight.copy,
        width: 460,
        actions: [
          CbButton(label: tr.cancel, onPressed: () => Navigator.pop(context)),
          CbButton(
            label: tr.sshTransferSkip,
            onPressed: () =>
                Navigator.pop(context, TransferConflictPolicy.skip),
          ),
          CbButton(
            label: tr.sshTransferReplace,
            variant: CbButtonVariant.primary,
            autofocus: true,
            onPressed: () =>
                Navigator.pop(context, TransferConflictPolicy.replace),
          ),
        ],
      ),
    );
  }

  Future<void> _showFailures(
    List<TransferFailure> failures,
    TransferFileSystem from,
  ) {
    final tr = context.tr;
    final c = context.cbColors;
    String reason(TransferFailure f) => switch (f.kind) {
      TransferFailureKind.invalidName => tr.sshTransferInvalidName,
      TransferFailureKind.link => tr.sshTransferLinkSkipped,
      TransferFailureKind.typeConflict => tr.sshTransferTypeConflict,
      TransferFailureKind.caseConflict => tr.sshTransferCaseConflict,
      TransferFailureKind.exists => tr.sshTransferExists,
      TransferFailureKind.error => '${f.error}',
    };
    return RouteUtils.showAcrylicDialog<void>(
      context: context,
      builder: (context) => CbDialog(
        title: tr.sshTransferFailed(failures.length),
        icon: PhosphorIconsLight.warningCircle,
        width: 520,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final failure in failures)
                Padding(
                  padding: const EdgeInsets.only(bottom: CbSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        from.paths.basename(failure.path),
                        style: CbTypography.label.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      SelectableText(
                        reason(failure),
                        style: CbTypography.bodySm.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          CbButton(
            label: tr.close,
            variant: CbButtonVariant.primary,
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Opens a folder picked in the native dialog in the local pane.
  Future<void> _browseLocal() async {
    final current = _local.path;
    String? picked;
    try {
      picked =
          await (widget.directoryPicker?.call() ??
              FilePicker.getDirectoryPath(
                dialogTitle: context.tr.selectFolder,
                initialDirectory: current.isEmpty ? null : current,
              ));
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString());
      return;
    }
    if (!mounted || picked == null || picked.isEmpty) return;
    await _local.navigate(picked);
  }

  Future<String?> _askName({
    required String title,
    required IconData icon,
    required String action,
    required String placeholder,
    String initial = '',
  }) => RouteUtils.showAcrylicDialog<String>(
    context: context,
    builder: (context) => SftpNameDialog(
      title: title,
      icon: icon,
      action: action,
      placeholder: placeholder,
      initial: initial,
    ),
  );

  bool _validName(TransferFileSystem fs, String name) =>
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains(fs.paths.separator);

  Future<void> _newFolder(_PaneController pane) async {
    final fs = pane.fileSystem;
    if (fs == null || pane.path.isEmpty) return;
    final tr = context.tr;
    final name = await _askName(
      title: tr.newFolder,
      icon: PhosphorIconsLight.folderPlus,
      action: tr.create,
      placeholder: tr.folderName,
    );
    if (!mounted || name == null || name.isEmpty) return;
    if (!_validName(fs, name)) {
      AppToast.error(context, tr.sshInvalidFolderName);
      return;
    }
    final path = fs.paths.join(pane.path, name);
    try {
      await fs.createDirectory(path);
      await pane.refresh(select: path);
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString());
    }
  }

  // ─── Remote file operations ──────────────────────────────────────────────

  void _hold(List<TransferEntry> entries, {required bool cut}) {
    if (entries.isEmpty) return;
    setState(() => _clip = (entries: entries, cut: cut));
    AppToast.info(context, context.tr.sshClipboardHint(entries.length));
  }

  /// Runs a remote change with the panes locked, then lists the folder again.
  Future<void> _remoteWork(
    Future<List<TransferFailure>> Function(TransferFileSystem fs) work,
  ) async {
    final fs = _remote.fileSystem;
    if (fs == null || _task != null || _working) return;
    setState(() => _working = true);
    var failures = const <TransferFailure>[];
    Object? error;
    try {
      failures = await work(fs);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _working = false);
    if (fs != _remote.fileSystem) return;
    unawaited(_remote.refresh());
    if (error != null) {
      AppToast.error(context, error.toString());
    } else if (failures.isNotEmpty) {
      await _showFailures(failures, fs);
    }
  }

  Future<void> _paste() async {
    if (_task != null || _working) return;
    final clip = _clip;
    final fs = _remote.fileSystem;
    final destination = _remote.path;
    if (clip == null || fs == null) return;
    // Pasting where the items already are would overwrite them with
    // themselves; a folder cannot go inside itself either.
    final invalid = clip.entries.any(
      (e) =>
          fs.paths.equals(fs.paths.dirname(e.path), destination) ||
          (e.isDirectory &&
              (fs.paths.equals(e.path, destination) ||
                  fs.paths.isWithin(e.path, destination))),
    );
    if (invalid) {
      AppToast.warning(context, context.tr.sshPasteInvalidTarget);
      return;
    }
    if (!clip.cut) {
      return _copyInto(from: fs, target: _remote, items: clip.entries);
    }
    await _remoteWork((fs) async {
      final failures = await moveTransferEntries(fs, clip.entries, destination);
      if (mounted && _clip == clip) {
        final failed = failures.map((f) => f.path).toSet();
        final remaining = clip.entries
            .where((e) => failed.contains(e.path))
            .toList();
        setState(
          () => _clip = remaining.isEmpty
              ? null
              : (entries: remaining, cut: true),
        );
      }
      return failures;
    });
  }

  Future<void> _renameEntry(TransferEntry entry) async {
    final fs = _remote.fileSystem;
    if (fs == null || _task != null || _working) return;
    final tr = context.tr;
    final name = await _askName(
      title: tr.rename,
      icon: PhosphorIconsLight.pencilSimple,
      action: tr.rename,
      placeholder: tr.newNameLabel,
      initial: entry.name,
    );
    if (!mounted ||
        fs != _remote.fileSystem ||
        name == null ||
        name.isEmpty ||
        name == entry.name) {
      return;
    }
    if (!_validName(fs, name)) {
      AppToast.error(context, tr.sshTransferInvalidName);
      return;
    }
    final target = fs.paths.join(fs.paths.dirname(entry.path), name);
    setState(() => _clip = null);
    await _remoteWork((fs) async {
      if (await fs.kind(target) != null) {
        return [TransferFailure(entry.path, TransferFailureKind.exists)];
      }
      await fs.rename(entry.path, target);
      return const [];
    });
  }

  Future<void> _delete(List<TransferEntry> entries) async {
    if (entries.isEmpty || _task != null || _working || _confirmingDelete) {
      return;
    }
    final fileSystem = _remote.fileSystem;
    _confirmingDelete = true;
    try {
      final tr = context.tr;
      const shown = 6;
      final listed = entries.take(shown).map((e) => e.name).join('\n');
      final confirmed = await RouteUtils.showAcrylicDialog<bool>(
        context: context,
        builder: (context) => CbDialog(
          title: tr.sshRemoteDeleteConfirm(entries.length),
          subtitle: entries.length > shown
              ? '$listed\n+${entries.length - shown}'
              : listed,
          icon: PhosphorIconsLight.trash,
          width: 460,
          actions: [
            CbButton(
              label: tr.cancel,
              autofocus: true,
              onPressed: () => Navigator.pop(context),
            ),
            CbButton(
              key: const ValueKey('sftp-transfer-confirm-delete'),
              label: tr.delete,
              variant: CbButtonVariant.danger,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || fileSystem != _remote.fileSystem) {
        return;
      }
      setState(() => _clip = null);
      await _remoteWork((fs) => deleteTransferEntries(fs, entries));
    } finally {
      _confirmingDelete = false;
    }
  }

  // ─── Layout ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return ScreenScaffold(
      selectionState: const SelectionState(),
      isNetworkPath: true,
      isDesktop: isDesktopPlatform,
      onClearSelection: () {},
      showRemoveTagsDialog: (_) {},
      showManageAllTagsDialog: (_) {},
      showDeleteConfirmationDialog: (_) {},
      showAppBar: true,
      showSearchBar: false,
      searchBar: const SizedBox.shrink(),
      pathNavigationBar: Row(
        children: [
          CbButton.icon(
            icon: PhosphorIconsLight.house,
            tooltip: tr.sshWorkspace,
            onPressed: () => navigateNetworkTab(context, widget.tabId, '#ssh'),
          ),
          const SizedBox(width: CbSpacing.xs),
          Expanded(
            child: Text(
              _profile == null
                  ? tr.sshFileTransfer
                  : '${tr.sshFileTransfer} · ${_profile!.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        CbButton.icon(
          icon: PhosphorIconsLight.arrowClockwise,
          tooltip: tr.refresh,
          onPressed: () {
            unawaited(_local.refresh());
            unawaited(_remote.refresh());
          },
        ),
      ],
      body: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sideBySide = constraints.maxWidth >= _sideBySideWidth;
                  final local = _localPane(context);
                  final remote = _remotePane(context);
                  const gap = SizedBox.square(dimension: CbSpacing.sm);
                  return Padding(
                    padding: const EdgeInsets.all(CbSpacing.sm),
                    child: sideBySide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: local),
                              gap,
                              Expanded(child: remote),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: local),
                              gap,
                              Expanded(child: remote),
                            ],
                          ),
                  );
                },
              ),
            ),
            if (_task != null)
              _progressBar(context)
            else if (_working)
              const LinearProgressIndicator(minHeight: 3),
          ],
        ),
      ),
    );
  }

  bool get _canTransfer =>
      _task == null && !_working && _remote.fileSystem != null;

  Widget _localPane(BuildContext context) {
    final tr = context.tr;
    return _TransferPane(
      key: const ValueKey('sftp-transfer-local'),
      side: _PaneSide.local,
      controller: _local,
      header: _PaneTitle(icon: PhosphorIconsLight.desktop, title: tr.thisPC),
      transferIcon: PhosphorIconsLight.uploadSimple,
      transferLabel: tr.sshUploadToServer,
      canTransfer: _canTransfer,
      onTransfer: (entries) => _transfer(upload: true, entries: entries),
      onDrop: (entries) => _transfer(upload: false, entries: entries),
      onNewFolder: () => _newFolder(_local),
      onBrowse: _browseLocal,
    );
  }

  Widget _remotePane(BuildContext context) {
    final tr = context.tr;
    final connected = _remote.fileSystem != null;
    final profiles = [..._store.profiles]
      ..sort((a, b) => TextUtils.compareNatural(a.name, b.name));
    return _TransferPane(
      key: const ValueKey('sftp-transfer-remote'),
      side: _PaneSide.remote,
      controller: _remote,
      header: Row(
        children: [
          Icon(
            PhosphorIconsLight.hardDrives,
            size: CbSizes.iconMd,
            color: context.cbColors.iconSubtle,
          ),
          const SizedBox(width: CbSpacing.sm),
          Expanded(
            child: CbSelect<String>(
              key: const ValueKey('sftp-transfer-host'),
              size: CbSelectSize.sm,
              expand: true,
              searchable: profiles.length > 8,
              placeholder: tr.sshChooseHost,
              value: _profile?.id,
              items: [
                for (final p in profiles)
                  CbSelectItem(
                    value: p.id,
                    label: '${p.name}  ·  ${p.username}@${p.host}',
                    triggerLabel: p.name,
                    keywords: '${p.host} ${p.username} ${p.group}',
                  ),
              ],
              onChanged: _task != null
                  ? null
                  : (id) {
                      final profile = profiles
                          .where((p) => p.id == id)
                          .firstOrNull;
                      if (profile != null) unawaited(_connect(profile));
                    },
            ),
          ),
          const SizedBox(width: CbSpacing.xs),
          if (connected)
            CbButton.icon(
              icon: PhosphorIconsLight.plugsConnected,
              tooltip: tr.disconnect,
              size: CbButtonSize.sm,
              onPressed: _task != null ? null : _disconnect,
            )
          else
            CbButton.icon(
              icon: PhosphorIconsLight.plugs,
              tooltip: tr.connect,
              size: CbButtonSize.sm,
              loading: _connecting,
              onPressed: _profile == null || _connecting
                  ? null
                  : () => _connect(_profile!),
            ),
        ],
      ),
      placeholder: connected ? null : _remotePlaceholder(context),
      transferIcon: PhosphorIconsLight.downloadSimple,
      transferLabel: tr.sshDownloadToComputer,
      canTransfer: _canTransfer,
      onTransfer: (entries) => _transfer(upload: false, entries: entries),
      onDrop: (entries) => _transfer(upload: true, entries: entries),
      onNewFolder: () => _newFolder(_remote),
      actions: _PaneActions(
        onCopy: (entries) => _hold(entries, cut: false),
        onCut: (entries) => _hold(entries, cut: true),
        onPaste: _clip == null ? null : _paste,
        onRename: _renameEntry,
        onDelete: _delete,
      ),
    );
  }

  Widget _remotePlaceholder(BuildContext context) {
    final tr = context.tr;
    final c = context.cbColors;
    final hasProfiles = _store.profiles.isNotEmpty;
    final String message;
    final Widget? action;
    if (_connecting) {
      message = tr.sshConnecting;
      action = null;
    } else if (_connectError != null) {
      message = _connectError!;
      action = _profile == null
          ? null
          : CbButton(
              icon: PhosphorIconsLight.arrowClockwise,
              label: tr.sshReconnect,
              onPressed: () => _connect(_profile!),
            );
    } else if (!hasProfiles) {
      message = tr.sshNoHosts;
      action = CbButton(
        icon: PhosphorIconsLight.plus,
        label: tr.sshAddHost,
        variant: CbButtonVariant.primary,
        onPressed: () => navigateNetworkTab(context, widget.tabId, '#ssh'),
      );
    } else {
      message = tr.sshChooseHostHint;
      action = null;
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CbSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_connecting)
              const SizedBox.square(
                dimension: CbSizes.iconXl,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                _connectError != null
                    ? PhosphorIconsLight.warningCircle
                    : PhosphorIconsLight.hardDrives,
                size: CbSizes.iconXl,
                color: _connectError != null ? c.status.danger : c.iconSubtle,
              ),
            const SizedBox(height: CbSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: SelectableText(
                message,
                textAlign: TextAlign.center,
                style: CbTypography.body.copyWith(color: c.textSecondary),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: CbSpacing.md),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _progressBar(BuildContext context) {
    final tr = context.tr;
    final c = context.cbColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.strokeSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CbSpacing.lg,
          CbSpacing.sm,
          CbSpacing.sm,
          CbSpacing.sm,
        ),
        child: ValueListenableBuilder<TransferProgress?>(
          valueListenable: _progress,
          builder: (context, progress, _) {
            final sizes = progress == null || progress.bytesTotal == 0
                ? ''
                : ' · ${FormatUtils.formatFileSize(progress.bytesDone)}'
                      ' / ${FormatUtils.formatFileSize(progress.bytesTotal)}';
            final speed = progress == null || progress.bytesPerSecond < 1
                ? ''
                : ' · ${FormatUtils.formatFileSize(progress.bytesPerSecond.round())}/s';
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        progress == null
                            ? tr.sshConnecting
                            : '${tr.sshTransferProgress(progress.filesDone, progress.filesTotal)}'
                                  '$sizes$speed · ${progress.current}',
                        style: CbTypography.bodySm.copyWith(
                          color: c.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: CbSpacing.xs),
                      LinearProgressIndicator(
                        minHeight: 3,
                        value: progress?.fraction,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CbSpacing.sm),
                CbButton(
                  key: const ValueKey('sftp-transfer-cancel'),
                  icon: PhosphorIconsLight.x,
                  label: tr.cancel,
                  size: CbButtonSize.sm,
                  onPressed: _task?.cancel,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _PaneSide { local, remote }

class _TransferDrag {
  final _PaneSide from;
  final List<TransferEntry> entries;
  const _TransferDrag(this.from, this.entries);
}

/// Listing, navigation and selection of one pane.
class _PaneController extends ChangeNotifier {
  _PaneController(this.fileSystem);

  TransferFileSystem? fileSystem;
  String path = '';
  List<TransferEntry> entries = const [];
  final selected = <String>{};

  /// [anchor] starts a Shift range; [cursor] is the row arrow keys move from.
  String? anchor, cursor;
  bool loading = false;
  Object? error;
  int _ticket = 0;
  bool _disposed = false;

  List<TransferEntry>? _selectedEntriesCache;
  Set<String> _entryPaths = const {};
  List<TransferEntry> get selectedEntries => _selectedEntriesCache ??= entries
      .where((e) => selected.contains(e.path))
      .toList(growable: false);

  void _notify() {
    _selectedEntriesCache = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> openHome() async {
    final fs = fileSystem;
    if (fs == null) return;
    String home;
    try {
      home = await fs.home();
    } catch (_) {
      home = '';
    }
    if (fs == fileSystem) await navigate(home);
  }

  Future<void> attach(TransferFileSystem fs) {
    fileSystem = fs;
    return openHome();
  }

  void detach() {
    _ticket++;
    fileSystem = null;
    path = '';
    entries = const [];
    _entryPaths = const {};
    selected.clear();
    anchor = cursor = null;
    loading = false;
    error = null;
    _notify();
  }

  Future<void> navigate(String target, {Set<String>? keepSelection}) async {
    final fs = fileSystem;
    if (fs == null) return;
    final ticket = ++_ticket;
    loading = true;
    error = null;
    _notify();
    try {
      final list = await fs.list(target);
      if (ticket != _ticket) return;
      list.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return TextUtils.compareNatural(a.name, b.name);
      });
      path = target;
      entries = list;
      _entryPaths = list.map((e) => e.path).toSet();
      selected
        ..clear()
        ..addAll(keepSelection?.where(_entryPaths.contains) ?? const []);
      if (!selected.contains(anchor)) anchor = null;
      if (!selected.contains(cursor)) cursor = null;
    } catch (e) {
      if (ticket == _ticket) error = e;
    } finally {
      if (ticket == _ticket) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> refresh({String? select}) =>
      navigate(path, keepSelection: select == null ? {...selected} : {select});

  Future<void> up() async {
    final parent = fileSystem?.parent(path);
    if (parent != null) await navigate(parent);
  }

  void select(TransferEntry entry, {bool toggle = false, bool range = false}) {
    cursor = entry.path;
    if (range && anchor != null) {
      final from = entries.indexWhere((e) => e.path == anchor);
      final to = entries.indexOf(entry);
      if (from >= 0 && to >= 0) {
        if (!toggle) selected.clear();
        final lo = from < to ? from : to, hi = from < to ? to : from;
        selected.addAll(entries.sublist(lo, hi + 1).map((e) => e.path));
        _notify();
        return;
      }
    }
    if (toggle) {
      if (!selected.remove(entry.path)) selected.add(entry.path);
    } else {
      selected
        ..clear()
        ..add(entry.path);
    }
    anchor = entry.path;
    _notify();
  }

  void selectAll() {
    selected
      ..clear()
      ..addAll(entries.map((e) => e.path));
    _notify();
  }

  void replaceSelection(Iterable<String> paths) {
    selected
      ..clear()
      ..addAll(paths.where(_entryPaths.contains));
    anchor = cursor = selected.lastOrNull;
    _notify();
  }

  void clearSelection() {
    if (selected.isEmpty) return;
    selected.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _PaneTitle extends StatelessWidget {
  const _PaneTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return SizedBox(
      height: CbSizes.controlSm,
      child: Row(
        children: [
          Icon(icon, size: CbSizes.iconMd, color: c.iconSubtle),
          const SizedBox(width: CbSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: CbTypography.label.copyWith(color: c.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// File operations inside one pane's own file system.
class _PaneActions {
  const _PaneActions({
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    required this.onRename,
    required this.onDelete,
  });
  final void Function(List<TransferEntry> entries) onCopy, onCut, onDelete;
  final void Function(TransferEntry entry) onRename;

  /// Null while nothing waits to be pasted.
  final VoidCallback? onPaste;
}

class _TransferPane extends StatefulWidget {
  const _TransferPane({
    super.key,
    required this.side,
    required this.controller,
    required this.header,
    required this.transferIcon,
    required this.transferLabel,
    required this.canTransfer,
    required this.onTransfer,
    required this.onDrop,
    required this.onNewFolder,
    this.onBrowse,
    this.actions,
    this.placeholder,
  });

  final _PaneSide side;
  final _PaneController controller;
  final Widget header;

  /// Replaces the listing, e.g. while the remote side is disconnected.
  final Widget? placeholder;
  final IconData transferIcon;
  final String transferLabel;
  final bool canTransfer;

  /// Sends entries from this pane to the other one.
  final void Function(List<TransferEntry> entries) onTransfer;

  /// Receives entries dragged from the other pane.
  final void Function(List<TransferEntry> entries) onDrop;
  final VoidCallback onNewFolder;

  /// Picks this pane's folder in a native dialog; null where there is none.
  final VoidCallback? onBrowse;

  /// Copy, move, rename and delete inside this pane; null where unsupported.
  final _PaneActions? actions;

  @override
  State<_TransferPane> createState() => _TransferPaneState();
}

class _TransferPaneState extends State<_TransferPane> {
  static const _viewModes = {ViewMode.list, ViewMode.details, ViewMode.grid};
  String get _viewPreference => 'sftp_transfer_${widget.side.name}';
  late final _view = GridListViewController(
    initialMode: ViewMode.details,
    supportedModes: _viewModes,
    load: () => UserPreferences.instance.getGridListCollectionMode(
      _viewPreference,
      supportedModes: _viewModes,
      fallback: ViewMode.details,
    ),
    save: (mode) => UserPreferences.instance.setGridListCollectionMode(
      _viewPreference,
      mode,
    ),
  );
  late final _scale = CollectionViewScaleController(
    view: _view,
    loadZoom: () =>
        UserPreferences.instance.getCollectionGridZoomLevel(_viewPreference),
    saveZoom: (zoom) => UserPreferences.instance.setCollectionGridZoomLevel(
      _viewPreference,
      zoom,
    ),
  );
  double _viewportWidth = 600;

  void _changePresentation(Future<void> action) => unawaited(
    action.catchError((Object error) {
      if (mounted) AppToast.error(context, error.toString());
    }),
  );
  final _path = TextEditingController();
  final _focus = FocusNode(debugLabel: 'transfer pane');
  final _scroll = ScrollController();
  final _dragBloc = SelectionBloc();
  late final _dragSelection = TabbedFolderDragSelectionController(
    selectionBloc: _dragBloc,
    folderPaths: () =>
        _pane.entries.where((e) => e.isDirectory).map((e) => e.path),
  );
  late final StreamSubscription<SelectionState> _dragSubscription;
  String? _shownPath;

  _PaneController get _pane => widget.controller;

  @override
  void initState() {
    super.initState();
    _pane.addListener(_changed);
    _view.addListener(_changed);
    _scale.addListener(_changed);
    _changePresentation(_scale.initialize());
    _dragSubscription = _dragBloc.stream.listen((selection) {
      _pane.replaceSelection(selection.allSelectedPaths);
    });
  }

  @override
  void didUpdateWidget(_TransferPane old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _scale.dispose();
    _view.dispose();
    _dragSubscription.cancel();
    _dragSelection.dispose();
    _dragBloc.close();
    _pane.removeListener(_changed);
    _path.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _open(TransferEntry entry) {
    if (entry.isDirectory) {
      unawaited(_pane.navigate(entry.path));
    } else if (widget.canTransfer) {
      widget.onTransfer([entry]);
    }
  }

  static const double _rowExtent = 30, _listPadding = CbSpacing.xs;

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final grid = _view.mode == ViewMode.grid;
    final columns = GridZoomConstraints.columnCountForZoom(
      _scale.zoom,
      _viewportWidth - 8,
    );
    final extent = grid
        ? (_viewportWidth / columns).clamp(90.0, 160.0)
        : _rowExtent;
    final row = grid ? index ~/ columns : index;
    final top = _listPadding + row * (extent + (grid ? 4 : 0));
    final bottom = top + extent + _listPadding;
    if (top < position.pixels) {
      _scroll.jumpTo(top - _listPadding);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (bottom - position.viewportDimension).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  /// Whether [_TransferPane.actions] may run now.
  bool get _canAct =>
      widget.actions != null &&
      widget.canTransfer &&
      widget.placeholder == null &&
      _pane.fileSystem != null;

  /// The file menu for the current selection, opened at [position].
  void _showMenu(Offset position) {
    final actions = widget.actions;
    if (actions == null || !_canAct) return;
    final tr = context.tr;
    final selected = _pane.selectedEntries;
    unawaited(
      showContextMenuPopup(
        context: context,
        globalPosition: position,
        sections: [
          ContextMenuSection(
            actions: [
              if (selected.isNotEmpty) ...[
                ContextMenuAction(
                  id: 'cut',
                  label: tr.cut,
                  icon: PhosphorIconsLight.scissors,
                  onSelected: (_) => actions.onCut(selected),
                ),
                ContextMenuAction(
                  id: 'copy',
                  label: tr.copy,
                  icon: PhosphorIconsLight.copy,
                  onSelected: (_) => actions.onCopy(selected),
                ),
              ],
              if (actions.onPaste != null)
                ContextMenuAction(
                  id: 'paste',
                  label: tr.pasteHere,
                  icon: PhosphorIconsLight.clipboardText,
                  onSelected: (_) => actions.onPaste!(),
                ),
              if (selected.isNotEmpty)
                ContextMenuAction(
                  id: 'delete',
                  label: tr.delete,
                  icon: PhosphorIconsLight.trash,
                  isDestructive: true,
                  onSelected: (_) => actions.onDelete(selected),
                ),
              if (selected.length == 1)
                ContextMenuAction(
                  id: 'rename',
                  label: tr.rename,
                  icon: PhosphorIconsLight.pencilSimple,
                  onSelected: (_) => actions.onRename(selected.single),
                ),
            ],
          ),
          ContextMenuSection(
            actions: [
              ContextMenuAction(
                id: 'new_folder',
                label: tr.newFolder,
                icon: PhosphorIconsLight.folderPlus,
                onSelected: (_) => widget.onNewFolder(),
              ),
              ContextMenuAction(
                id: 'refresh',
                label: tr.refresh,
                icon: PhosphorIconsLight.arrowClockwise,
                onSelected: (_) => unawaited(_pane.refresh()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!TabFocusGate.isActiveTab(context)) return KeyEventResult.ignored;
    if (DesktopShortcuts.isTextInputFocused) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (key == LogicalKeyboardKey.backspace ||
        (keyboard.isAltPressed && key == LogicalKeyboardKey.arrowUp)) {
      unawaited(_pane.up());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final selected = _pane.selectedEntries;
      if (selected.length == 1 && selected.single.isDirectory) {
        _open(selected.single);
      } else if (selected.isNotEmpty && widget.canTransfer) {
        widget.onTransfer(selected);
      }
      return KeyEventResult.handled;
    }
    final actions = _canAct ? widget.actions : null;
    if (actions != null) {
      final selected = _pane.selectedEntries;
      if (key == LogicalKeyboardKey.f2 && selected.length == 1) {
        actions.onRename(selected.single);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.delete && selected.isNotEmpty) {
        actions.onDelete(selected);
        return KeyEventResult.handled;
      }
      if (ctrl && key == LogicalKeyboardKey.keyC && selected.isNotEmpty) {
        actions.onCopy(selected);
        return KeyEventResult.handled;
      }
      if (ctrl && key == LogicalKeyboardKey.keyX && selected.isNotEmpty) {
        actions.onCut(selected);
        return KeyEventResult.handled;
      }
      if (ctrl && key == LogicalKeyboardKey.keyV && actions.onPaste != null) {
        actions.onPaste!();
        return KeyEventResult.handled;
      }
    }
    if (ctrl && key == LogicalKeyboardKey.keyA) {
      _pane.selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f5) {
      unawaited(_pane.refresh());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _pane.clearSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final entries = _pane.entries;
      if (entries.isEmpty) return KeyEventResult.handled;
      final current = entries.indexWhere((e) => e.path == _pane.cursor);
      final next = current < 0
          ? 0
          : (current + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(
              0,
              entries.length - 1,
            );
      _pane.select(entries[next], range: keyboard.isShiftPressed);
      _reveal(next);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final c = context.cbColors;
    final fs = _pane.fileSystem;
    final active = fs != null && widget.placeholder == null;
    final displayPath = _pane.path.isEmpty && fs != null
        ? tr.thisPC
        : _pane.path;
    if (_shownPath != displayPath) {
      _shownPath = displayPath;
      _path.text = displayPath;
    }
    final selectedCount = _pane.selected.length;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKey,
      child: DragTarget<_TransferDrag>(
        onWillAcceptWithDetails: (details) =>
            active && widget.canTransfer && details.data.from != widget.side,
        onAcceptWithDetails: (details) => widget.onDrop(details.data.entries),
        builder: (context, candidates, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: CbRadii.mdAll,
            border: Border.all(
              color: candidates.isNotEmpty ? c.accent.base : c.strokeSubtle,
              width: candidates.isNotEmpty
                  ? CbStrokes.emphasis
                  : CbStrokes.hairline,
            ),
          ),
          child: ClipRRect(
            borderRadius: CbRadii.mdAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CbSpacing.md,
                    CbSpacing.sm,
                    CbSpacing.sm,
                    CbSpacing.xs,
                  ),
                  child: widget.header,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: CbSpacing.sm),
                  child: Row(
                    children: [
                      CbButton.icon(
                        icon: PhosphorIconsLight.arrowUp,
                        tooltip: tr.parentFolder,
                        size: CbButtonSize.sm,
                        onPressed: active && fs.parent(_pane.path) != null
                            ? () => _pane.up()
                            : null,
                      ),
                      const SizedBox(width: CbSpacing.xs),
                      Expanded(child: _addressBar(context, active)),
                      const SizedBox(width: CbSpacing.xs),
                      CbButton.icon(
                        icon: PhosphorIconsLight.arrowClockwise,
                        tooltip: tr.refresh,
                        size: CbButtonSize.sm,
                        onPressed: active ? () => _pane.refresh() : null,
                      ),
                      CbButton.icon(
                        icon: PhosphorIconsLight.folderPlus,
                        tooltip: tr.newFolder,
                        size: CbButtonSize.sm,
                        onPressed: active && _pane.path.isNotEmpty
                            ? widget.onNewFolder
                            : null,
                      ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: GridListViewToggle(
                          mode: _view.mode,
                          supportedModes: _viewModes,
                          onChanged: (mode) =>
                              _changePresentation(_view.select(mode)),
                        ),
                      ),
                      if (_view.mode == ViewMode.grid)
                        CbButton.icon(
                          key: ValueKey(
                            'sftp-transfer-zoom-${widget.side.name}',
                          ),
                          icon: PhosphorIconsLight.magnifyingGlassPlus,
                          tooltip: tr.adjustGridSizeTooltip,
                          size: CbButtonSize.sm,
                          onPressed: () => SharedActionBar.showGridSizeDialog(
                            context,
                            currentGridSize: _scale.zoom,
                            onApply: (zoom) =>
                                _changePresentation(_scale.setZoom(zoom)),
                          ),
                        ),
                      if (widget.actions != null)
                        CbButton.icon(
                          key: ValueKey(
                            'sftp-transfer-delete-${widget.side.name}',
                          ),
                          icon: PhosphorIconsLight.trash,
                          tooltip: tr.delete,
                          size: CbButtonSize.sm,
                          onPressed: _canAct && selectedCount > 0
                              ? () => widget.actions!.onDelete(
                                  _pane.selectedEntries,
                                )
                              : null,
                        ),
                      if (widget.actions != null)
                        Builder(
                          builder: (context) => CbButton.icon(
                            key: ValueKey(
                              'sftp-transfer-more-${widget.side.name}',
                            ),
                            icon: PhosphorIconsLight.dotsThree,
                            tooltip: tr.moreOptions,
                            size: CbButtonSize.sm,
                            onPressed: !_canAct
                                ? null
                                : () {
                                    final box =
                                        context.findRenderObject()!
                                            as RenderBox;
                                    _showMenu(
                                      box.localToGlobal(
                                        box.size.bottomLeft(Offset.zero),
                                      ),
                                    );
                                  },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: CbSpacing.xs),
                if (_pane.loading && active)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  const SizedBox(height: 2),
                if (_pane.error != null && active) _error(context),
                Expanded(child: widget.placeholder ?? _list(context, active)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.strokeSubtle)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CbSpacing.md,
                      CbSpacing.xs,
                      CbSpacing.xs,
                      CbSpacing.xs,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final enabled =
                            active && widget.canTransfer && selectedCount > 0;
                        void send() => widget.onTransfer(_pane.selectedEntries);
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                active
                                    ? tr.sshPaneStatus(
                                        _pane.entries.length,
                                        selectedCount,
                                      )
                                    : '',
                                style: CbTypography.caption.copyWith(
                                  color: c.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (constraints.maxWidth < 360)
                              CbButton.icon(
                                key: ValueKey(
                                  'sftp-transfer-send-${widget.side.name}',
                                ),
                                icon: widget.transferIcon,
                                tooltip: widget.transferLabel,
                                variant: CbButtonVariant.primary,
                                size: CbButtonSize.sm,
                                onPressed: enabled ? send : null,
                              )
                            else
                              CbButton(
                                key: ValueKey(
                                  'sftp-transfer-send-${widget.side.name}',
                                ),
                                icon: widget.transferIcon,
                                label: widget.transferLabel,
                                variant: CbButtonVariant.primary,
                                size: CbButtonSize.sm,
                                onPressed: enabled ? send : null,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The folder chain as clickable crumbs; a click on the rest of the bar
  /// switches to typing a path, and the trailing button browses for one.
  Widget _addressBar(BuildContext context, bool active) {
    final tr = context.tr;
    final c = context.cbColors;
    final fs = _pane.fileSystem;
    final chain = <String>[];
    if (active && fs != null) {
      for (
        String? path = _pane.path;
        path != null && chain.length < 64;
        path = fs.parent(path)
      ) {
        chain.insert(0, path);
      }
    }
    String label(String path) {
      if (path.isEmpty) return tr.thisPC;
      final name = fs!.paths.basename(path);
      return name.length > 1 ? name.replaceAll(RegExp(r'[\\/]+$'), '') : name;
    }

    return Container(
      height: CbSizes.controlMd,
      decoration: BoxDecoration(
        color: active ? c.surfaceSunken : c.fillSubtle,
        borderRadius: CbRadii.mdAll,
        border: Border.all(color: c.strokeSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: !active
                ? const SizedBox.shrink()
                : Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    // Abandoned typing must not show up on the next edit.
                    onFocusChange: (focused) {
                      if (!focused) _path.text = _shownPath ?? '';
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: CbSpacing.xxs),
                      child: BreadcrumbAddressBar(
                        key: ValueKey('sftp-transfer-path-${widget.side.name}'),
                        segments: [
                          for (final (index, path) in chain.indexed)
                            BreadcrumbSegment(
                              label: label(path),
                              icon: index > 0
                                  ? null
                                  : path.isEmpty
                                  ? PhosphorIconsLight.desktop
                                  : PhosphorIconsLight.hardDrive,
                              onTap: index == chain.length - 1
                                  ? null
                                  : () => unawaited(_pane.navigate(path)),
                            ),
                        ],
                        editController: _path,
                        onPathSubmitted: (value) {
                          final target = value.trim();
                          unawaited(
                            _pane.navigate(target == tr.thisPC ? '' : target),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          if (widget.onBrowse != null)
            CbButton.icon(
              key: ValueKey('sftp-transfer-browse-${widget.side.name}'),
              icon: PhosphorIconsLight.folderOpen,
              tooltip: tr.selectFolder,
              size: CbButtonSize.sm,
              onPressed: active ? widget.onBrowse : null,
            ),
          if (widget.onBrowse != null) const SizedBox(width: CbSpacing.xxs),
        ],
      ),
    );
  }

  Widget _error(BuildContext context) {
    final c = context.cbColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        CbSpacing.sm,
        CbSpacing.xs,
        CbSpacing.sm,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: CbSpacing.sm,
        vertical: CbSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.status.dangerSurface,
        borderRadius: CbRadii.smAll,
      ),
      child: Text(
        '${_pane.error}',
        style: CbTypography.bodySm.copyWith(color: c.status.danger),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _list(BuildContext context, bool active) {
    final c = context.cbColors;
    if (!active) return const SizedBox.shrink();
    return FileViewShell(
      viewMode: _view.mode,
      enableKeyboardShortcuts: false,
      onViewScaleDelta: (delta) =>
          _changePresentation(_scale.step(delta, _viewportWidth)),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (_) {
            _focus.requestFocus();
            _dragBloc.add(
              SelectItemsInRect(
                filePaths: _pane.selectedEntries
                    .where((e) => !e.isDirectory)
                    .map((e) => e.path)
                    .toSet(),
                folderPaths: _pane.selectedEntries
                    .where((e) => e.isDirectory)
                    .map((e) => e.path)
                    .toSet(),
                isCtrlPressed: false,
                isShiftPressed: false,
              ),
            );
          },
          child: DragSelectionRegion(
            controller: _dragSelection,
            enabled: isDesktopPlatform,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _focus.requestFocus();
                _pane.clearSelection();
              },
              onSecondaryTapUp: (details) {
                _focus.requestFocus();
                _pane.clearSelection();
                _showMenu(details.globalPosition);
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewportWidth = constraints.maxWidth;
                  if (_pane.entries.isEmpty) {
                    if (_pane.loading) return const SizedBox.shrink();
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsLight.folderOpen,
                            size: CbSizes.iconXl,
                            color: c.iconSubtle,
                          ),
                          const SizedBox(height: CbSpacing.sm),
                          Text(
                            context.tr.emptyFolder,
                            style: CbTypography.body.copyWith(
                              color: c.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (_view.mode == ViewMode.grid) {
                    final columns = GridZoomConstraints.columnCountForZoom(
                      _scale.zoom,
                      constraints.maxWidth - 8,
                    );
                    return Scrollbar(
                      controller: _scroll,
                      child: GridView.builder(
                        key: ValueKey('sftp-transfer-grid-${widget.side.name}'),
                        controller: _scroll,
                        padding: const EdgeInsets.all(4),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          mainAxisExtent: (constraints.maxWidth / columns)
                              .clamp(90.0, 160.0),
                        ),
                        itemCount: _pane.entries.length,
                        itemBuilder: (context, index) => _row(
                          context,
                          _pane.entries[index],
                          showSize: false,
                          showModified: false,
                          grid: true,
                        ),
                      ),
                    );
                  }
                  final showModified =
                      _view.mode == ViewMode.details &&
                      constraints.maxWidth >= 440;
                  final showSize =
                      _view.mode == ViewMode.details &&
                      constraints.maxWidth >= 280;
                  final tr = context.tr;
                  final heading = CbTypography.caption.copyWith(
                    color: c.textTertiary,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: CbSizes.controlXs,
                        padding: const EdgeInsets.symmetric(
                          horizontal: CbSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: c.strokeSubtle),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: CbSizes.iconMd + CbSpacing.sm,
                            ),
                            Expanded(
                              child: Text(
                                tr.columnName,
                                style: heading,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (showSize)
                              SizedBox(
                                width: 72,
                                child: Text(
                                  tr.columnSize,
                                  style: heading,
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (showModified)
                              SizedBox(
                                width: 112,
                                child: Text(
                                  tr.columnDateModified,
                                  style: heading,
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _scroll,
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(
                              vertical: _listPadding,
                            ),
                            itemExtent: _rowExtent,
                            itemCount: _pane.entries.length,
                            itemBuilder: (context, index) => _row(
                              context,
                              _pane.entries[index],
                              showSize: showSize,
                              showModified: showModified,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    TransferEntry entry, {
    required bool showSize,
    required bool showModified,
    bool grid = false,
  }) {
    final c = context.cbColors;
    final selected = _pane.selected.contains(entry.path);
    final meta = CbTypography.caption.copyWith(
      color: c.textTertiary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final row = _HoverRow(
      selected: selected,
      builder: (hovered) => Container(
        color: ItemInteractionStyle.backgroundColor(
          theme: Theme.of(context),
          isDesktopMode: isDesktopPlatform,
          isSelected: selected,
          isHovering: hovered,
        ),
        padding: EdgeInsets.symmetric(horizontal: grid ? 4 : CbSpacing.md),
        child: grid
            ? LayoutBuilder(
                builder: (context, constraints) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      entry.isDirectory
                          ? PhosphorIconsFill.folder
                          : PhosphorIconsLight.file,
                      size: (constraints.maxWidth * 0.4).clamp(20.0, 48.0),
                      color: c.accent.text,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: CbTypography.bodySm,
                    ),
                  ],
                ),
              )
            : Row(
                children: [
                  Icon(
                    entry.isLink
                        ? PhosphorIconsLight.link
                        : entry.isDirectory
                        ? PhosphorIconsFill.folder
                        : PhosphorIconsLight.file,
                    size: CbSizes.iconMd,
                    color: entry.isDirectory ? c.accent.text : c.iconSubtle,
                  ),
                  const SizedBox(width: CbSpacing.sm),
                  Expanded(
                    child: Text(
                      entry.name,
                      style: CbTypography.body.copyWith(color: c.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showSize)
                    SizedBox(
                      width: 72,
                      child: Text(
                        entry.isDirectory
                            ? ''
                            : FormatUtils.formatFileSize(entry.size),
                        style: meta,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                      ),
                    ),
                  if (showModified)
                    SizedBox(
                      width: 112,
                      child: Text(
                        entry.modified == null
                            ? ''
                            : _modifiedFormat.format(entry.modified!),
                        style: meta,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
      ),
    );
    final interactive = OptimizedInteractionLayer(
      onTap: () {
        _focus.requestFocus();
        final keyboard = HardwareKeyboard.instance;
        _pane.select(
          entry,
          toggle: keyboard.isControlPressed || keyboard.isMetaPressed,
          range: keyboard.isShiftPressed,
        );
      },
      onDoubleTap: () => _open(entry),
      onSecondaryTapUp: (details) {
        _focus.requestFocus();
        if (!selected) _pane.select(entry);
        _showMenu(details.globalPosition);
      },
      child: row,
    );
    final dragged = selected ? _pane.selectedEntries : [entry];
    final feedback = Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.md,
          vertical: CbSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: CbRadii.mdAll,
          boxShadow: context.cb.shadowLevel1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.transferIcon,
              size: CbSizes.iconMd,
              color: c.accent.text,
            ),
            const SizedBox(width: CbSpacing.sm),
            Text(
              dragged.length == 1
                  ? dragged.single.name
                  : context.tr.sshPaneStatus(dragged.length, 0),
              style: CbTypography.label.copyWith(color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
    final data = _TransferDrag(widget.side, dragged);
    final draggable = isDesktopPlatform
        ? Draggable<_TransferDrag>(
            data: data,
            feedback: feedback,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            child: interactive,
          )
        : LongPressDraggable<_TransferDrag>(
            data: data,
            feedback: feedback,
            child: interactive,
          );
    return SelectionGeometryItem(
      path: entry.path,
      isFolder: entry.isDirectory,
      controller: _dragSelection,
      child: draggable,
    );
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.selected, required this.builder});
  final bool selected;
  final Widget Function(bool hovered) builder;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Semantics(
      selected: widget.selected,
      button: true,
      child: widget.builder(_hovered),
    ),
  );
}

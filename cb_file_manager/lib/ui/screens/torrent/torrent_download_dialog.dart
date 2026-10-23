import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../components/common/soft_checkbox.dart';
import '../../../services/torrent/torrent_download_options.dart';

export '../../../services/torrent/torrent_download_options.dart';

class TorrentDownloadDialog extends StatefulWidget {
  final String name;
  final String initialDestination;
  final bool startImmediately;
  final bool destinationLocked;

  /// A standalone host supplies this callback instead of popping a route.
  final ValueChanged<TorrentDownloadOptions?>? onComplete;

  /// Fires after this form's first painted frame, including localization load.
  final VoidCallback? onReady;
  final VoidCallback? onWindowDrag;
  final VoidCallback? onWindowMinimize;

  const TorrentDownloadDialog({
    super.key,
    required this.name,
    required this.initialDestination,
    this.startImmediately = true,
    this.destinationLocked = false,
    this.onComplete,
    this.onReady,
    this.onWindowDrag,
    this.onWindowMinimize,
  });

  @override
  State<TorrentDownloadDialog> createState() => _TorrentDownloadDialogState();
}

class _TorrentDownloadDialogState extends State<TorrentDownloadDialog> {
  late final _destination = TextEditingController(
    text: widget.initialDestination,
  );
  late bool _start = widget.startImmediately;
  bool _choosing = false;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.onReady != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onReady?.call();
      });
    }
  }

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    if (widget.destinationLocked || _choosing) return;
    setState(() => _choosing = true);
    try {
      // Windows' folder picker rejects a missing initial directory before it
      // opens. A typed new folder should still allow browsing from its parent.
      String? initial;
      var candidate = _destination.text.trim();
      if (p.isAbsolute(candidate)) {
        candidate = p.normalize(candidate);
        while (true) {
          try {
            if (await Directory(candidate).exists()) {
              initial = candidate;
              break;
            }
          } on FileSystemException {
            break;
          }
          final parent = p.dirname(candidate);
          if (parent == candidate) break;
          candidate = parent;
        }
      }
      if (!mounted) return;
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: AppLocalizations.of(context)!.torrentColumn('destination'),
        initialDirectory: initial,
        windowsOptions: const WindowsOptions(lockParentWindow: true),
      );
      if (!mounted || directory == null || directory.trim().isEmpty) return;
      setState(() {
        _destination.text = directory;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  void _submit() {
    if (_choosing || _closing) return;
    final destination = _destination.text.trim();
    if (!p.isAbsolute(destination) || destination.contains('\x00')) {
      setState(
        () => _error = AppLocalizations.of(context)!.torrentDestinationRequired,
      );
      return;
    }
    _closing = true;
    _finish(TorrentDownloadOptions(p.normalize(destination), _start));
  }

  void _finish(TorrentDownloadOptions? options) {
    if (widget.onComplete != null) {
      widget.onComplete!(options);
    } else {
      Navigator.pop(context, options);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Enter does the same as the Save button. Focused buttons handle their own
    // Enter first, so Cancel/Browse still activate normally.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
      },
      child: Focus(autofocus: true, child: _buildDialog(l)),
    );
  }

  Widget _buildDialog(AppLocalizations l) {
    if (widget.onComplete != null) {
      return Material(
        key: const ValueKey('torrent-download-window-form'),
        color: context.cbColors.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _windowBar(l),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.cbColors.accent.tint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      PhosphorIconsLight.downloadSimple,
                      color: context.cbColors.accent.text,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        Text(l.torrentDownload, style: CbTypography.headingLg),
                        Text(
                          widget.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.bodySm.copyWith(
                            color: context.cbColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _fields(l),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              decoration: BoxDecoration(
                color: context.cbColors.surface,
                border: Border(top: BorderSide(color: context.cbColors.stroke)),
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: CbSpacing.md,
                children: _actions(l),
              ),
            ),
          ],
        ),
      );
    }
    return CbDialog(
      title: l.torrentDownload,
      subtitle: widget.name,
      width: 680,
      content: _fields(l),
      actions: _actions(l),
    );
  }

  Widget _windowBar(AppLocalizations l) => SizedBox(
    height: 48,
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            key: const ValueKey('torrent-window-drag'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => widget.onWindowDrag?.call(),
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'CB File Hub',
                  style: CbTypography.labelSm.copyWith(
                    color: context.cbColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
        CbButton.icon(
          key: const ValueKey('torrent-window-minimize'),
          icon: PhosphorIconsLight.minus,
          tooltip: l.minimize,
          onPressed: widget.onWindowMinimize,
        ),
        const SizedBox(width: 4),
        CbButton.icon(
          key: const ValueKey('torrent-window-close'),
          icon: PhosphorIconsLight.x,
          tooltip: l.close,
          onPressed: () => _finish(null),
        ),
        const SizedBox(width: 10),
      ],
    ),
  );

  Widget _fields(AppLocalizations l) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CbTextField(
              key: const ValueKey('torrent-download-destination'),
              controller: _destination,
              label: l.torrentColumn('destination'),
              placeholder: l.selectFolder,
              readOnly: widget.destinationLocked || _choosing,
              helperText: widget.destinationLocked
                  ? l.torrentDestinationLocked
                  : null,
              errorText: _error,
              mono: true,
              onSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          const SizedBox(width: CbSpacing.md),
          Padding(
            padding: const EdgeInsets.only(top: CbSpacing.xl),
            child: CbButton(
              key: const ValueKey('torrent-download-browse'),
              label: l.browse,
              icon: PhosphorIconsLight.folderOpen,
              onPressed: widget.destinationLocked || _choosing ? null : _browse,
            ),
          ),
        ],
      ),
      const SizedBox(height: CbSpacing.xl),
      Semantics(
        checked: _start,
        child: InkWell(
          key: const ValueKey('torrent-start-immediately'),
          onTap: () => setState(() => _start = !_start),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: CbSpacing.md),
            child: Row(
              children: [
                SoftCheckboxInline(value: _start),
                const SizedBox(width: 10),
                Expanded(child: Text(l.torrentStartImmediately)),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  List<Widget> _actions(AppLocalizations l) => [
    CbButton(label: l.cancel, onPressed: () => _finish(null)),
    CbButton(
      key: const ValueKey('torrent-download-confirm'),
      label: l.save,
      variant: CbButtonVariant.primary,
      onPressed: _choosing ? null : _submit,
    ),
  ];
}

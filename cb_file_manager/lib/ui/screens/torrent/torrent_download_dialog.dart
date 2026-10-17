import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../components/common/soft_checkbox.dart';

class TorrentDownloadOptions {
  final String destination;
  final bool startImmediately;

  const TorrentDownloadOptions(this.destination, this.startImmediately);
}

class TorrentDownloadDialog extends StatefulWidget {
  final String name;
  final String initialDestination;
  final bool startImmediately;
  final bool destinationLocked;

  const TorrentDownloadDialog({
    super.key,
    required this.name,
    required this.initialDestination,
    this.startImmediately = true,
    this.destinationLocked = false,
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
  String? _error;

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
    final destination = _destination.text.trim();
    if (!p.isAbsolute(destination)) {
      setState(
        () => _error = AppLocalizations.of(context)!.torrentDestinationRequired,
      );
      return;
    }
    Navigator.pop(
      context,
      TorrentDownloadOptions(p.normalize(destination), _start),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return CbDialog(
      title: l.torrentDownload,
      subtitle: widget.name,
      width: 680,
      content: Column(
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
                  onPressed: widget.destinationLocked || _choosing
                      ? null
                      : _browse,
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
      ),
      actions: [
        CbButton(label: l.cancel, onPressed: () => Navigator.pop(context)),
        CbButton(
          key: const ValueKey('torrent-download-confirm'),
          label: l.save,
          variant: CbButtonVariant.primary,
          onPressed: _choosing ? null : _submit,
        ),
      ],
    );
  }
}

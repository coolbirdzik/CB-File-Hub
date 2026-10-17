import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';

class TorrentClientImportDialog extends StatefulWidget {
  final String client;
  final String storageMode;
  final Future<List<String>> Function() discover;

  const TorrentClientImportDialog({
    super.key,
    required this.client,
    required this.storageMode,
    required this.discover,
  });

  @override
  State<TorrentClientImportDialog> createState() =>
      _TorrentClientImportDialogState();
}

class _TorrentClientImportDialogState extends State<TorrentClientImportDialog> {
  final _source = TextEditingController();
  List<String> _roots = [];
  bool _loading = true, _busy = false, _edited = false;
  String? _error;
  AppLocalizations get l => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    unawaited(_discover());
  }

  Future<void> _discover() async {
    try {
      final roots = await widget.discover();
      if (!mounted) return;
      setState(() {
        _roots = roots;
        if (!_edited && _source.text.isEmpty && roots.isNotEmpty) {
          _source.text = roots.first;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _browse() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final initial = _source.text.trim();
      final exists = initial.isNotEmpty && await Directory(initial).exists();
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: l.selectFolder,
        initialDirectory: exists ? initial : null,
        windowsOptions: const WindowsOptions(lockParentWindow: true),
      );
      if (mounted && selected != null && selected.isNotEmpty) {
        setState(() {
          _edited = true;
          _source.text = selected;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _loading) return;
    setState(() => _busy = true);
    try {
      final source = _source.text.trim();
      if (source.isEmpty || !await Directory(source).exists()) {
        if (mounted) setState(() => _error = l.torrentClientSourceRequired);
        return;
      }
      if (mounted) Navigator.pop(context, Directory(source).absolute.path);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CbDialog(
    key: const ValueKey('torrent-client-import-dialog'),
    title: l.torrentImportFrom(widget.client),
    subtitle: l.torrentClientImportHint,
    width: 680,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _roots.isEmpty) ...[
          Text(l.torrentClientNotFound, style: CbTypography.body),
          const SizedBox(height: CbSpacing.xl),
        ],
        if (_roots.length > 1) ...[
          CbSelect<String>(
            key: const ValueKey('torrent-client-profiles'),
            label: l.torrentSources,
            expand: true,
            value: _roots.contains(_source.text) ? _source.text : null,
            items: _roots
                .map((root) => CbSelectItem(value: root, label: root))
                .toList(),
            onChanged: _busy
                ? null
                : (root) => setState(() {
                    _edited = true;
                    _source.text = root;
                    _error = null;
                  }),
          ),
          const SizedBox(height: CbSpacing.xl),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CbTextField(
                key: const ValueKey('torrent-client-source'),
                controller: _source,
                label: l.selectFolder,
                enabled: !_busy,
                errorText: _error,
                onChanged: (_) => setState(() {
                  _edited = true;
                  _error = null;
                }),
              ),
            ),
            const SizedBox(width: CbSpacing.md),
            CbButton(
              key: const ValueKey('torrent-client-browse'),
              label: l.browse,
              icon: PhosphorIconsLight.folderOpen,
              onPressed: _busy ? null : _browse,
            ),
          ],
        ),
        const SizedBox(height: CbSpacing.xl),
        Text(
          l.torrentStorageMode(widget.storageMode),
          style: CbTypography.body,
        ),
      ],
    ),
    actions: [
      CbButton(
        label: l.cancel,
        onPressed: _busy ? null : () => Navigator.pop(context),
      ),
      CbButton(
        key: const ValueKey('torrent-client-import-confirm'),
        label: l.torrentImportMenu,
        variant: CbButtonVariant.primary,
        onPressed: _busy || _loading ? null : _submit,
      ),
    ],
  );
}

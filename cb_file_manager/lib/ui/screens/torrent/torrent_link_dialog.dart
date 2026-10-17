import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/torrent/torrent_entry.dart';
import '../../../services/torrent/torrent_import_confirmation.dart';
import '../../../services/torrent/magnet_link.dart';

class TorrentLinkDialog extends StatefulWidget {
  final Future<TorrentEntry> Function(String) onAdd;
  const TorrentLinkDialog({super.key, required this.onAdd});

  @override
  State<TorrentLinkDialog> createState() => _TorrentLinkDialogState();
}

class _TorrentLinkDialogState extends State<TorrentLinkDialog> {
  final _link = TextEditingController();
  bool _adding = false;
  String? _error;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prefillMagnet());
  }

  Future<void> _prefillMagnet() async {
    try {
      final text = (await Clipboard.getData(
        Clipboard.kTextPlain,
      ))?.text?.trim();
      if (text == null || text.isEmpty) return;
      MagnetLink.parse(text);
      if (!mounted || _edited || _adding || _link.text.isNotEmpty) return;
      _link.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } on FormatException {
      // Clipboard contents are optional; only supported magnet links prefill.
    } on PlatformException {
      // Opening the dialog still works if the clipboard is unavailable.
    } on MissingPluginException {
      // Platforms without a clipboard implementation keep an empty field.
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_adding) return;
    final value = _link.text.trim();
    if (value.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.torrentLinkHint);
      return;
    }
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final entry = await widget.onAdd(value);
      if (mounted) Navigator.pop(context, entry);
    } on TorrentImportCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_adding,
      child: CbDialog(
        title: l.torrentAddLink,
        subtitle: l.torrentLinkHint,
        showCloseButton: !_adding,
        width: 680,
        content: CbTextField(
          key: const ValueKey('torrent-link-input'),
          controller: _link,
          autofocus: true,
          enabled: !_adding,
          placeholder: 'https://… / magnet:?xt=urn:btih:…',
          maxLines: 3,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          errorText: _error,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => _edited = true,
        ),
        actions: [
          CbButton(
            label: l.cancel,
            onPressed: _adding ? null : () => Navigator.pop(context),
          ),
          CbButton(
            key: const ValueKey('torrent-link-confirm'),
            label: l.add,
            loading: _adding && (ModalRoute.of(context)?.isCurrent ?? true),
            variant: CbButtonVariant.primary,
            onPressed: _adding ? null : _submit,
          ),
        ],
      ),
    );
  }
}

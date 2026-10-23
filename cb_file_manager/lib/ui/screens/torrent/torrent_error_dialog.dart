import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';

/// Keeps the diagnostic available until the user dismisses it, even if a
/// background refresh has already cleared the original error.
class TorrentErrorDialog extends StatefulWidget {
  final String report;

  const TorrentErrorDialog({super.key, required this.report});

  @override
  State<TorrentErrorDialog> createState() => _TorrentErrorDialogState();
}

class _TorrentErrorDialogState extends State<TorrentErrorDialog> {
  bool _copied = false;
  String? _copyError;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.report));
      if (mounted) {
        setState(() {
          _copied = true;
          _copyError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _copyError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return CbDialog(
      key: const ValueKey('torrent-error-dialog'),
      title: l.errorTitle,
      subtitle: l.torrents,
      width: 760,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: CbSpacing.md,
        children: [
          SelectableText(
            widget.report,
            key: const ValueKey('torrent-error-report'),
            style: CbTypography.body.copyWith(height: 1.5),
          ),
          if (_copyError != null) SelectableText(_copyError!),
        ],
      ),
      actions: [
        CbButton(
          key: const ValueKey('torrent-error-copy'),
          label: _copied ? l.copied : l.copy,
          icon: Icons.copy_outlined,
          onPressed: _copy,
        ),
        CbButton(
          key: const ValueKey('torrent-error-close'),
          label: l.close,
          variant: CbButtonVariant.primary,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/torrent/torrent_entry.dart';

Future<bool> confirmTorrentMove(
  BuildContext context,
  TorrentMovePlan plan,
) async {
  final l = AppLocalizations.of(context)!;
  return await CbDialog.show<bool>(
        context: context,
        barrierDismissible: false,
        dialog: CbDialog(
          key: const ValueKey('torrent-move-confirmation'),
          title: l.torrentMoveConfirmTitle,
          subtitle: l.torrentMoveConfirmHint(plan.sources.length),
          width: 760,
          destructive: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.torrentStorage),
              const SizedBox(height: CbSpacing.sm),
              SelectableText(plan.destination),
              if (plan.sources.isNotEmpty) ...[
                const SizedBox(height: CbSpacing.xl),
                SizedBox(
                  height: 260,
                  child: ListView.builder(
                    key: const ValueKey('torrent-move-source-preview'),
                    itemCount: plan.sources.length,
                    itemBuilder: (context, index) {
                      final source = plan.sources[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: CbSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(source.path),
                            const SizedBox(height: CbSpacing.sm),
                            SelectableText('→ ${source.destination}'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          actions: [
            CbButton(
              key: const ValueKey('torrent-move-cancel'),
              label: l.cancel,
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
            ),
            CbButton(
              key: const ValueKey('torrent-move-confirm'),
              label: l.torrentMoveConfirm,
              variant: CbButtonVariant.primary,
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
            ),
          ],
        ),
      ) ==
      true;
}

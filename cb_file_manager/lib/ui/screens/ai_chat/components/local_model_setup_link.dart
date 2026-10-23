import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../services/local_ai/local_model_downloads.dart';
import '../../settings/settings_navigation.dart';
import 'local_model_guide_dialog.dart';

/// Empty-chat shortcut to a free local model: the setup guide, or the
/// progress of a model already downloading in the background.
class LocalModelSetupLink extends StatelessWidget {
  final bool compact;

  const LocalModelSetupLink({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<LocalModelDownloads>()) return _guideLink(context);
    final downloads = getIt<LocalModelDownloads>();
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final active = downloads.downloads.where((d) => !d.failed);
        if (active.isEmpty) return _guideLink(context);
        return _progress(context, active.first);
      },
    );
  }

  Widget _guideLink(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey('local-model-guide-link'),
      onPressed: () => LocalModelGuideDialog.show(context),
      icon: Icon(PhosphorIconsLight.cpu, size: compact ? 14 : 16),
      label: Text(
        AppLocalizations.of(context)!.localModelGuideLink,
        style: compact ? const TextStyle(fontSize: 12) : null,
      ),
    );
  }

  Widget _progress(BuildContext context, LocalModelDownload download) {
    final theme = Theme.of(context);
    final progress = download.progress;
    final label = AppLocalizations.of(
      context,
    )!.localModelDownloading(download.entry.displayName);
    return TextButton.icon(
      key: const ValueKey('local-model-download-progress'),
      onPressed: () => openSettings(context, anchor: SettingsAnchor.localAi),
      icon: SizedBox(
        width: compact ? 12 : 14,
        height: compact ? 12 : 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: progress,
          color: theme.colorScheme.primary,
        ),
      ),
      label: Text(
        progress == null ? label : '$label · ${(progress * 100).toInt()}%',
        style: compact ? const TextStyle(fontSize: 12) : null,
      ),
    );
  }
}

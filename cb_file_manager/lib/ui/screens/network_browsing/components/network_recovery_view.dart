import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../design_system/primitives/cb_button.dart';

/// Recovery stays usable even in a short window or with a long server error.
class NetworkRecoveryView extends StatelessWidget {
  final String path;
  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onConnections;
  final VoidCallback onHome;

  const NetworkRecoveryView({
    super.key,
    required this.path,
    required this.errorMessage,
    required this.onRetry,
    required this.onConnections,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                PhosphorIconsLight.wifiSlash,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.cannotOpenNetworkPath,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(path, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                l10n.networkErrorPersistsHint,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CbButton(
                    label: l10n.networkConnections,
                    icon: PhosphorIconsLight.plugs,
                    variant: CbButtonVariant.primary,
                    onPressed: onConnections,
                  ),
                  CbButton(
                    label: l10n.tryAgain,
                    icon: PhosphorIconsLight.arrowClockwise,
                    onPressed: onRetry,
                  ),
                  CbButton(
                    label: l10n.home,
                    icon: PhosphorIconsLight.house,
                    variant: CbButtonVariant.ghost,
                    onPressed: onHome,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

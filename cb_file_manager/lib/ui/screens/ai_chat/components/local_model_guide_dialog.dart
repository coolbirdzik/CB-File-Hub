import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../e2e/cb_e2e_config.dart';
import '../../../../services/local_ai/local_ai_advisor_service.dart';
import '../../settings/settings_navigation.dart';

/// Explains how to install an on-device model so CB Agent works without an
/// API key or usage limits.
class LocalModelGuideDialog extends StatelessWidget {
  const LocalModelGuideDialog({super.key});

  /// Set once the guide has opened, so the chat tab and the side panel
  /// starting together cannot both show it.
  static bool _offeredThisSession = false;

  @visibleForTesting
  static void resetSessionForTest() => _offeredThisSession = false;

  /// Shows the guide on the user's first visit to CB Agent, unless they
  /// already have a local model installed.
  static Future<void> maybeShowOnFirstUse(BuildContext context) async {
    // E2E suites open CB Agent on fresh profiles; a modal would block them.
    if (_offeredThisSession || kCbE2E) return;
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<LocalAiAdvisorService>()) return;
    _offeredThisSession = true;

    final localAi = getIt<LocalAiAdvisorService>();
    if (localAi.chatGuideShown) return;
    await localAi.markChatGuideShown();
    // Someone who already runs a local model does not need the guide.
    if (localAi.getInstalledModels().isNotEmpty || !context.mounted) return;
    await show(context);
  }

  /// Shows the guide; "Open Local AI settings" jumps to that Settings section.
  static Future<void> show(BuildContext context) async {
    final openSettingsRequested = await showDialog<bool>(
      context: context,
      builder: (_) => const LocalModelGuideDialog(),
    );
    if (openSettingsRequested == true && context.mounted) {
      openSettings(
        context,
        anchor: SettingsAnchor.localAi,
        openLocalModelInstaller: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final steps = [
      l.localModelGuideStep1,
      l.localModelGuideStep2(l.installModel),
      l.localModelGuideStep3,
    ];

    return AlertDialog(
      icon: Icon(
        PhosphorIconsLight.cpu,
        size: 32,
        color: theme.colorScheme.primary,
      ),
      title: Text(l.localModelGuideTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.localModelGuideIntro,
                style: TextStyle(fontSize: 13, height: 1.45, color: muted),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < steps.length; i++)
                _GuideStep(number: i + 1, text: steps[i]),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhosphorIconsLight.info, size: 14, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.localModelGuideNote,
                      style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.localModelGuideLater),
        ),
        FilledButton.icon(
          key: const ValueKey('local-model-guide-open-settings'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(PhosphorIconsLight.gear, size: 16),
          label: Text(l.localModelGuideOpenSettings),
        ),
      ],
    );
  }
}

class _GuideStep extends StatelessWidget {
  final int number;
  final String text;

  const _GuideStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

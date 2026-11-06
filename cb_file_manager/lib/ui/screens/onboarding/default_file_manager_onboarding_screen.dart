import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/desktop_integration/default_file_manager_service.dart';
import '../settings/default_file_manager_settings.dart';

class DefaultFileManagerOnboardingScreen extends StatefulWidget {
  static const completedKey = 'default_file_manager_onboarding_completed_v1';
  final DefaultFileManagerService? service;

  const DefaultFileManagerOnboardingScreen({super.key, this.service});

  /// Separate completion from theme onboarding so existing desktop users can
  /// make this choice once too. OS registration still requires an explicit tap.
  static Future<void> showIfNeeded(
    BuildContext context, {
    DefaultFileManagerService? service,
  }) async {
    final setup = service ?? DefaultFileManagerService.instance;
    if (!setup.supported) return;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(completedKey) == true) return;
    try {
      final status = await setup.status();
      if (!status.available) return;
      if (status.enabled) {
        await preferences.setBool(completedKey, true);
        return;
      }
    } catch (_) {
      // The shared setup UI offers retry and postponement on a read failure.
    }
    if (!context.mounted) return;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => DefaultFileManagerOnboardingScreen(service: setup),
      ),
    );
    if (completed == true) await preferences.setBool(completedKey, true);
  }

  @override
  State<DefaultFileManagerOnboardingScreen> createState() =>
      _DefaultFileManagerOnboardingScreenState();
}

class _DefaultFileManagerOnboardingScreenState
    extends State<DefaultFileManagerOnboardingScreen> {
  final _busy = ValueNotifier<bool>(false);
  bool _enabled = false;

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.tr;
    return ValueListenableBuilder<bool>(
      valueListenable: _busy,
      builder: (context, busy, _) => PopScope(
        canPop: !busy,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 1),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 760,
                    maxHeight: 640,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Icon(
                                  PhosphorIconsLight.folderOpen,
                                  size: 48,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  l10n.defaultFileManagerOnboardingTitle,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  l10n.defaultFileManagerOnboardingDescription,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 24),
                                DefaultFileManagerSettings(
                                  service: widget.service,
                                  busy: _busy,
                                  onStatusChanged: (status) {
                                    if (_enabled != status.enabled) {
                                      setState(() => _enabled = status.enabled);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(36, 8, 36, 24),
                          child: CbButton(
                            label: _enabled
                                ? l10n.themeOnboardingContinue
                                : l10n.defaultFileManagerOnboardingLater,
                            variant: _enabled
                                ? CbButtonVariant.primary
                                : CbButtonVariant.secondary,
                            size: CbButtonSize.lg,
                            expand: true,
                            onPressed: busy
                                ? null
                                : () => Navigator.of(context).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

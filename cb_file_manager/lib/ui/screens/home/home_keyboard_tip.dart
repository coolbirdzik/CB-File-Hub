import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_tokens.dart';
import '../../../design_system/primitives/cb_button.dart';
import '../../../design_system/primitives/cb_decorations.dart';
import '../../../design_system/primitives/cb_kbd.dart';
import '../../../design_system/tokens/cb_geometry_tokens.dart';
import '../../../design_system/tokens/cb_type_tokens.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../components/keyboard_shortcuts/key_caps.dart';
import '../../components/keyboard_shortcuts/keyboard_shortcuts_view.dart';
import '../../tab_manager/core/tab_keyboard_shortcuts.dart';

/// The Home card that teaches the keyboard: the command palette first, then
/// two everyday shortcuts, with buttons to open the palette and the full
/// shortcuts reference.
///
/// Desktop only — the palette and these shortcuts need a keyboard. The close
/// button turns it off ([UserPreferences.showHomeKeyboardTip]); the switch on
/// the keyboard shortcuts page turns it back on.
class HomeKeyboardTip extends StatefulWidget {
  const HomeKeyboardTip({super.key});

  /// Platforms that show the card. Uses [defaultTargetPlatform] so widget
  /// tests (Android unless overridden) keep their existing Home layout.
  static bool get isSupported => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    _ => false,
  };

  @override
  State<HomeKeyboardTip> createState() => _HomeKeyboardTipState();
}

class _HomeKeyboardTipState extends State<HomeKeyboardTip> {
  final UserPreferences _prefs = UserPreferences.instance;

  /// Nothing renders until the stored choice is known, so a dismissed card
  /// never flashes on launch (Home loads its recent-folders visibility the
  /// same way).
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (HomeKeyboardTip.isSupported) {
      unawaited(
        _prefs
            .getShowHomeKeyboardTip()
            .catchError((Object _) => false)
            .whenComplete(() {
              if (mounted) setState(() => _loaded = true);
            }),
      );
    }
  }

  void _openPalette() {
    // Goes through the tab shell's own Ctrl+K action, so the card and the
    // shortcut can never open different palettes.
    Actions.maybeInvoke(context, const OpenCommandPaletteIntent());
  }

  @override
  Widget build(BuildContext context) {
    if (!HomeKeyboardTip.isSupported || !_loaded) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _prefs.showHomeKeyboardTip,
      builder: (context, visible, _) {
        if (!visible) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: _buildCard(context),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final c = context.cbColors;
    final l10n = context.tr;
    final tips = <(List<String>, String)>[
      (KeyCaps.chord('K'), l10n.homeTipPalette),
      (KeyCaps.chord('T'), l10n.newTab),
      (const ['A–Z'], l10n.shortcutTypeToFind),
    ];

    return Container(
      key: const ValueKey('home-keyboard-tip'),
      padding: const EdgeInsets.fromLTRB(
        CbSpacing.lg + 2,
        CbSpacing.md + 2,
        CbSpacing.sm,
        CbSpacing.lg,
      ),
      decoration: CbDecorations.card(context, radius: CbRadii.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsLight.keyboard,
                size: CbSizes.iconLg,
                color: c.icon,
              ),
              const SizedBox(width: CbSpacing.sm + 2),
              Expanded(
                child: Text(
                  l10n.homeTipTitle,
                  style: CbTypography.headingSm.copyWith(color: c.textPrimary),
                ),
              ),
              CbButton.icon(
                key: const ValueKey('home-keyboard-tip-dismiss'),
                icon: PhosphorIconsLight.x,
                tooltip: l10n.dismiss,
                size: CbButtonSize.sm,
                onPressed: () =>
                    unawaited(_prefs.setShowHomeKeyboardTip(false)),
              ),
            ],
          ),
          const SizedBox(height: CbSpacing.md),
          Padding(
            padding: const EdgeInsets.only(right: CbSpacing.sm),
            child: Wrap(
              spacing: CbSpacing.xl,
              runSpacing: CbSpacing.sm + 2,
              children: [
                for (final (keys, label) in tips)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CbKbd(keys, height: 22),
                      const SizedBox(width: CbSpacing.sm + 2),
                      Text(
                        label,
                        style: CbTypography.body.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: CbSpacing.lg),
          Wrap(
            spacing: CbSpacing.sm,
            runSpacing: CbSpacing.sm,
            children: [
              CbButton(
                key: const ValueKey('home-keyboard-tip-open-palette'),
                label: l10n.homeTipOpenPalette,
                icon: PhosphorIconsLight.lightning,
                variant: CbButtonVariant.secondary,
                onPressed: _openPalette,
              ),
              CbButton(
                key: const ValueKey('home-keyboard-tip-all-shortcuts'),
                label: l10n.shortcutsTitle,
                icon: PhosphorIconsLight.keyboard,
                variant: CbButtonVariant.ghost,
                onPressed: () =>
                    unawaited(showKeyboardShortcutsDialog(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

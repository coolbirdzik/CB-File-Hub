import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/translation_helper.dart';
import '../../../design_system/cb_tokens.dart';
import '../../../design_system/primitives/cb_button.dart';
import '../../../design_system/primitives/cb_decorations.dart';
import '../../../design_system/primitives/cb_kbd.dart';
import '../../../design_system/tokens/cb_geometry_tokens.dart';
import '../../../design_system/tokens/cb_motion_tokens.dart';
import '../../../design_system/tokens/cb_type_tokens.dart';
import '../../../helpers/core/text_utils.dart';
import '../../../helpers/core/user_preferences.dart';
import 'keyboard_shortcut_catalog.dart';

/// The keyboard shortcuts reference: a search field over every shortcut,
/// grouped by where it works, each with its key caps.
///
/// Hosted as a Settings page ([KeyboardShortcutsScreen]) and as a floating
/// window from Home and the command palette ([showKeyboardShortcutsDialog]).
class KeyboardShortcutsView extends StatefulWidget {
  /// Shows the "keyboard tips on Home" switch — the way back after the Home
  /// tip card has been dismissed.
  final bool showHomeTipToggle;

  final bool autofocusSearch;

  const KeyboardShortcutsView({
    super.key,
    this.showHomeTipToggle = true,
    this.autofocusSearch = false,
  });

  @override
  State<KeyboardShortcutsView> createState() => _KeyboardShortcutsViewState();
}

class _KeyboardShortcutsViewState extends State<KeyboardShortcutsView> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    if (widget.showHomeTipToggle) {
      unawaited(UserPreferences.instance.getShowHomeKeyboardTip());
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<KeyboardShortcutGroup> _filtered(List<KeyboardShortcutGroup> groups) {
    final q = _query.text;
    if (q.trim().isEmpty) return groups;
    return [
      for (final group in groups)
        if (TextUtils.matchesSearch(group.title, q))
          group
        else if (group.entries.any((e) => _matches(e, q)))
          KeyboardShortcutGroup(
            title: group.title,
            icon: group.icon,
            entries: [
              for (final e in group.entries)
                if (_matches(e, q)) e,
            ],
          ),
    ];
  }

  bool _matches(KeyboardShortcutEntry entry, String q) =>
      TextUtils.matchesSearch(
        '${entry.label} ${entry.combos.expand((c) => c).join(' ')}',
        q,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l10n = context.tr;
    final groups = _filtered(keyboardShortcutGroups(l10n));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CbSpacing.lg,
            CbSpacing.md,
            CbSpacing.lg,
            CbSpacing.sm,
          ),
          child: TextField(
            key: const ValueKey('keyboard-shortcuts-search'),
            controller: _query,
            autofocus: widget.autofocusSearch,
            style: CbTypography.body.copyWith(color: c.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.shortcutsSearchHint,
              prefixIcon: Icon(
                PhosphorIconsLight.magnifyingGlass,
                size: CbSizes.iconMd,
                color: c.iconSubtle,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
            ),
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text(
                    l10n.noResultsFound,
                    style: CbTypography.body.copyWith(color: c.textTertiary),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    CbSpacing.sm,
                    0,
                    CbSpacing.sm,
                    CbSpacing.lg,
                  ),
                  children: [
                    if (widget.showHomeTipToggle && _query.text.isEmpty)
                      const _HomeTipToggle(),
                    for (final group in groups) _GroupSection(group: group),
                  ],
                ),
        ),
      ],
    );
  }
}

class _HomeTipToggle extends StatelessWidget {
  const _HomeTipToggle();

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final prefs = UserPreferences.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: prefs.showHomeKeyboardTip,
      builder: (context, enabled, _) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.sm,
          vertical: CbSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIconsLight.lightbulb,
              size: CbSizes.iconMd,
              color: c.icon,
            ),
            const SizedBox(width: CbSpacing.md),
            Expanded(
              child: Text(
                context.tr.homeTipShowOnHome,
                style: CbTypography.body.copyWith(color: c.textPrimary),
              ),
            ),
            Switch(
              key: const ValueKey('keyboard-shortcuts-home-tip-toggle'),
              value: enabled,
              onChanged: (value) =>
                  unawaited(prefs.setShowHomeKeyboardTip(value)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  final KeyboardShortcutGroup group;

  const _GroupSection({required this.group});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.only(top: CbSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CbSpacing.sm,
              0,
              CbSpacing.sm,
              CbSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(group.icon, size: CbSizes.iconSm, color: c.iconSubtle),
                const SizedBox(width: CbSpacing.sm - 2),
                Text(
                  group.title,
                  style: CbTypography.labelXs.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: CbDecorations.card(context),
            child: Column(
              children: [
                for (var i = 0; i < group.entries.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: CbSpacing.md,
                      endIndent: CbSpacing.md,
                      color: c.strokeSubtle,
                    ),
                  _EntryRow(entry: group.entries[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final KeyboardShortcutEntry entry;

  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.md,
          vertical: CbSpacing.xs + 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entry.label,
                style: CbTypography.body.copyWith(color: c.textPrimary),
              ),
            ),
            const SizedBox(width: CbSpacing.md),
            Wrap(
              spacing: CbSpacing.sm,
              runSpacing: CbSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.end,
              children: [
                for (var i = 0; i < entry.combos.length; i++) ...[
                  if (i > 0)
                    Text(
                      '/',
                      style: CbTypography.bodySm.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                  CbKbd(entry.combos[i]),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings sub-page hosting [KeyboardShortcutsView].
class KeyboardShortcutsScreen extends StatelessWidget {
  const KeyboardShortcutsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr.shortcutsTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: const KeyboardShortcutsView(),
        ),
      ),
    );
  }
}

/// Opens the shortcuts reference as a floating window over the app.
Future<void> showKeyboardShortcutsDialog(BuildContext context) {
  final c = context.cbColors;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.tr.shortcutsTitle,
    barrierColor: c.scrim,
    transitionDuration: CbDurations.fast,
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: CbCurves.standard),
      child: child,
    ),
    pageBuilder: (dialogContext, _, _) => const _KeyboardShortcutsWindow(),
  );
}

class _KeyboardShortcutsWindow extends StatelessWidget {
  const _KeyboardShortcutsWindow();

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final media = MediaQuery.sizeOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CbSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: (media.height * 0.8).clamp(320, 760),
          ),
          child: Material(
            key: const ValueKey('keyboard-shortcuts-window'),
            color: c.surfaceOverlay,
            shape: CbDecorations.floatingShape(c, radius: CbRadii.xl),
            elevation: 12,
            shadowColor: c.shadow,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CbSpacing.lg + 2,
                    CbSpacing.md,
                    CbSpacing.sm,
                    0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIconsLight.keyboard,
                        size: CbSizes.iconLg,
                        color: c.icon,
                      ),
                      const SizedBox(width: CbSpacing.sm + 2),
                      Expanded(
                        child: Text(
                          context.tr.shortcutsTitle,
                          style: CbTypography.headingMd.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      CbButton.icon(
                        icon: PhosphorIconsLight.x,
                        tooltip: context.tr.close,
                        size: CbButtonSize.sm,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                const Expanded(
                  child: KeyboardShortcutsView(autofocusSearch: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

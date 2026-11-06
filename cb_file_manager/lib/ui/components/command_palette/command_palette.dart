import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../config/translation_helper.dart';
import '../../../design_system/cb_tokens.dart';
import '../../../design_system/primitives/cb_decorations.dart';
import '../../../design_system/primitives/cb_kbd.dart';
import '../../../design_system/tokens/cb_color_tokens.dart';
import '../../../design_system/tokens/cb_geometry_tokens.dart';
import '../../../design_system/tokens/cb_motion_tokens.dart';
import '../../../design_system/tokens/cb_type_tokens.dart';
import '../../../helpers/core/desktop_shortcuts.dart';
import '../keyboard_shortcuts/key_caps.dart';
import 'command_palette_item.dart';

export 'command_palette_item.dart';

/// Opens the Raycast-style command palette over the current window.
///
/// [items] are available immediately. [deferredItems] (pinned and recent
/// folders, which come from disk) are merged in when they resolve, so the
/// palette opens instantly. [itemsForQuery] contributes query-dependent rows
/// such as "go to this path".
///
/// The chosen item's [CommandPaletteItem.onRun] runs after the palette has
/// closed, against whatever context the caller captured in it.
Future<void> showCommandPalette({
  required BuildContext context,
  required List<CommandPaletteItem> items,
  Future<List<CommandPaletteItem>>? deferredItems,
  List<CommandPaletteItem> Function(String query)? itemsForQuery,
}) async {
  // Ctrl+K while the palette is up is handled by the palette itself (it
  // closes); a second palette is never stacked on the first.
  if (CommandPalette._isOpen) return;
  final c = context.cbColors;
  {
    final chosen = await showGeneralDialog<CommandPaletteItem>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.tr.commandPaletteTitle,
      // A light dim: the palette is a quick, transient layer, not a modal
      // task, so the window behind should stay readable.
      barrierColor: c.scrim.withValues(alpha: c.scrim.a * 0.45),
      transitionDuration: CbDurations.fast,
      pageBuilder: (dialogContext, _, _) => CommandPalette(
        items: items,
        deferredItems: deferredItems,
        itemsForQuery: itemsForQuery,
      ),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: CbCurves.standard,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
    if (chosen == null) return;
    // Let the dialog route finish popping before the action pushes routes or
    // switches tabs of its own.
    SchedulerBinding.instance.addPostFrameCallback((_) => chosen.onRun());
  }
}

/// The palette window: a search field, grouped results and an action footer.
class CommandPalette extends StatefulWidget {
  static bool _isOpen = false;

  /// Whether a palette is currently showing (used to make Ctrl+K a toggle).
  static bool get isOpen => _isOpen;

  final List<CommandPaletteItem> items;
  final Future<List<CommandPaletteItem>>? deferredItems;
  final List<CommandPaletteItem> Function(String query)? itemsForQuery;

  const CommandPalette({
    super.key,
    required this.items,
    this.deferredItems,
    this.itemsForQuery,
  });

  static const double width = 680;
  static const double searchHeight = 54;
  static const double rowHeight = 40;
  static const double headerHeight = 30;
  static const double footerHeight = 40;
  static const double maxListHeight = 400;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

/// A visual line in the result list: a section header or an item.
class _Entry {
  final CommandPaletteSection? header;
  final CommandPaletteItem? item;

  /// Index among items only (for selection), or -1 for headers.
  final int itemIndex;

  const _Entry.header(this.header) : item = null, itemIndex = -1;
  const _Entry.item(this.item, this.itemIndex) : header = null;

  double get height =>
      item == null ? CommandPalette.headerHeight : CommandPalette.rowHeight;
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'command-palette-search');
  final ScrollController _scroll = ScrollController();

  late List<CommandPaletteItem> _source = List.of(widget.items);
  List<_Entry> _entries = const [];
  List<CommandPaletteItem> _results = const [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    CommandPalette._isOpen = true;
    _rebuild();
    _query.addListener(_onQueryChanged);
    final deferred = widget.deferredItems;
    if (deferred != null) {
      unawaited(
        deferred.then((more) {
          if (!mounted || more.isEmpty) return;
          setState(() {
            _source = [..._source, ...more];
            _rebuild(keepSelection: true);
          });
        }, onError: (_) {}),
      );
    }
  }

  @override
  void dispose() {
    CommandPalette._isOpen = false;
    _query.removeListener(_onQueryChanged);
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() => _rebuild());
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _rebuild({bool keepSelection = false}) {
    final String query = _query.text;
    final selectedId = keepSelection && _selected < _results.length
        ? _results[_selected].id
        : null;
    final extra = widget.itemsForQuery?.call(query) ?? const [];
    _results = rankCommandPaletteItems([...extra, ..._source], query);

    final entries = <_Entry>[];
    CommandPaletteSection? current;
    for (var i = 0; i < _results.length; i++) {
      final item = _results[i];
      if (item.section != current) {
        current = item.section;
        entries.add(_Entry.header(current));
      }
      entries.add(_Entry.item(item, i));
    }
    _entries = entries;
    final keptIndex = selectedId == null
        ? -1
        : _results.indexWhere((item) => item.id == selectedId);
    _selected = keptIndex >= 0 ? keptIndex : 0;
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selected = (_selected + delta) % _results.length;
      if (_selected < 0) _selected += _results.length;
    });
    _revealSelected();
  }

  void _revealSelected() {
    if (!_scroll.hasClients) return;
    double top = 0;
    for (final entry in _entries) {
      if (entry.itemIndex == _selected) break;
      top += entry.height;
    }
    // Keep the section header visible when selecting a section's first row.
    final double headerTop = _selected == 0 ? 0 : top;
    final double bottom = top + CommandPalette.rowHeight;
    final position = _scroll.position;
    if (headerTop < position.pixels) {
      _scroll.jumpTo(headerTop.clamp(0, position.maxScrollExtent));
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (bottom - position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  void _run(int index) {
    if (index < 0 || index >= _results.length) return;
    Navigator.of(context).pop(_results[index]);
  }

  String _sectionTitle(AppLocalizations l10n, CommandPaletteSection section) {
    return switch (section) {
      CommandPaletteSection.goTo => l10n.commandPaletteGoTo,
      CommandPaletteSection.tabs => l10n.openTabs,
      CommandPaletteSection.currentFolder => l10n.currentFolder,
      CommandPaletteSection.pinned => l10n.favoritesSection,
      CommandPaletteSection.recent => l10n.recent,
      CommandPaletteSection.places => l10n.commandPalettePlaces,
      CommandPaletteSection.commands => l10n.commandPaletteCommands,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cb;
    final c = tokens.colors;
    final l10n = context.tr;
    final media = MediaQuery.of(context);
    final double listHeight = _entries.isEmpty
        ? CommandPalette.rowHeight * 2
        : _entries
              .fold<double>(CbSpacing.xs * 2, (sum, e) => sum + e.height)
              .clamp(0, CommandPalette.maxListHeight);
    final double topInset = (media.size.height * 0.14).clamp(CbSpacing.xl, 160);

    final palette = Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearch(c, l10n),
          Divider(height: 1, color: c.strokeSubtle),
          SizedBox(
            height: listHeight,
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      l10n.noResultsFound,
                      style: CbTypography.body.copyWith(color: c.textTertiary),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: CbSpacing.xs),
                    itemCount: _entries.length,
                    itemExtentBuilder: (index, _) =>
                        index < _entries.length ? _entries[index].height : null,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      if (entry.item == null) {
                        return _SectionHeader(
                          title: _sectionTitle(l10n, entry.header!),
                        );
                      }
                      return _ResultRow(
                        key: ValueKey('command-palette-item-${entry.item!.id}'),
                        item: entry.item!,
                        selected: entry.itemIndex == _selected,
                        onHover: () {
                          if (_selected != entry.itemIndex) {
                            setState(() => _selected = entry.itemIndex);
                          }
                        },
                        onTap: () => _run(entry.itemIndex),
                      );
                    },
                  ),
          ),
          _buildFooter(c, l10n),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.tab): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
            _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): () => _run(_selected),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            _run(_selected),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        for (final activator in DesktopShortcuts.primary(
          LogicalKeyboardKey.keyK,
        ))
          activator: () => Navigator.of(context).maybePop(),
      },
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: l10n.commandPaletteTitle,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              CbSpacing.lg,
              topInset,
              CbSpacing.lg,
              CbSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: CommandPalette.width),
              child: DecoratedBox(
                key: const ValueKey('command-palette'),
                decoration: BoxDecoration(
                  borderRadius: CbRadii.xlAll,
                  boxShadow: tokens.shadowLevel4,
                ),
                child: ClipRRect(
                  borderRadius: CbRadii.xlAll,
                  // Frosted glass over the window, like the acrylic backdrop
                  // the rest of the shell sits on.
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surfaceOverlay.withValues(
                          alpha: tokens.isDark ? 0.84 : 0.88,
                        ),
                        borderRadius: CbRadii.xlAll,
                        border: Border.all(
                          color: CbDecorations.floatingEdge(c),
                        ),
                      ),
                      child: palette,
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

  Widget _buildSearch(CbColorTokens c, AppLocalizations l10n) {
    return SizedBox(
      height: CommandPalette.searchHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CbSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: CbSizes.iconLg, color: c.icon),
            const SizedBox(width: CbSpacing.md),
            Expanded(
              child: TextField(
                key: const ValueKey('command-palette-search'),
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                cursorColor: c.textPrimary,
                style: CbTypography.bodyLg.copyWith(
                  fontSize: 16,
                  color: c.textPrimary,
                ),
                decoration:
                    InputDecoration.collapsed(
                      hintText: l10n.commandPaletteHint,
                      hintStyle: CbTypography.bodyLg.copyWith(
                        fontSize: 16,
                        color: c.textTertiary,
                      ),
                    ).copyWith(
                      // Borderless, Raycast-style: the divider under the row is
                      // the only edge. Explicit, or the theme's field hairline
                      // fills in for the null borders of a collapsed decoration.
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
              ),
            ),
            const SizedBox(width: CbSpacing.md),
            CbKbd([KeyCaps.escape]),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(CbColorTokens c, AppLocalizations l10n) {
    final label = CbTypography.labelSm.copyWith(color: c.textSecondary);
    Widget hint(String text, List<String> keys) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: label),
        const SizedBox(width: CbSpacing.sm),
        CbKbd(keys, height: 18),
      ],
    );
    final selected = _selected < _results.length ? _results[_selected] : null;
    return Container(
      height: CommandPalette.footerHeight,
      padding: const EdgeInsets.symmetric(horizontal: CbSpacing.md),
      decoration: BoxDecoration(
        color: c.fillSubtle,
        border: Border(top: BorderSide(color: c.strokeSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: CbSizes.iconMd, color: c.iconSubtle),
          const SizedBox(width: CbSpacing.xs + 2),
          Expanded(
            child: Text(
              l10n.commandPaletteTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CbTypography.labelSm.copyWith(color: c.textTertiary),
            ),
          ),
          if (selected != null) ...[
            hint(l10n.open, [KeyCaps.enter]),
            _footerDivider(c),
          ],
          hint(l10n.commandPaletteNavigate, const ['↑', '↓']),
        ],
      ),
    );
  }

  Widget _footerDivider(CbColorTokens c) => Container(
    width: 1,
    height: 14,
    margin: const EdgeInsets.symmetric(horizontal: CbSpacing.md),
    color: c.stroke,
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CbSpacing.lg + 2,
        CbSpacing.sm + 2,
        CbSpacing.lg,
        CbSpacing.xs,
      ),
      child: Text(
        title,
        maxLines: 1,
        style: CbTypography.labelXs.copyWith(color: c.textTertiary),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final CommandPaletteItem item;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  const _ResultRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final Widget? trailing = item.shortcut.isNotEmpty
        ? CbKbd(item.shortcut)
        : item.accessory == null
        ? null
        : Text(
            item.accessory!,
            style: CbTypography.bodySm.copyWith(color: c.textTertiary),
          );

    return MouseRegion(
      onHover: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: selected,
          label: item.title,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: CbSpacing.sm - 2),
            padding: const EdgeInsets.symmetric(horizontal: CbSpacing.sm + 2),
            decoration: BoxDecoration(
              color: selected ? c.surfaceSelected : Colors.transparent,
              borderRadius: CbRadii.mdAll,
            ),
            child: Row(
              children: [
                // Raycast's icon tile: a small rounded square behind the glyph.
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.fill,
                    borderRadius: CbRadii.smAll,
                  ),
                  child: Icon(
                    item.icon,
                    size: CbSizes.iconSm,
                    color: selected ? c.textPrimary : c.icon,
                  ),
                ),
                const SizedBox(width: CbSpacing.md),
                // Title and subtitle share the middle; the accessory stays
                // pinned to the right edge whatever their lengths.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        flex: 3,
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.body.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (item.subtitle != null &&
                          item.subtitle!.isNotEmpty) ...[
                        const SizedBox(width: CbSpacing.sm),
                        Flexible(
                          flex: 2,
                          child: Text(
                            item.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CbTypography.body.copyWith(
                              color: c.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: CbSpacing.md),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

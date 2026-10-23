import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_tokens.dart';
import '../../../design_system/primitives/cb_button.dart';
import '../../../design_system/primitives/cb_text_field.dart';
import '../../../design_system/tokens/cb_geometry_tokens.dart';
import '../../../design_system/tokens/cb_type_tokens.dart';
import '../../../helpers/core/text_utils.dart';
import '../../../services/windows_shell_properties.dart';
import '../../screens/folder_list/components/details_columns.dart';
import '../../screens/folder_list/folder_list_state.dart';

/// The Details column chooser: every column the app and Windows offer on one
/// side, searchable, and the shown ones in display order on the other.
///
/// Edits a copy; [onApply] receives it (and [onApplyAdditionalColumns] the
/// shown [additionalColumns]) when the user applies.
class ColumnChooserDialog extends StatefulWidget {
  final ColumnVisibility initial;
  final ValueChanged<ColumnVisibility> onApply;

  /// Collection columns (id to label) shown next to the Details columns.
  final Map<String, String> additionalColumns;
  final Set<String> visibleAdditionalColumns;
  final ValueChanged<Set<String>>? onApplyAdditionalColumns;

  const ColumnChooserDialog({
    super.key,
    required this.initial,
    required this.onApply,
    this.additionalColumns = const {},
    this.visibleAdditionalColumns = const {},
    this.onApplyAdditionalColumns,
  });

  @override
  State<ColumnChooserDialog> createState() => _ColumnChooserDialogState();
}

class _ColumnChooserDialogState extends State<ColumnChooserDialog> {
  static const double _wideLayoutWidth = 720;

  late var _columns = widget.initial;
  late final _additional = Set<String>.of(widget.visibleAdditionalColumns);
  final _search = TextEditingController();
  String _query = '';

  /// Null while Windows lists its properties.
  List<SystemPropertyColumn>? _system = WindowsShellProperties.isSupported
      ? null
      : const [];

  @override
  void initState() {
    super.initState();
    if (_system == null) {
      WindowsShellProperties.instance.systemColumns().then((columns) {
        if (mounted) setState(() => _system = columns);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Iterable<String> texts) =>
      _query.isEmpty ||
      texts.any((text) => TextUtils.searchKey(text).contains(_query));

  void _apply() {
    widget.onApply(_columns);
    widget.onApplyAdditionalColumns?.call(_additional);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.cbColors;
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 600;
    final height = math.min(
      720.0,
      media.size.height - media.viewInsets.vertical - CbSpacing.xxxl,
    );
    final shownCount =
        _columns.visibleColumns.length +
        _columns.visibleSystemColumns.length +
        _additional.length;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? CbSpacing.md : CbSpacing.xxl,
        vertical: CbSpacing.xl,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SizedBox(
          height: math.max(height, 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, l10n, narrow),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      constraints.maxWidth >= _wideLayoutWidth
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _buildAvailable(context, l10n)),
                            VerticalDivider(width: 1, color: c.strokeSubtle),
                            SizedBox(
                              width: 320,
                              child: _buildShown(context, l10n, shownCount),
                            ),
                          ],
                        )
                      : DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              TabBar(
                                tabs: [
                                  Tab(text: l10n.columnChooserAvailable),
                                  Tab(
                                    text: l10n.columnChooserShown(shownCount),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildAvailable(context, l10n),
                                    _buildShown(context, l10n, null),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              _buildFooter(context, l10n, narrow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n,
    bool narrow,
  ) {
    final c = context.cbColors;
    final padding = narrow ? CbSpacing.lg : CbSpacing.xl;
    return Container(
      padding: EdgeInsets.fromLTRB(padding, CbSpacing.lg, CbSpacing.md, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: CbSpacing.xs),
            child: Icon(
              PhosphorIconsLight.columns,
              size: CbSizes.iconLg,
              color: c.icon,
            ),
          ),
          const SizedBox(width: CbSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.columnVisibilityTitle,
                  style: CbTypography.headingLg.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: CbSpacing.xs),
                Text(
                  l10n.columnChooserSubtitle,
                  style: CbTypography.body.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: CbSpacing.md),
              ],
            ),
          ),
          CbButton.icon(
            icon: Icons.close,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            size: CbButtonSize.sm,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    AppLocalizations l10n,
    bool narrow,
  ) {
    final c = context.cbColors;
    final padding = narrow ? CbSpacing.lg : CbSpacing.xl;
    return Container(
      padding: EdgeInsets.fromLTRB(
        padding,
        CbSpacing.md,
        padding,
        CbSpacing.md,
      ),
      decoration: BoxDecoration(
        color: c.fillSubtle,
        border: Border(top: BorderSide(color: c.strokeSubtle)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: CbSpacing.md,
        runSpacing: CbSpacing.sm,
        children: [
          CbButton(
            key: const ValueKey('column-dialog-reset'),
            label: l10n.columnResetLayout,
            icon: PhosphorIconsLight.arrowCounterClockwise,
            variant: CbButtonVariant.ghost,
            onPressed: () => setState(() => _columns = _columns.resetLayout()),
          ),
          Wrap(
            spacing: CbSpacing.md,
            children: [
              CbButton(
                label: l10n.cancel,
                onPressed: () => Navigator.pop(context),
              ),
              CbButton(
                key: const ValueKey('column-dialog-apply'),
                label: l10n.apply,
                icon: PhosphorIconsLight.check,
                variant: CbButtonVariant.primary,
                onPressed: _apply,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Every column, grouped and filtered by the search; the collection's own
  /// columns first.
  Widget _buildAvailable(BuildContext context, AppLocalizations l10n) {
    final rows = <WidgetBuilder>[];

    final additional = [
      for (final entry in widget.additionalColumns.entries)
        if (_matches([entry.value])) entry,
    ];
    if (additional.isNotEmpty) {
      rows.add(
        (_) =>
            _GroupHeader(l10n.columnChooserCollectionGroup, additional.length),
      );
      for (final entry in additional) {
        rows.add(
          (context) => _AvailableRow(
            key: ValueKey('column-dialog-extra-${entry.key}'),
            icon: PhosphorIconsLight.listBullets,
            title: entry.value,
            value: _additional.contains(entry.key),
            onChanged: (value) => setState(() {
              if (value) {
                _additional.add(entry.key);
              } else {
                _additional.remove(entry.key);
              }
            }),
          ),
        );
      }
    }

    final basic = [
      for (final column in DetailsColumn.values)
        if (column.isAvailable &&
            _matches([column.label(l10n), column.description(l10n)]))
          column,
    ];
    if (basic.isNotEmpty) {
      rows.add((_) => _GroupHeader(l10n.columnChooserBasicGroup, basic.length));
      for (final column in basic) {
        rows.add(
          (context) => _AvailableRow(
            key: ValueKey('column-dialog-${column.name}'),
            icon: column.icon,
            title: column.label(l10n),
            subtitle: column == DetailsColumn.name
                ? l10n.columnChooserAlwaysShown
                : column.description(l10n),
            value: _columns.isVisible(column),
            onChanged: column == DetailsColumn.name
                ? null
                : (value) => setState(
                    () => _columns = _columns.withColumn(column, value),
                  ),
          ),
        );
      }
    }

    final system = _system;
    if (WindowsShellProperties.isSupported) {
      final matching = [
        for (final column in system ?? const <SystemPropertyColumn>[])
          if (_matches([column.label, column.name])) column,
      ];
      if (system == null || matching.isNotEmpty) {
        rows.add(
          (_) => _GroupHeader(
            l10n.columnChooserSystemGroup,
            system == null ? null : matching.length,
            note: l10n.columnChooserSystemNote,
          ),
        );
      }
      if (system == null) {
        rows.add((_) => _LoadingRow(l10n.columnChooserLoadingSystem));
      }
      for (final column in matching) {
        rows.add(
          (context) => _AvailableRow(
            key: ValueKey('column-dialog-system-${column.name}'),
            icon: PhosphorIconsLight.squaresFour,
            title: column.label,
            subtitle: column.name,
            value: _columns.systemColumns.contains(column.name),
            onChanged: (value) => setState(
              () => _columns = _columns.withSystemColumn(column.name, value),
            ),
          ),
        );
      }
    }

    final c = context.cbColors;
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
          child: CbTextField(
            key: const ValueKey('column-dialog-search'),
            controller: _search,
            placeholder: l10n.columnChooserSearchHint,
            prefixIcon: PhosphorIconsLight.magnifyingGlass,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) =>
                setState(() => _query = TextUtils.searchKey(value.trim())),
            suffix: _query.isEmpty
                ? null
                : CbButton.icon(
                    icon: Icons.close,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                    size: CbButtonSize.xs,
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    l10n.columnChooserNoMatch,
                    style: CbTypography.body.copyWith(color: c.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: CbSpacing.md),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => rows[index](context),
                ),
        ),
      ],
    );
  }

  /// The shown columns in display order: Name, the collection columns after
  /// it, then the movable built-in and system columns.
  Widget _buildShown(
    BuildContext context,
    AppLocalizations l10n,
    int? shownCount,
  ) {
    final c = context.cbColors;
    final builtIn = _columns.visibleColumns.skip(1).toList();
    final system = _columns.visibleSystemColumns;
    final additional = [
      for (final entry in widget.additionalColumns.entries)
        if (_additional.contains(entry.key)) entry,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shownCount != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CbSpacing.lg,
              CbSpacing.lg,
              CbSpacing.lg,
              CbSpacing.sm,
            ),
            child: Text(
              l10n.columnChooserShown(shownCount),
              style: CbTypography.headingSm.copyWith(color: c.textPrimary),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(bottom: CbSpacing.md),
            header: Column(
              children: [
                _ShownRow(
                  icon: DetailsColumn.name.icon,
                  title: DetailsColumn.name.label(l10n),
                  subtitle: l10n.columnChooserAlwaysShown,
                ),
                for (final entry in additional)
                  _ShownRow(
                    key: ValueKey('column-shown-extra-${entry.key}'),
                    icon: PhosphorIconsLight.listBullets,
                    title: entry.value,
                    hideTooltip: l10n.columnChooserHide,
                    onHide: () => setState(() => _additional.remove(entry.key)),
                  ),
              ],
            ),
            itemCount: builtIn.length + system.length,
            // Built-in and system columns each keep to their own block.
            onReorderItem: (from, to) => setState(() {
              if (from < builtIn.length) {
                final target = builtIn[math.min(to, builtIn.length - 1)];
                _columns = _columns.moveColumn(builtIn[from], target);
              } else {
                final index = math.max(to - builtIn.length, 0);
                final target = system[math.min(index, system.length - 1)];
                _columns = _columns.moveSystemColumn(
                  system[from - builtIn.length],
                  target,
                );
              }
            }),
            itemBuilder: (context, index) {
              if (index < builtIn.length) {
                final column = builtIn[index];
                return _ShownRow(
                  key: ValueKey('column-shown-${column.name}'),
                  index: index,
                  icon: column.icon,
                  title: column.label(l10n),
                  hideTooltip: l10n.columnChooserHide,
                  onHide: () => setState(
                    () => _columns = _columns.withColumn(column, false),
                  ),
                );
              }
              final column = system[index - builtIn.length];
              return _ShownRow(
                key: ValueKey('column-shown-system-$column'),
                index: index,
                icon: PhosphorIconsLight.squaresFour,
                title: systemColumnLabel(column),
                group: index == builtIn.length
                    ? l10n.columnChooserSystemGroup
                    : null,
                hideTooltip: l10n.columnChooserHide,
                onHide: () => setState(
                  () => _columns = _columns.withSystemColumn(column, false),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final int? count;
  final String? note;

  const _GroupHeader(this.title, this.count, {this.note});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CbSpacing.lg,
        CbSpacing.lg,
        CbSpacing.lg,
        CbSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == null
                ? title.toUpperCase()
                : '${title.toUpperCase()} · $count',
            style: CbTypography.overline.copyWith(color: c.textSecondary),
          ),
          if (note != null) ...[
            const SizedBox(height: CbSpacing.xxs),
            Text(
              note!,
              style: CbTypography.caption.copyWith(color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  final String label;

  const _LoadingRow(this.label);

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CbSpacing.lg,
        vertical: CbSpacing.md,
      ),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: CbSizes.iconMd,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: CbSpacing.md),
          Text(
            label,
            style: CbTypography.body.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A column to tick in the available list.
class _AvailableRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;

  /// Null keeps the row ticked and disabled.
  final ValueChanged<bool>? onChanged;

  const _AvailableRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final onChanged = this.onChanged;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.sm,
          vertical: CbSpacing.xxs,
        ),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged == null
                  ? null
                  : (value) => onChanged(value ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Icon(icon, size: CbSizes.iconMd, color: c.iconSubtle),
            const SizedBox(width: CbSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CbTypography.label.copyWith(color: c.textPrimary),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.caption.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shown column; draggable when it has an [index] in the reorderable list.
class _ShownRow extends StatelessWidget {
  final int? index;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Labels the first row of a block.
  final String? group;
  final String? hideTooltip;
  final VoidCallback? onHide;

  const _ShownRow({
    super.key,
    this.index,
    required this.icon,
    required this.title,
    this.subtitle,
    this.group,
    this.hideTooltip,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final index = this.index;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CbSpacing.sm,
        vertical: CbSpacing.xxs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: CbSizes.controlSm,
            child: index == null
                ? Icon(
                    PhosphorIconsLight.pushPin,
                    size: CbSizes.iconSm,
                    color: c.iconSubtle,
                  )
                : ReorderableDragStartListener(
                    index: index,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Icon(
                        PhosphorIconsLight.dotsSixVertical,
                        size: CbSizes.iconLg,
                        color: c.iconSubtle,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: CbSpacing.xs),
          Icon(icon, size: CbSizes.iconMd, color: c.iconSubtle),
          const SizedBox(width: CbSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CbTypography.label.copyWith(color: c.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CbTypography.caption.copyWith(color: c.textTertiary),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: CbSizes.controlSm,
            height: CbSizes.controlSm,
            child: onHide == null
                ? null
                : CbButton.icon(
                    icon: Icons.close,
                    tooltip: hideTooltip ?? '',
                    size: CbButtonSize.xs,
                    onPressed: onHide,
                  ),
          ),
        ],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: group == null
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: CbSpacing.lg),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CbSpacing.lg,
                    0,
                    CbSpacing.lg,
                    CbSpacing.xs,
                  ),
                  child: Text(
                    group!.toUpperCase(),
                    style: CbTypography.overline.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
                row,
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../models/ai/ai_provider_model.dart';

class ModelSelectorButton extends StatefulWidget {
  final List<AiProviderModelCatalog> catalogs;
  final String? selectedProviderId;
  final String? selectedModelName;
  final bool isLoading;
  final bool compact;
  final String tooltip;
  final String defaultLabel;
  final String loadingLabel;
  final String emptyLabel;
  final String searchHint;
  final String noMatchesLabel;
  final ValueChanged<ModelSelectorValue> onSelected;

  const ModelSelectorButton({
    Key? key,
    required this.catalogs,
    required this.selectedProviderId,
    required this.selectedModelName,
    required this.isLoading,
    required this.tooltip,
    required this.defaultLabel,
    required this.loadingLabel,
    required this.emptyLabel,
    required this.onSelected,
    this.searchHint = 'Search models...',
    this.noMatchesLabel = 'No models found',
    this.compact = false,
  }) : super(key: key);

  @override
  State<ModelSelectorButton> createState() => _ModelSelectorButtonState();
}

class _ModelSelectorButtonState extends State<ModelSelectorButton> {
  OverlayEntry? _overlay;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _hovered = false;

  @override
  void dispose() {
    // Remove directly: _removeOverlay() calls setState, which is illegal here.
    _overlay?.remove();
    _overlay = null;
    _searchController.dispose();
    super.dispose();
  }

  bool get _isEnabled => widget.catalogs.isNotEmpty && !widget.isLoading;

  void _toggleOverlay() {
    if (_overlay != null) {
      _removeOverlay();
      return;
    }
    if (!_isEnabled) return;
    _query = '';
    _searchController.clear();
    _overlay = _buildOverlay();
    Overlay.of(context).insert(_overlay!);
    setState(() {});
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() {});
  }

  void _handleSelected(ModelSelectorValue value) {
    _removeOverlay();
    widget.onSelected(value);
  }

  OverlayEntry _buildOverlay() {
    final theme = Theme.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final buttonSize = renderBox?.size ?? Size.zero;
    final buttonTopLeft = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    const double gap = 6;
    const double margin = 8;
    const double panelMaxWidth = 360;
    const double panelMaxHeight = 360;

    return OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.of(overlayContext);
        final screen = media.size;

        // Panel width: at least the button width, capped, and never wider than
        // the screen (minus margins).
        final available = screen.width - margin * 2;
        final desiredWidth = buttonSize.width < 240 ? 240.0 : buttonSize.width;
        final panelWidth =
            desiredWidth.clamp(0.0, panelMaxWidth).clamp(0.0, available);

        // Horizontal: align to button left, clamp so it never runs off-screen.
        var left = buttonTopLeft.dx;
        if (left + panelWidth > screen.width - margin) {
          left = screen.width - margin - panelWidth;
        }
        if (left < margin) left = margin;

        // Vertical: prefer below the button; flip above if there isn't room.
        final spaceBelow =
            screen.height - (buttonTopLeft.dy + buttonSize.height);
        final spaceAbove = buttonTopLeft.dy;
        final opensUp = spaceBelow < 220 && spaceAbove > spaceBelow;
        final maxHeight = (opensUp ? spaceAbove : spaceBelow) - gap - margin;
        final panelHeight = maxHeight.clamp(120.0, panelMaxHeight);

        final top = opensUp
            ? buttonTopLeft.dy - gap - panelHeight
            : buttonTopLeft.dy + buttonSize.height + gap;

        return Stack(
          children: [
            // Full-screen barrier to dismiss on outside tap.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: panelWidth,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: theme.colorScheme.surfaceContainerHigh,
                clipBehavior: Clip.antiAlias,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: panelHeight,
                    ),
                    child: StatefulBuilder(
                      builder: (context, setOverlayState) {
                        return _buildMenuContent(theme, setOverlayState);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuContent(ThemeData theme, StateSetter setOverlayState) {
    final filtered = _filteredCatalogs();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.searchHint,
              hintStyle: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              prefixIcon: Icon(
                PhosphorIconsLight.magnifyingGlass,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 34,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            onChanged: (value) {
              setOverlayState(() => _query = value.trim().toLowerCase());
            },
          ),
        ),
        Flexible(
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Text(
                    widget.noMatchesLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 6),
                  shrinkWrap: true,
                  children: _buildRows(theme, filtered),
                ),
        ),
      ],
    );
  }

  List<Widget> _buildRows(
    ThemeData theme,
    List<AiProviderModelCatalog> catalogs,
  ) {
    final rows = <Widget>[];
    for (final catalog in catalogs) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(
                catalog.apiType == AiApiType.anthropic
                    ? PhosphorIconsLight.chatCircleDots
                    : PhosphorIconsLight.robot,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  catalog.providerName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

      for (final model in catalog.models) {
        final isSelected = catalog.providerId == widget.selectedProviderId &&
            model == widget.selectedModelName;
        rows.add(
          InkWell(
            onTap: () => _handleSelected(
              ModelSelectorValue(
                providerId: catalog.providerId,
                modelName: model,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: isSelected
                        ? Icon(
                            PhosphorIconsBold.check,
                            size: 14,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      model,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (model == catalog.defaultModelName) ...[
                    const SizedBox(width: 8),
                    Text(
                      widget.defaultLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    }
    return rows;
  }

  /// Returns catalogs with models filtered by the search query. A catalog is
  /// kept when its name matches (all models shown) or any of its models match.
  List<AiProviderModelCatalog> _filteredCatalogs() {
    if (_query.isEmpty) return widget.catalogs;
    final result = <AiProviderModelCatalog>[];
    for (final catalog in widget.catalogs) {
      final providerMatches =
          catalog.providerName.toLowerCase().contains(_query);
      final matchingModels = providerMatches
          ? catalog.models
          : catalog.models
              .where((m) => m.toLowerCase().contains(_query))
              .toList();
      if (matchingModels.isEmpty) continue;
      result.add(
        AiProviderModelCatalog(
          providerId: catalog.providerId,
          providerName: catalog.providerName,
          apiType: catalog.apiType,
          authMode: catalog.authMode,
          defaultModelName: catalog.defaultModelName,
          models: matchingModels,
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCatalog = _findSelectedCatalog();
    final selectedLabel = _buildSelectedLabel(selectedCatalog);

    // Compact mode renders as a ghost pill (transparent until hovered) so it
    // sits inside the composer card without reading as a nested box.
    final Color background = widget.compact
        ? (_hovered || _overlay != null
            ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
            : Colors.transparent)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor:
            _isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _toggleOverlay,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: _isEnabled || widget.isLoading ? 1 : 0.6,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: BoxConstraints(
                minWidth: widget.compact ? 0 : 150,
                maxWidth: widget.compact ? 240 : 280,
                minHeight: widget.compact ? 28 : 30,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 8 : 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(widget.compact ? 999 : 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      PhosphorIconsLight.cpu,
                      size: widget.compact ? 14 : 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      selectedLabel,
                      style: TextStyle(
                        fontSize: widget.compact ? 11 : 12,
                        color: widget.compact
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    PhosphorIconsLight.caretDown,
                    size: widget.compact ? 12 : 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  AiProviderModelCatalog? _findSelectedCatalog() {
    for (final catalog in widget.catalogs) {
      if (catalog.providerId == widget.selectedProviderId) {
        return catalog;
      }
    }
    return widget.catalogs.isNotEmpty ? widget.catalogs.first : null;
  }

  String _buildSelectedLabel(AiProviderModelCatalog? selectedCatalog) {
    if (widget.isLoading) return widget.loadingLabel;
    if (selectedCatalog == null) return widget.emptyLabel;
    final model = widget.selectedModelName?.trim().isNotEmpty == true
        ? widget.selectedModelName!
        : null;
    final effectiveModel = model ??
        (selectedCatalog.defaultModelName.trim().isNotEmpty
            ? selectedCatalog.defaultModelName.trim()
            : (selectedCatalog.models.isNotEmpty
                ? selectedCatalog.models.first
                : widget.emptyLabel));
    // Compact mode has little room, so the provider prefix is dropped — the
    // tooltip and the dropdown still show which provider it belongs to.
    if (widget.compact) return effectiveModel;
    return '${selectedCatalog.providerName}: $effectiveModel';
  }
}

class ModelSelectorValue {
  final String providerId;
  final String modelName;

  const ModelSelectorValue({
    required this.providerId,
    required this.modelName,
  });
}

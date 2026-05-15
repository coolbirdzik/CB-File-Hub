import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../models/ai/ai_provider_model.dart';

class ModelSelectorButton extends StatelessWidget {
  final List<AiProviderModelCatalog> catalogs;
  final String? selectedProviderId;
  final String? selectedModelName;
  final bool isLoading;
  final bool compact;
  final String tooltip;
  final String defaultLabel;
  final String loadingLabel;
  final String emptyLabel;
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
    this.compact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCatalog = _findSelectedCatalog();
    final selectedLabel = _buildSelectedLabel(selectedCatalog);
    final isEnabled = catalogs.isNotEmpty && !isLoading;

    return PopupMenuButton<ModelSelectorValue>(
      enabled: isEnabled,
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (context) {
        final items = <PopupMenuEntry<ModelSelectorValue>>[];
        for (final catalog in catalogs) {
          items.add(
            PopupMenuItem<ModelSelectorValue>(
              enabled: false,
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
            final isSelected = catalog.providerId == selectedProviderId &&
                model == selectedModelName;
            items.add(
              CheckedPopupMenuItem<ModelSelectorValue>(
                value: ModelSelectorValue(
                  providerId: catalog.providerId,
                  modelName: model,
                ),
                checked: isSelected,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        model,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (model == catalog.defaultModelName) ...[
                      const SizedBox(width: 8),
                      Text(
                        defaultLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          if (catalog != catalogs.last) {
            items.add(const PopupMenuDivider(height: 8));
          }
        }
        return items;
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: isEnabled || isLoading ? 1 : 0.6,
        child: Container(
          constraints: BoxConstraints(
            minWidth: compact ? 0 : 150,
            maxWidth: compact ? 180 : 280,
            minHeight: 30,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  PhosphorIconsLight.cpu,
                  size: compact ? 14 : 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  selectedLabel,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                PhosphorIconsLight.caretDown,
                size: compact ? 12 : 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  AiProviderModelCatalog? _findSelectedCatalog() {
    for (final catalog in catalogs) {
      if (catalog.providerId == selectedProviderId) {
        return catalog;
      }
    }
    return catalogs.isNotEmpty ? catalogs.first : null;
  }

  String _buildSelectedLabel(AiProviderModelCatalog? selectedCatalog) {
    if (isLoading) return loadingLabel;
    if (selectedCatalog == null) return emptyLabel;
    final model =
        selectedModelName?.trim().isNotEmpty == true ? selectedModelName! : null;
    final effectiveModel = model ??
        (selectedCatalog.defaultModelName.trim().isNotEmpty
            ? selectedCatalog.defaultModelName.trim()
            : (selectedCatalog.models.isNotEmpty
                ? selectedCatalog.models.first
                : emptyLabel));
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

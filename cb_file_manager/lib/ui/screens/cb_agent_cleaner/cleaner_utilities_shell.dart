import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';

class CleanerUtilityDestination {
  final String id;
  final String title;
  final String description;
  final String group;
  final IconData icon;

  const CleanerUtilityDestination({
    required this.id,
    required this.title,
    required this.description,
    required this.group,
    required this.icon,
  });
}

class CleanerUtilitiesShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final String selectedId;
  final List<CleanerUtilityDestination> destinations;
  final ValueChanged<String> onSelected;
  final bool navigationEnabled;
  final Widget child;

  const CleanerUtilitiesShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedId,
    required this.destinations,
    required this.onSelected,
    required this.child,
    this.navigationEnabled = true,
  }) : assert(destinations.length > 0);

  static const double compactBreakpoint = 920;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < compactBreakpoint) {
          return Column(
            children: [
              _CompactUtilityNavigation(
                title: title,
                selectedId: selectedId,
                destinations: destinations,
                enabled: navigationEnabled,
                onSelected: onSelected,
              ),
              const SizedBox(height: CbSpacing.xs),
              Expanded(child: child),
            ],
          );
        }

        return Row(
          children: [
            SizedBox(
              width: 280,
              child: _UtilitySidebar(
                title: title,
                subtitle: subtitle,
                selectedId: selectedId,
                destinations: destinations,
                enabled: navigationEnabled,
                onSelected: onSelected,
              ),
            ),
            const SizedBox(width: CbSpacing.sm),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _UtilitySidebar extends StatelessWidget {
  final String title;
  final String subtitle;
  final String selectedId;
  final List<CleanerUtilityDestination> destinations;
  final ValueChanged<String> onSelected;
  final bool enabled;

  const _UtilitySidebar({
    required this.title,
    required this.subtitle,
    required this.selectedId,
    required this.destinations,
    required this.onSelected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(PhosphorIconsLight.broom, size: 21, color: c.icon),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: CbTypography.headingMd.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: CbTypography.bodySm.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];

    String? currentGroup;
    for (final destination in destinations) {
      if (destination.group != currentGroup) {
        currentGroup = destination.group;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 7),
            child: Text(
              currentGroup,
              style: CbTypography.labelXs.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      children.add(
        _UtilityNavigationTile(
          destination: destination,
          selected: destination.id == selectedId,
          enabled: enabled,
          onTap: () => onSelected(destination.id),
        ),
      );
    }

    return Container(
      key: const ValueKey<String>('cleaner-subfeature-selector'),
      color: c.fillSubtle,
      child: ListView(
        key: const PageStorageKey<String>('cleaner-utilities-sidebar'),
        padding: const EdgeInsets.only(bottom: 16),
        children: children,
      ),
    );
  }
}

class _UtilityNavigationTile extends StatelessWidget {
  final CleanerUtilityDestination destination;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _UtilityNavigationTile({
    required this.destination,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final foreground = selected ? c.accent.text : c.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Semantics(
        selected: selected,
        child: CbSurface(
          key: ValueKey<String>('cleaner-utility-${destination.id}'),
          selected: selected,
          onPressed: enabled ? onTap : null,
          semanticLabel: destination.title,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            child: Row(
              children: [
                Icon(destination.icon, size: 21, color: foreground),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CbTypography.body.copyWith(
                          color: foreground,
                          fontWeight: selected
                              ? CbTypography.semibold
                              : CbTypography.medium,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destination.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CbTypography.bodySm.copyWith(
                          color: selected
                              ? foreground.withValues(alpha: 0.78)
                              : c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(
                    PhosphorIconsLight.caretRight,
                    size: 18,
                    color: foreground,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactUtilityNavigation extends StatelessWidget {
  final String title;
  final String selectedId;
  final List<CleanerUtilityDestination> destinations;
  final ValueChanged<String> onSelected;
  final bool enabled;

  const _CompactUtilityNavigation({
    required this.title,
    required this.selectedId,
    required this.destinations,
    required this.onSelected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final selected = destinations.firstWhere(
      (destination) => destination.id == selectedId,
      orElse: () => destinations.first,
    );
    return Container(
      key: const ValueKey<String>('cleaner-subfeature-selector'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      color: c.fillSubtle,
      child: Row(
        children: [
          Icon(PhosphorIconsLight.broom, size: 20, color: c.accent.text),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CbTypography.headingSm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CbSelect<String>(
              key: const ValueKey<String>('cleaner-utility-popup'),
              value: selected.id,
              enabled: enabled,
              expand: true,
              tooltip: title,
              onChanged: onSelected,
              items: [
                for (final destination in destinations)
                  CbSelectItem(
                    value: destination.id,
                    label: destination.title,
                    icon: destination.icon,
                    keywords: destination.description,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

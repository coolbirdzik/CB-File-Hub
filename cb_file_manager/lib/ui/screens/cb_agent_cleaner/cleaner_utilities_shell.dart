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
    Key? key,
    required this.title,
    required this.subtitle,
    required this.selectedId,
    required this.destinations,
    required this.onSelected,
    required this.child,
    this.navigationEnabled = true,
  })  : assert(destinations.length > 0),
        super(key: key);

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
              const Divider(height: 1),
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
            const VerticalDivider(width: 1),
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
    final theme = Theme.of(context);
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
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.auto_fix_high_rounded,
                size: 21,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
              currentGroup.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
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
      color: theme.colorScheme.surfaceContainerLow,
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
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('cleaner-utility-${destination.id}'),
          onTap: enabled ? onTap : null,
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destination.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected
                              ? foreground.withValues(alpha: 0.78)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: foreground),
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
    final theme = Theme.of(context);
    final selected = destinations.firstWhere(
      (destination) => destination.id == selectedId,
      orElse: () => destinations.first,
    );
    return Container(
      key: const ValueKey<String>('cleaner-subfeature-selector'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Icon(
            Icons.auto_fix_high_rounded,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PopupMenuButton<String>(
              key: const ValueKey<String>('cleaner-utility-popup'),
              enabled: enabled,
              onSelected: onSelected,
              itemBuilder: (context) => destinations
                  .map(
                    (destination) => PopupMenuItem<String>(
                      value: destination.id,
                      child: Row(
                        children: [
                          Icon(destination.icon, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(destination.title),
                                Text(
                                  destination.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(selected.icon, size: 19),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        selected.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

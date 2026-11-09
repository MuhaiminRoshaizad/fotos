import 'package:flutter/material.dart';

import '../core/selection/selection.dart';
import '../core/theme/app_tokens.dart';

class NavDestination {
  const NavDestination(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const List<NavDestination> navDestinations = <NavDestination>[
  NavDestination(Icons.photo_library_outlined, Icons.photo_library, 'Photos'),
  NavDestination(Icons.video_library_outlined, Icons.video_library, 'Videos'),
  NavDestination(Icons.photo_album_outlined, Icons.photo_album, 'Albums'),
  NavDestination(Icons.folder_outlined, Icons.folder, 'Files'),
];

const double _itemWidth = 72;
const double _indicatorWidth = 56;

/// The pill that floats above the content. Icon over label so four
/// destinations fit a phone width; the indicator slides between them.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return _Pill(
      child: SizedBox(
        width: _itemWidth * navDestinations.length,
        height: AppNavMetrics.height - 12,
        child: Stack(
          children: <Widget>[
            AnimatedPositioned(
              duration: AppMotion.long,
              curve: AppMotion.emphasized,
              left: index * _itemWidth + (_itemWidth - _indicatorWidth) / 2,
              top: 4,
              width: _indicatorWidth,
              height: 30,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                for (int i = 0; i < navDestinations.length; i++)
                  _NavItem(
                    destination: navDestinations[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color color = selected ? cs.primary : cs.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: SizedBox(
          width: _itemWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                height: 30,
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: AppIconSize.standard,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Replaces the navigation pill while items are selected.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.actions,
    required this.enabled,
    required this.onAction,
  });

  final List<SelectionAction> actions;
  final bool enabled;
  final ValueChanged<SelectionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return _Pill(
      child: SizedBox(
        height: AppNavMetrics.height - 12,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final SelectionAction a in actions)
              Semantics(
                button: true,
                enabled: enabled,
                label: a.label,
                excludeSemantics: true,
                child: InkResponse(
                  onTap: enabled ? () => onAction(a) : null,
                  radius: 36,
                  child: SizedBox(
                    width: _itemWidth + 4,
                    child: Opacity(
                      opacity: enabled ? 1 : 0.4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            a.icon,
                            size: AppIconSize.standard,
                            color: a.destructive ? cs.error : cs.onSurface,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            a.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: 1.3),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: a.destructive ? cs.error : cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: child,
      ),
    );
  }
}

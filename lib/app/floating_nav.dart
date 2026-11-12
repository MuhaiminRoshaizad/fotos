import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/selection/selection.dart';
import '../core/theme/app_tokens.dart';

class NavDestination {
  const NavDestination(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const List<NavDestination> navDestinations = <NavDestination>[
  NavDestination(
    CupertinoIcons.photo_on_rectangle,
    CupertinoIcons.photo_fill_on_rectangle_fill,
    'Photos',
  ),
  NavDestination(
    CupertinoIcons.play_rectangle,
    CupertinoIcons.play_rectangle_fill,
    'Videos',
  ),
  NavDestination(
    CupertinoIcons.rectangle_stack,
    CupertinoIcons.rectangle_stack_fill,
    'Albums',
  ),
  NavDestination(CupertinoIcons.folder, CupertinoIcons.folder_fill, 'Files'),
];

const double _itemWidth = 72;
const double _indicatorWidth = 56;

/// The pill that floats above the content. Icon over label so four
/// destinations fit a phone width. The indicator springs to a newly opened
/// tab, passing it a little before it settles, and the tab's icon bounces.
class FloatingNav extends StatefulWidget {
  const FloatingNav({
    super.key,
    required this.index,
    required this.order,
    required this.onSelect,
    this.onLongPress,
  });

  /// The open tab, as an index into [navDestinations].
  final int index;

  /// The tabs from left to right, as indices into [navDestinations].
  final List<int> order;

  /// Called with the chosen tab's index into [navDestinations].
  final ValueChanged<int> onSelect;

  /// Pressing and holding the bar: opens the tab editor.
  final VoidCallback? onLongPress;

  @override
  State<FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<FloatingNav>
    with TickerProviderStateMixin {
  /// The bar dipping under the finger when held, before the editor opens.
  late final AnimationController _dip = AnimationController.unbounded(
    vsync: this,
  );

  Future<void> _held() async {
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _dip.animateTo(
        1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
      _dip.animateWith(SpringSimulation(AppMotion.spring, _dip.value, 0, 0));
    }
    widget.onLongPress?.call();
  }

  /// Where the indicator is, in tabs from the left.
  late final AnimationController _at = AnimationController.unbounded(
    vsync: this,
    value: _slot(widget).toDouble(),
  );

  /// The open tab's place in the bar.
  static int _slot(FloatingNav w) => w.order.indexOf(w.index);

  @override
  void didUpdateWidget(FloatingNav old) {
    super.didUpdateWidget(old);
    // A new tab, or the open tab moved by a new order.
    if (_slot(old) == _slot(widget)) return;
    final double to = _slot(widget).toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _at.value = to;
    } else {
      _at.animateWith(
        SpringSimulation(
          AppMotion.spring,
          _at.value,
          to,
          _at.velocity,
          snapToEnd: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _at.dispose();
    _dip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool still = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      onLongPress: widget.onLongPress == null ? null : _held,
      child: AnimatedBuilder(
        animation: _dip,
        builder: (BuildContext context, Widget? pill) =>
            Transform.scale(scale: 1 - 0.04 * _dip.value, child: pill),
        child: _Pill(
          child: SizedBox(
            width: _itemWidth * navDestinations.length,
            height: AppNavMetrics.height - 12,
            child: Stack(
              children: <Widget>[
                AnimatedBuilder(
                  animation: _at,
                  builder: (BuildContext context, Widget? child) {
                    final (double left, double width) = indicatorSpan(
                      _at.value,
                      navDestinations.length,
                    );
                    return Positioned(
                      left: left,
                      top: 4,
                      width: width,
                      height: 30,
                      child: child!,
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
                // Each tab slides to its new place when the order changes.
                for (int slot = 0; slot < widget.order.length; slot++)
                  AnimatedPositioned(
                    key: ValueKey<int>(widget.order[slot]),
                    duration: still ? Duration.zero : AppMotion.medium,
                    curve: AppMotion.emphasized,
                    left: slot * _itemWidth,
                    top: 0,
                    bottom: 0,
                    width: _itemWidth,
                    child: _NavItem(
                      destination: navDestinations[widget.order[slot]],
                      selected: widget.order[slot] == widget.index,
                      onTap: () => widget.onSelect(widget.order[slot]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Left edge and width of the indicator [at] tabs from the left. Past the
/// first or last tab the spring's overshoot squashes it against that end,
/// by up to a third of its width, instead of carrying it out of the pill.
(double, double) indicatorSpan(double at, int tabs) {
  final double last = tabs - 1.0;
  final double over = at < 0 ? -at : (at > last ? at - last : 0.0);
  final double width =
      _indicatorWidth -
      (over * _itemWidth).clamp(0, _indicatorWidth / 3).toDouble();
  final double inset = (_itemWidth - _indicatorWidth) / 2;
  final double left = at < 0
      ? inset
      : at > last
      ? last * _itemWidth + inset + _indicatorWidth - width
      : at * _itemWidth + inset;
  return (left, width);
}

/// One tab. No ripple: the indicator and a small bounce of the icon answer
/// the tap.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  late final Animation<double> _scale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 1, end: 1.28),
          weight: 1,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 1.28, end: 0.94),
          weight: 1,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 0.94, end: 1),
          weight: 1,
        ),
      ]).animate(CurvedAnimation(parent: _bounce, curve: Curves.easeOut));

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (widget.selected &&
        !old.selected &&
        !MediaQuery.disableAnimationsOf(context)) {
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool selected = widget.selected;
    final Color color = selected ? cs.primary : cs.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: widget.destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: _itemWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                height: 30,
                child: ScaleTransition(
                  scale: _scale,
                  child: Icon(
                    selected
                        ? widget.destination.selectedIcon
                        : widget.destination.icon,
                    size: AppIconSize.standard,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.destination.label,
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? () => onAction(a) : null,
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

/// Frosted glass: whatever scrolls behind shows through, blurred, as on
/// iOS. A hairline edge keeps it distinct over photos of any colour.
class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    const ShapeBorder shape = StadiumBorder();
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipPath(
        clipper: const ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: cs.surfaceContainerLow.withValues(
                alpha: dark ? 0.68 : 0.74,
              ),
              shape: StadiumBorder(
                side: BorderSide(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

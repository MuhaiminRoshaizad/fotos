import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'inset_group.dart';

/// Height of the bar under the status bar.
const double kBarHeight = 44;

/// A tab page in the iOS manner: a large title at the top of the content
/// that scrolls away under a frosted bar, which then shows the title small.
///
/// [body] builds the page and receives the [header] to put first in its
/// scroll view (or above a state that does not scroll), so the title moves
/// with the content. Scrolling is detected from the scroll notifications that
/// bubble up, so the body keeps its own controller.
class LargeTitleScaffold extends StatefulWidget {
  const LargeTitleScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.leading,
    this.trailing = const <Widget>[],
    this.barTitle,
    this.grouped = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> trailing;

  /// Shown in the bar at all times, with the bar solid, when set (for
  /// example "3 selected" while selecting).
  final String? barTitle;

  /// A page of inset groups: grey behind the rows in light mode.
  final bool grouped;

  final Widget Function(BuildContext context, Widget header) body;

  @override
  State<LargeTitleScaffold> createState() => _LargeTitleScaffoldState();
}

class _LargeTitleScaffoldState extends State<LargeTitleScaffold> {
  bool _collapsed = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final bool c = n.metrics.pixels > 40;
    if (c != _collapsed) setState(() => _collapsed = c);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    final bool solid = _collapsed || widget.barTitle != null;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color background = widget.grouped ? cs.groupedBackground : cs.surface;
    return Scaffold(
      backgroundColor: background,
      // Nothing here takes text; dialogs handle the keyboard themselves.
      resizeToAvoidBottomInset: false,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: widget.body(
                context,
                LargeTitle(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  topInset: top + kBarHeight,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: FrostedBar(
                solid: solid,
                background: background,
                title: widget.barTitle ?? widget.title,
                leading: widget.leading,
                trailing: widget.trailing,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The large title block that opens a [LargeTitleScaffold]'s content.
class LargeTitle extends StatelessWidget {
  const LargeTitle({
    super.key,
    required this.title,
    required this.topInset,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final double topInset;

  static TextScaler _scaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5);

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextScaler scaler = _scaler(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        topInset,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: scaler,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                height: 1.15,
                color: cs.onSurface,
              ),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: scaler,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// The bar across the top: clear over the large title, frosted with a
/// hairline and a small centred title once content scrolls under it.
class FrostedBar extends StatelessWidget {
  const FrostedBar({
    super.key,
    required this.solid,
    required this.title,
    this.background,
    this.leading,
    this.trailing = const <Widget>[],
  });

  final bool solid;

  /// The page colour the bar frosts over; the surface when null.
  final Color? background;
  final String title;
  final Widget? leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double top = MediaQuery.paddingOf(context).top;
    final Widget row = SizedBox(
      height: top + kBarHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.sm, top, AppSpacing.sm, 0),
        child: NavigationToolbar(
          leading: leading,
          middle: AnimatedOpacity(
            opacity: solid ? 1 : 0,
            duration: AppMotion.short,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: trailing),
          middleSpacing: AppSpacing.sm,
        ),
      ),
    );
    return Stack(
      children: <Widget>[
        // The blur is only built while solid: a hidden BackdropFilter still
        // costs a full-screen pass every frame.
        if (solid)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: (background ?? cs.surface).withValues(alpha: 0.78),
                    border: Border(
                      bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        row,
      ],
    );
  }
}

/// A button in a [FrostedBar]: a small capsule with a label or an icon.
/// The tap area is 44 pt square or larger; pressing dims it.
class BarButton extends StatelessWidget {
  const BarButton.text({
    super.key,
    required String this.label,
    required this.onPressed,
    this.prominent = false,
  }) : icon = null,
       tooltip = null;

  const BarButton.icon({
    super.key,
    required IconData this.icon,
    required String this.tooltip,
    required this.onPressed,
  }) : label = null,
       prominent = false;

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  /// Drawn in the accent colour, for the action that ends a mode (Done).
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Widget capsule = Container(
      height: 32,
      constraints: const BoxConstraints(minWidth: 32),
      padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
      decoration: BoxDecoration(
        color: prominent ? cs.primary : cs.onSurface.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      // Sized to its label: an aligned Container would fill the whole bar.
      child: Center(
        widthFactor: 1,
        child: label != null
            ? Text(
                label!,
                maxLines: 1,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.2),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: prominent ? cs.onPrimary : cs.onSurface,
                ),
              )
            : Icon(icon, size: AppIconSize.dense, color: cs.onSurface),
      ),
    );
    final Widget button = CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(44, 44),
      pressedOpacity: 0.5,
      onPressed: onPressed,
      child: Opacity(opacity: onPressed == null ? 0.4 : 1, child: capsule),
    );
    return tooltip == null
        ? Semantics(button: true, child: button)
        : Tooltip(message: tooltip, child: button);
  }
}

/// iOS's back button for a pushed page: a chevron and the previous page's
/// name in the accent colour (Flutter's own Cupertino widget, so it matches
/// iOS exactly). Does what the system back gesture does.
class BackBarButton extends StatelessWidget {
  const BackBarButton({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.2,
    child: CupertinoNavigationBarBackButton(previousPageTitle: label),
  );
}

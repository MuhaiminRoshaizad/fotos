import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// iOS grouped-list colours: the page behind the groups, and the rows.
extension GroupedColors on ColorScheme {
  /// Grey page in light mode (rows are white on it); the plain surface in
  /// dark mode, where the rows are the lighter layer.
  Color get groupedBackground =>
      brightness == Brightness.light ? surfaceContainerLow : surface;

  Color get groupedRow => brightness == Brightness.light
      ? surfaceContainerLowest
      : surfaceContainerLow;
}

/// A rounded group of rows inset from the screen edges, as in iOS Settings,
/// with an optional heading above and note below.
class InsetGroup extends StatelessWidget {
  const InsetGroup({
    super.key,
    required this.children,
    this.header,
    this.footer,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (header != null) GroupHeading(header!),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Material(
              color: cs.groupedRow,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < children.length; i++) ...<Widget>[
                    if (i > 0) const _RowDivider(),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.sm,
              AppSpacing.xxl,
              0,
            ),
            child: Text(
              footer!,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// One row of a long inset group built lazily by a list builder: rounds the
/// group's top and bottom corners and draws the hairline between rows.
class InsetGroupItem extends StatelessWidget {
  const InsetGroupItem({
    super.key,
    required this.first,
    required this.last,
    required this.child,
  });

  final bool first;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const Radius r = Radius.circular(AppRadii.md);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: first ? r : Radius.zero,
          bottom: last ? r : Radius.zero,
        ),
        child: Material(
          color: Theme.of(context).colorScheme.groupedRow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[if (!first) const _RowDivider(), child],
          ),
        ),
      ),
    );
  }
}

/// A section heading in the iOS large style ("On this phone").
class GroupHeading extends StatelessWidget {
  const GroupHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A hairline between rows that starts after the leading icon, as iOS does.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// One row in an [InsetGroup]: icon, title and optional subtitle, an
/// optional value, and a chevron when it leads somewhere.
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.chevron = true,
    this.destructive = false,
  });

  final String title;
  final Widget? leading;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                IconTheme.merge(
                  data: IconThemeData(
                    color: destructive ? cs.error : cs.primary,
                    size: AppIconSize.standard,
                  ),
                  child: SizedBox(width: 26, child: Center(child: leading)),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: destructive ? cs.error : cs.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Text(
                    value!,
                    style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                  ),
                ),
              ?trailing,
              if (chevron && onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

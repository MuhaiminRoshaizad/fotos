import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'inset_group.dart';

/// The only way the app opens a task sheet (a picker, a form, details).
///
/// `showModalBottomSheet` draws under the system navigation bar and its
/// `useSafeArea` guards only top, left and right, so the content is wrapped in
/// a bottom-only [SafeArea]: the sheet colour still runs behind the bar while
/// its last row ends above it. The iOS card look (grabber, 14 pt corners)
/// comes from the theme's `bottomSheetTheme`.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: scrollControlled,
    builder: (BuildContext sheetContext) => OnSheet(
      child: SafeArea(top: false, child: Builder(builder: builder)),
    ),
  );
}

/// The heading of a task sheet: a small centred title, as on iOS, with an
/// optional line under it.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Semantics(
        header: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// One choice in an action sheet.
class SheetChoice<T> {
  const SheetChoice(this.value, this.label, {this.destructive = false});

  final T value;
  final String label;

  /// Drawn in red: deletes something.
  final bool destructive;
}

/// The only way the app offers a short list of choices about one thing:
/// iOS's action sheet, floating above the bottom edge with Cancel set apart.
/// Returns the chosen value, or null on Cancel or a tap outside.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<SheetChoice<T>> choices,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (BuildContext ctx) => CupertinoActionSheet(
      title: title == null
          ? null
          : Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      message: message == null ? null : Text(message),
      actions: <Widget>[
        for (final SheetChoice<T> c in choices)
          CupertinoActionSheetAction(
            isDestructiveAction: c.destructive,
            onPressed: () => Navigator.of(ctx).pop(c.value),
            child: Text(c.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('Cancel'),
      ),
    ),
  );
}

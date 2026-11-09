import 'package:flutter/material.dart';

/// The only way the app opens a bottom sheet.
///
/// `showModalBottomSheet` draws under the system navigation bar and its
/// `useSafeArea` guards only top, left and right, so the content is wrapped in
/// a bottom-only [SafeArea]: the sheet colour still runs behind the bar while
/// its last row ends above it.
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
    builder: (BuildContext sheetContext) =>
        SafeArea(top: false, child: builder(sheetContext)),
  );
}

/// A row inside an action sheet.
class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color color = destructive ? cs.error : cs.onSurface;
    return ListTile(
      leading: Icon(icon, color: destructive ? cs.error : cs.onSurfaceVariant),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}

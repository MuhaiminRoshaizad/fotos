import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics/app_haptics.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/inset_group.dart';
import '../core/widgets/large_title_scaffold.dart';
import 'floating_nav.dart';
import 'tab_order.dart';

/// The sheet for putting the tabs in another order: each tab a row with a
/// grip to drag it by. Done keeps the order; closing the sheet any other
/// way leaves it as it was. The first tab is where fotos opens.
Future<void> showEditTabs(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) => _EditTabs(
      order: ref.read(tabOrderProvider),
      onDone: (List<int> order) {
        ref.read(tabOrderProvider.notifier).set(order);
        Navigator.of(context).pop();
      },
    ),
  );
}

class _EditTabs extends StatefulWidget {
  const _EditTabs({required this.order, required this.onDone});

  final List<int> order;
  final ValueChanged<List<int>> onDone;

  @override
  State<_EditTabs> createState() => _EditTabsState();
}

class _EditTabsState extends State<_EditTabs> {
  late final List<int> _order = List<int>.of(widget.order);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Stack(
          children: <Widget>[
            const SheetTitle(
              'Edit tabs',
              subtitle: 'Hold a tab and drag it. fotos opens on the first.',
            ),
            Positioned(
              right: AppSpacing.sm,
              top: -6,
              child: BarButton.text(
                label: 'Done',
                prominent: true,
                onPressed: () => widget.onDone(_order),
              ),
            ),
          ],
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          // A tick as a row is picked up, as for each item drag-select adds.
          onReorderStart: (_) => AppHaptics.tick(),
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          onReorderItem: (int from, int to) =>
              setState(() => _order.insert(to, _order.removeAt(from))),
          proxyDecorator: (Widget child, int index, Animation<double> a) =>
              AnimatedBuilder(
                animation: a,
                builder: (BuildContext context, Widget? child) => Material(
                  color: Colors.transparent,
                  elevation: 8 * a.value,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: Transform.scale(
                    scale: 1 + 0.02 * a.value,
                    child: child,
                  ),
                ),
                child: child,
              ),
          children: <Widget>[
            for (int i = 0; i < _order.length; i++)
              InsetGroupItem(
                key: ValueKey<int>(_order[i]),
                first: i == 0,
                last: i == _order.length - 1,
                // Press and hold anywhere on a row to pick it up; its grip
                // picks it up at once.
                child: ReorderableDelayedDragStartListener(
                  index: i,
                  child: _TabRow(
                    tab: navDestinations[_order[i]],
                    index: i,
                    opensFirst: i == 0,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tab,
    required this.index,
    required this.opensFirst,
  });

  final NavDestination tab;
  final int index;
  final bool opensFirst;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: Row(
        children: <Widget>[
          const SizedBox(width: AppSpacing.lg),
          Icon(tab.icon, size: AppIconSize.standard, color: cs.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              tab.label,
              style: TextStyle(fontSize: 16, color: cs.onSurface),
            ),
          ),
          if (opensFirst)
            Text(
              'Opens first',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: 'Move ${tab.label}',
              button: true,
              child: SizedBox.square(
                dimension: 48,
                child: Icon(
                  CupertinoIcons.line_horizontal_3,
                  size: AppIconSize.dense,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }
}

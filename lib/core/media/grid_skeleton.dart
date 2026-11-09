import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../theme/app_tokens.dart';
import 'grouping.dart';

/// Loading state for a media grid: one heading and the rows of tiles at the
/// exact size and column count the real grid will use, so nothing moves when
/// the thumbnails arrive.
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key, required this.level});

  final GridLevel level;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Skeletonizer(
      enabled: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final int columns = level.columnsFor(c.maxWidth);
          final double tile = (c.maxWidth - 2 * (columns - 1)) / columns;
          final int rows = (c.maxHeight / (tile + 2)).ceil();
          return ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: <Widget>[
              const SizedBox(
                height: 44,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Text('November 2026'),
                ),
              ),
              GridView.count(
                crossAxisCount: columns,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: List<Widget>.generate(
                  rows * columns,
                  (_) => ColoredBox(color: cs.surfaceContainerHigh),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

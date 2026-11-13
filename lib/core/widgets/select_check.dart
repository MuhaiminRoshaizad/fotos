import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The circle in a tile's corner while selecting: hollow, then filled with
/// a tick once the tile is selected.
class SelectCheck extends StatelessWidget {
  const SelectCheck({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.short,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? cs.primary : Colors.black.withValues(alpha: 0.18),
        border: Border.all(
          color: selected ? cs.surface : Colors.white,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(CupertinoIcons.checkmark, size: 14, color: cs.onPrimary)
          : null,
    );
  }
}

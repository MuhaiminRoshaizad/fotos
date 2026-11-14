import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A small dark label in a thumbnail's corner, readable over any picture:
/// a video's length, a comic's page count.
class CornerBadge extends StatelessWidget {
  const CornerBadge({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(2, 1, 6, 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}

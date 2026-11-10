import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'entrance.dart';

/// Centred icon, headline, explanation and an optional action. Used for empty,
/// error and permission states so they all look alike. On a page the user
/// opened, the four parts rise in turn like the page's rows would have.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xxl * 3,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: staggered(<Widget>[
              // A plain glyph, not an accent-tinted tile: the accent belongs
              // to the one action below it.
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Icon(
                  icon,
                  size: 44,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: cs.onSurface,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs + 2),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (actionLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: FilledButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ),
              if (secondaryLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: TextButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

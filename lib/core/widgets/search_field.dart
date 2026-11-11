import 'package:flutter/cupertino.dart'
    show CupertinoButton, CupertinoSearchTextField;
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// iOS's search field, with Cancel sliding in beside it while it is in use.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.focus,
    required this.active,
    required this.placeholder,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool active;
  final String placeholder;

  static const double height = 36;
  static const EdgeInsets padding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.xs,
    AppSpacing.lg,
    AppSpacing.sm,
  );

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height),
              child: CupertinoSearchTextField(
                controller: controller,
                focusNode: focus,
                placeholder: placeholder,
                style: TextStyle(fontSize: 16, color: cs.onSurface),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.decelerate,
            alignment: Alignment.centerLeft,
            child: active
                ? CupertinoButton(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    minimumSize: const Size(44, 44),
                    onPressed: () {
                      controller.clear();
                      focus.unfocus();
                    },
                    child: const Text('Cancel'),
                  )
                : const SizedBox(height: 44),
          ),
        ],
      ),
    );
  }
}

/// Holds the search field's place while a page loads, so nothing moves
/// when the field arrives.
class SearchFieldPlaceholder extends StatelessWidget {
  const SearchFieldPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: SearchField.padding,
    child: Container(
      height: 44,
      alignment: Alignment.center,
      child: Container(
        height: SearchField.height,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    ),
  );
}

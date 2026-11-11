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

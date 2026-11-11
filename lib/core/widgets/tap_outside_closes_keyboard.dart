import 'package:flutter/widgets.dart';

/// A tap anywhere outside a text field takes the focus off it, which closes
/// the keyboard, as in most phone apps.
///
/// Flutter does this only on desktop and the web: on Android a touch outside
/// a field leaves it focused (EditableText's default tap-outside action).
/// Every field below this widget uses this action instead.
class TapOutsideClosesKeyboard extends StatelessWidget {
  const TapOutsideClosesKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      EditableTextTapOutsideIntent:
          CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (EditableTextTapOutsideIntent intent) {
              intent.focusNode.unfocus();
              return null;
            },
          ),
    },
    child: child,
  );
}

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../haptics/app_haptics.dart';

/// Press and hold in the text field inside [child], then slide, to move the
/// cursor, as on an iPhone.
///
/// Flutter picks the long-press behaviour of its text fields by platform:
/// on Android a hold selects the word under the finger. This claims the
/// hold a little sooner than the field's own (500 ms), so the field never
/// sees it, and places the cursor under the finger for as long as it moves.
/// Taps, double taps and the selection handles are untouched.
class HoldToMoveCursor extends StatefulWidget {
  const HoldToMoveCursor({super.key, required this.child});

  final Widget child;

  /// Shorter than [kLongPressTimeout], which the field's own hold waits for.
  static const Duration hold = Duration(milliseconds: 350);

  @override
  State<HoldToMoveCursor> createState() => _HoldToMoveCursorState();
}

class _HoldToMoveCursorState extends State<HoldToMoveCursor> {
  EditableTextState? _field;

  EditableTextState? _find() {
    EditableTextState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  void _start(LongPressStartDetails d) {
    _field = _find();
    final EditableTextState? field = _field;
    if (field == null) return;
    AppHaptics.longPress();
    field.requestKeyboard();
    field.hideToolbar();
    _moveTo(d.globalPosition);
  }

  void _move(LongPressMoveUpdateDetails d) => _moveTo(d.globalPosition);

  void _end(LongPressEndDetails d) => _field = null;

  void _moveTo(Offset global) {
    final EditableTextState? field = _field;
    if (field == null || !field.mounted) return;
    final TextPosition at = field.renderEditable.getPositionForPoint(global);
    final TextEditingValue now = field.textEditingValue;
    if (now.selection.isCollapsed && now.selection.baseOffset == at.offset) {
      return;
    }
    field.userUpdateTextEditingValue(
      now.copyWith(
        selection: TextSelection.collapsed(
          offset: at.offset,
          affinity: at.affinity,
        ),
      ),
      SelectionChangedCause.drag,
    );
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.translucent,
    gestures: <Type, GestureRecognizerFactory>{
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: HoldToMoveCursor.hold,
              debugOwner: this,
            ),
            (LongPressGestureRecognizer r) {
              r
                ..onLongPressStart = _start
                ..onLongPressMoveUpdate = _move
                ..onLongPressEnd = _end;
            },
          ),
    },
    child: widget.child,
  );
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import '../haptics/app_haptics.dart';
import '../theme/app_tokens.dart';
import 'app_sheet.dart';
import 'hold_to_move_cursor.dart';
import 'motion.dart';

/// Confirms a destructive or irreversible action. Returns true on confirm.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final bool? ok = await showCupertinoDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (BuildContext ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        // iOS bolds the safe choice: Cancel when the action destroys.
        CupertinoDialogAction(
          isDefaultAction: destructive,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: !destructive,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for a name (album, folder, file) in a sheet, where a long name wraps
/// onto as many lines as it needs. [validate] returns an error message or
/// null. Errors appear once the field has been left with text in it or on
/// submit, and clear as soon as the value becomes valid.
///
/// With [selectStem], a file's ending (.cbz, .pdf) is shown after the field
/// and kept, so it can't be lost by accident; [validate] and the result
/// still see the whole name.
Future<String?> promptName(
  BuildContext context, {
  required String title,
  required String label,
  required String hint,
  required String confirmLabel,
  required String? Function(String value) validate,
  String initial = '',
  bool selectStem = false,
  TextInputType keyboardType = TextInputType.text,
  List<TextInputFormatter>? inputFormatters,
  String subject = 'name',
}) {
  return showAppSheet<String>(
    context,
    scrollControlled: true,
    builder: (BuildContext ctx) => _NameSheet(
      title: title,
      label: label,
      hint: hint,
      confirmLabel: confirmLabel,
      validate: validate,
      initial: initial,
      selectStem: selectStem,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      subject: subject,
    ),
  );
}

/// [name] split into the part to edit and the ending to keep. Only a dot
/// with something either side of it starts an ending.
@visibleForTesting
(String, String) splitEnding(String name) {
  final int dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return (name, '');
  return (name.substring(0, dot), name.substring(dot));
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({
    required this.title,
    required this.label,
    required this.hint,
    required this.confirmLabel,
    required this.validate,
    required this.initial,
    required this.selectStem,
    required this.keyboardType,
    required this.inputFormatters,
    required this.subject,
  });

  final String title;
  final String label;
  final String hint;
  final String confirmLabel;
  final String? Function(String value) validate;
  final String initial;
  final bool selectStem;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// What is being typed, for the hint on moving the cursor.
  final String subject;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final (String, String) _parts = widget.selectStem
      ? splitEnding(widget.initial)
      : (widget.initial, '');
  late final TextEditingController _controller = TextEditingController(
    text: _parts.$1,
  );
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _armed = false;

  String get _ending => _parts.$2;
  String get _value => '${_controller.text.trim()}$_ending';

  @override
  void initState() {
    super.initState();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _focus.addListener(() {
      if (!_focus.hasFocus && _controller.text.trim().isNotEmpty) _check();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _check() {
    _armed = true;
    final String? e = _controller.text.trim().isEmpty
        ? widget.validate('')
        : widget.validate(_value);
    setState(() => _error = e);
    return e == null;
  }

  void _submit() {
    if (!_check()) {
      AppHaptics.error();
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextStyle text = TextStyle(fontSize: 17, color: cs.onSurface);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Pressable(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(fontSize: 17, color: cs.primary),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Pressable(
                  label: widget.confirmLabel,
                  onTap: _submit,
                  child: Text(
                    widget.confirmLabel,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Semantics(
              label: widget.label,
              textField: true,
              child: HoldToMoveCursor(
                child: CupertinoTextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  placeholder: widget.hint,
                  style: text,
                  // Wraps rather than scrolls sideways; Done still submits.
                  minLines: 1,
                  maxLines: 6,
                  keyboardType: widget.keyboardType,
                  inputFormatters: widget.inputFormatters,
                  textInputAction: TextInputAction.done,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  suffix: _ending.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.md),
                          child: Text(
                            _ending,
                            style: text.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_armed && _error != null) _check();
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Text(
              _error ??
                  (_ending.isEmpty
                      ? 'Press and hold the ${widget.subject}, then slide, to '
                            'move the cursor.'
                      : 'The $_ending ending is kept. Press and hold the '
                            '${widget.subject}, '
                            'then slide, to move the cursor.'),
              style: TextStyle(
                fontSize: 13,
                color: _error == null ? cs.onSurfaceVariant : cs.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

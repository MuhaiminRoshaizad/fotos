import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';

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

/// Asks for a name (album, folder, file). [validate] returns an error message
/// or null. Errors appear once the field has been left with text in it or on
/// submit, and clear as soon as the value becomes valid.
Future<String?> promptName(
  BuildContext context, {
  required String title,
  required String label,
  required String hint,
  required String confirmLabel,
  required String? Function(String value) validate,
  String initial = '',
  bool selectStem = false,
}) {
  return showCupertinoDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (BuildContext ctx) => _NameDialog(
      title: title,
      label: label,
      hint: hint,
      confirmLabel: confirmLabel,
      validate: validate,
      initial: initial,
      selectStem: selectStem,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.confirmLabel,
    required this.validate,
    required this.initial,
    required this.selectStem,
  });

  final String title;
  final String label;
  final String hint;
  final String confirmLabel;
  final String? Function(String value) validate;
  final String initial;
  final bool selectStem;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    final int dot = widget.initial.lastIndexOf('.');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.selectStem && dot > 0 ? dot : widget.initial.length,
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
    final String? e = widget.validate(_controller.text.trim());
    setState(() => _error = e);
    return e == null;
  }

  void _submit() {
    if (!_check()) {
      AppHaptics.error();
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              label: widget.label,
              textField: true,
              child: CupertinoTextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                placeholder: widget.hint,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_armed && _error != null) _check();
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  textAlign: TextAlign.start,
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

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
  final bool? ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (BuildContext ctx) {
      final ColorScheme cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: destructive
                ? TextButton.styleFrom(foregroundColor: cs.error)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
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
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
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
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_armed && _error != null) _check();
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

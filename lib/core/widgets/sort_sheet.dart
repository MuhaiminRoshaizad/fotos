import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoSlidingSegmentedControl, CupertinoSwitch;
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_sheet.dart';
import 'inset_group.dart';

/// What the sort sheet returns: the chosen key's index, whether the second
/// direction was picked, and whether it should become the default for
/// everything of its kind.
class SortPick {
  const SortPick(
    this.by, {
    required this.reversed,
    this.forAll = false,
    this.option = false,
  });
  final int by;
  final bool reversed;
  final bool forAll;

  /// The sheet's extra switch, when it has one (see [SortOption]).
  final bool option;
}

/// A switch the sort sheet offers beside the order, such as an album's
/// Favourites first.
class SortOption {
  const SortOption(this.label, {required this.footer, required this.value});
  final String label;

  /// Said under the switch, so its effect is plain before it is tried.
  final String footer;
  final bool value;
}

/// The sort sheet: a key to sort by and one of its two directions. With
/// [forAllLabel] it also offers to make the choice the default for every
/// album or folder that has not been given its own order.
Future<SortPick?> pickSort(
  BuildContext context, {
  required String title,
  required List<String> labels,
  required List<(String, String)> directions,
  required int by,
  required bool reversed,
  String? forAllLabel,
  SortOption? option,
}) => showAppSheet<SortPick>(
  context,
  // Sized to its rows, not Flutter's default cap of 9/16 of the screen:
  // with Favourites first added the cap cut Apply off under the navigation
  // bar on a Pixel 9 Pro (21/11/2026). Past the screen, it scrolls.
  scrollControlled: true,
  builder: (BuildContext ctx) => _SortSheet(
    title: title,
    labels: labels,
    directions: directions,
    by: by,
    reversed: reversed,
    forAllLabel: forAllLabel,
    option: option,
  ),
);

class _SortSheet extends StatefulWidget {
  const _SortSheet({
    required this.title,
    required this.labels,
    required this.directions,
    required this.by,
    required this.reversed,
    required this.forAllLabel,
    required this.option,
  });
  final String title;
  final List<String> labels;
  final List<(String, String)> directions;
  final int by;
  final bool reversed;
  final String? forAllLabel;
  final SortOption? option;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late int _by = widget.by;
  late bool _reversed = widget.reversed;
  late bool _option = widget.option?.value ?? false;
  bool _forAll = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final (String first, String second) = widget.directions[_by];
    final String? forAll = widget.forAllLabel;
    final SortOption? option = widget.option;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetTitle(widget.title),
          // iOS marks the choice with a checkmark, not a radio button.
          InsetGroup(
            children: <Widget>[
              for (final (int i, String label) in widget.labels.indexed)
                Semantics(
                  selected: i == _by,
                  inMutuallyExclusiveGroup: true,
                  child: GroupRow(
                    title: label,
                    chevron: false,
                    trailing: i == _by
                        ? Icon(
                            CupertinoIcons.checkmark,
                            size: 20,
                            color: cs.primary,
                          )
                        : null,
                    onTap: () => setState(() {
                      _by = i;
                      _reversed = false;
                    }),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: CupertinoSlidingSegmentedControl<bool>(
              groupValue: _reversed,
              children: <bool, Widget>{
                false: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(first),
                ),
                true: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(second),
                ),
              },
              onValueChanged: (bool? v) {
                if (v != null) setState(() => _reversed = v);
              },
            ),
          ),
          if (option != null)
            InsetGroup(
              footer: option.footer,
              children: <Widget>[
                MergeSemantics(
                  child: GroupRow(
                    title: option.label,
                    chevron: false,
                    trailing: CupertinoSwitch(
                      value: _option,
                      onChanged: (bool v) => setState(() => _option = v),
                    ),
                    onTap: () => setState(() => _option = !_option),
                  ),
                ),
              ],
            ),
          if (forAll != null)
            InsetGroup(
              footer: _forAll
                  ? 'New ones, and any you have not sorted yourself, use this '
                        'order.'
                  : 'Only this one changes.',
              children: <Widget>[
                MergeSemantics(
                  child: GroupRow(
                    title: forAll,
                    chevron: false,
                    trailing: CupertinoSwitch(
                      value: _forAll,
                      onChanged: (bool v) => setState(() => _forAll = v),
                    ),
                    onTap: () => setState(() => _forAll = !_forAll),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(
                SortPick(
                  _by,
                  reversed: _reversed,
                  forAll: _forAll,
                  option: _option,
                ),
              ),
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

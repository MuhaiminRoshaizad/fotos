import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One button on the floating selection bar.
class SelectionAction {
  const SelectionAction({
    required this.icon,
    required this.label,
    required this.run,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext context, Set<String> ids) run;
  final bool destructive;
}

/// Which screen is selecting, what is selected, and what the bar offers.
@immutable
class SelectionState {
  const SelectionState({
    this.owner,
    this.ids = const <String>{},
    this.actions = const <SelectionAction>[],
  });

  final String? owner;
  final Set<String> ids;
  final List<SelectionAction> actions;

  bool get active => owner != null;
  bool isActiveFor(String key) => owner == key;
}

class SelectionNotifier extends Notifier<SelectionState> {
  @override
  SelectionState build() => const SelectionState();

  void start(
    String owner,
    List<SelectionAction> actions, {
    Set<String> initial = const <String>{},
  }) {
    state = SelectionState(owner: owner, ids: initial, actions: actions);
  }

  void setIds(Set<String> ids) {
    if (!state.active) return;
    state = SelectionState(
      owner: state.owner,
      ids: Set<String>.unmodifiable(ids),
      actions: state.actions,
    );
  }

  void toggle(String id) {
    final Set<String> next = Set<String>.of(state.ids);
    if (!next.remove(id)) next.add(id);
    setIds(next);
  }

  void clear() => state = const SelectionState();
}

final NotifierProvider<SelectionNotifier, SelectionState> selectionProvider =
    NotifierProvider<SelectionNotifier, SelectionState>(SelectionNotifier.new);

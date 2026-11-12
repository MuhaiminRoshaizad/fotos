import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/selection/selection.dart';
import '../core/widgets/toast.dart';
import 'tab_order.dart';

/// Wraps each tab's first page, so Back there follows Android's rule for
/// bottom tabs: another tab goes back to the first one, and only the first
/// one leaves the app, after a "press back again" toast so a stray swipe
/// doesn't close fotos.
///
/// It sits on the tab's page, not on the shell around the tabs: on Android
/// 14 and later the app tells Android in advance whether it will handle
/// Back, and each tab's navigator answers that for itself. A guard on the
/// shell is outvoted and Android closes the app without asking.
class TabRoot extends ConsumerWidget {
  const TabRoot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (didPop) return;
        final SelectionNotifier selection = ref.read(
          selectionProvider.notifier,
        );
        // A selection on the tab is cleared first; pages that handle their
        // own selection have done so already.
        if (ref.read(selectionProvider).active) {
          selection.clear();
          return;
        }
        final StatefulNavigationShellState? shell =
            StatefulNavigationShell.maybeOf(context);
        if (shell == null) return;
        ref
            .read(backToCloseProvider)
            .back(
              context,
              current: shell.currentIndex,
              first: ref.read(tabOrderProvider).first,
              goTo: (int i) {
                selection.clear();
                shell.goBranch(i);
              },
            );
      },
      child: child,
    );
  }
}

/// Remembers, across the four tabs, whether Back has just asked to be
/// pressed again.
class BackToClose {
  /// How long a second Back still closes the app: as long as the toast
  /// asking for it shows.
  static const Duration window = Duration(seconds: 3);

  Timer? _asking;

  void back(
    BuildContext context, {
    required int current,
    required int first,
    required ValueChanged<int> goTo,
  }) {
    if (current != first) {
      _asking?.cancel();
      goTo(first);
      return;
    }
    if (_asking?.isActive ?? false) {
      _asking!.cancel();
      SystemNavigator.pop();
      return;
    }
    _asking = Timer(window, () {});
    showToast(
      context,
      'Press back again to close fotos',
      icon: CupertinoIcons.info_circle,
    );
  }

  void dispose() => _asking?.cancel();
}

final Provider<BackToClose> backToCloseProvider = Provider<BackToClose>((
  Ref ref,
) {
  final BackToClose b = BackToClose();
  ref.onDispose(b.dispose);
  return b;
});

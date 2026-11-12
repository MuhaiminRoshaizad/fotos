import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/preferences.dart';

/// The four tabs' addresses, in the router's branch order.
const List<String> tabPaths = <String>[
  '/photos',
  '/videos',
  '/albums',
  '/files',
];

/// The tabs as the bar shows them, as branch indices into [tabPaths]. The
/// first is where fotos opens and where Back returns to.
const List<int> defaultTabOrder = <int>[0, 1, 2, 3];

/// The saved order, read before the app starts so the router can open on
/// its first tab without showing Photos first. Overridden in main.
final Provider<List<int>> initialTabOrderProvider = Provider<List<int>>(
  (Ref ref) => defaultTabOrder,
);

/// [saved] as an order of all four tabs, or the default when it is not one
/// (missing, a tab short, or from an older version).
List<int> decodeTabOrder(List<String>? saved) {
  if (saved == null || saved.length != tabPaths.length) return defaultTabOrder;
  final List<int> order = <int>[
    for (final String p in saved) tabPaths.indexOf(p),
  ];
  return order.toSet().length == tabPaths.length && !order.contains(-1)
      ? List<int>.unmodifiable(order)
      : defaultTabOrder;
}

/// The tab bar's order, kept between sessions by tab address.
class TabOrderNotifier extends Notifier<List<int>> {
  static const String key = 'tabs.order';

  static Future<List<int>> load(SharedPreferencesAsync prefs) async {
    try {
      return decodeTabOrder(await prefs.getStringList(key));
    } on Exception {
      return defaultTabOrder;
    }
  }

  @override
  List<int> build() => ref.read(initialTabOrderProvider);

  Future<void> set(List<int> order) async {
    state = List<int>.unmodifiable(order);
    await ref.read(preferencesProvider).setStringList(key, <String>[
      for (final int i in order) tabPaths[i],
    ]);
  }
}

final NotifierProvider<TabOrderNotifier, List<int>> tabOrderProvider =
    NotifierProvider<TabOrderNotifier, List<int>>(TabOrderNotifier.new);

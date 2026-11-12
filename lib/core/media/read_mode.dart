import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences.dart';

/// How a folder's pictures are read, switched from the viewer's top bar.
enum ReadMode {
  /// Swipe sideways; a tap shows or hides the controls.
  photos('Photos'),

  /// As photos, but a tap on the left or right third turns the page, for
  /// comics; the middle third shows or hides the controls.
  pages('Pages'),

  /// Every page joined top to bottom in one long scroll.
  strip('Strip');

  const ReadMode(this.label);
  final String label;

  static ReadMode decode(String s) => ReadMode.values.firstWhere(
    (ReadMode m) => m.name == s,
    orElse: () => ReadMode.photos,
  );
}

/// A folder's key for its reading mode: its path inside shared storage with
/// no slash at either end ("Comic/Album/Iron Orchard"). The same folder
/// gets the same key whether it is opened as an album or from Files.
String readingKey(String relativePath) =>
    relativePath.replaceAll(RegExp(r'^/+|/+$'), '');

/// The mode [folder] is read in; Photos for none, or for a mixed view
/// such as the Photos tab, which has no folder.
ReadMode readModeFor(Map<String, ReadMode>? modes, String? folder) =>
    folder == null ? ReadMode.photos : (modes?[folder] ?? ReadMode.photos);

/// Folders read other than as photos, by [readingKey].
class ReadModesNotifier extends AsyncNotifier<Map<String, ReadMode>> {
  static const String _key = 'reading.folders';

  @override
  Future<Map<String, ReadMode>> build() async {
    final String? raw = await ref.watch(preferencesProvider).getString(_key);
    if (raw == null) return const <String, ReadMode>{};
    return <String, ReadMode>{
      for (final MapEntry<String, Object?> e
          in (jsonDecode(raw) as Map<String, Object?>).entries)
        e.key: ReadMode.decode(e.value! as String),
    };
  }

  Future<void> _save(Map<String, ReadMode> next) async {
    state = AsyncData<Map<String, ReadMode>>(next);
    await ref
        .read(preferencesProvider)
        .setString(
          _key,
          jsonEncode(<String, String>{
            for (final MapEntry<String, ReadMode> e in next.entries)
              e.key: e.value.name,
          }),
        );
  }

  Future<void> set(String folder, ReadMode mode) => _save(<String, ReadMode>{
    for (final MapEntry<String, ReadMode> e
        in (state.value ?? const <String, ReadMode>{}).entries)
      if (e.key != folder) e.key: e.value,
    if (mode != ReadMode.photos) folder: mode,
  });

  /// Keeps modes on a folder renamed or moved from [from] to [to], and on
  /// the folders inside it. Both are [readingKey]s.
  Future<void> follow(String from, String to) async {
    final Map<String, ReadMode> now = state.value ?? const <String, ReadMode>{};
    String moved(String key) => key == from
        ? to
        : key.startsWith('$from/')
        ? '$to${key.substring(from.length)}'
        : key;
    final Map<String, ReadMode> next = <String, ReadMode>{
      for (final MapEntry<String, ReadMode> e in now.entries)
        moved(e.key): e.value,
    };
    if (!mapEquals(next, now)) await _save(next);
  }
}

final readModesProvider =
    AsyncNotifierProvider<ReadModesNotifier, Map<String, ReadMode>>(
      ReadModesNotifier.new,
    );

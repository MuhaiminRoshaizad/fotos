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

/// The key holding the mode last chosen for a folder inside [parent]: the
/// parent's key with a slash after it, which no folder's own key can be.
String _besideKey(String folder) {
  final int slash = folder.lastIndexOf('/');
  return '${slash < 0 ? '' : folder.substring(0, slash)}/';
}

/// The mode [folder] is read in: its own if it has one, else the one last
/// chosen for a folder beside it (the next comic in Comic/Album opens as
/// the last one was read), else Photos. Photos too for a mixed view such
/// as the Photos tab, which has no folder.
ReadMode readModeFor(Map<String, ReadMode>? modes, String? folder) {
  if (folder == null || modes == null) return ReadMode.photos;
  return modes[folder] ?? modes[_besideKey(folder)] ?? ReadMode.photos;
}

/// Folders' reading modes by [readingKey], and for each parent the mode
/// last chosen inside it.
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

  /// Sets [folder]'s mode, and makes it the one the folders beside it start
  /// in. The folder keeps it even as Photos, so a later choice beside it
  /// doesn't change a folder already set.
  Future<void> set(String folder, ReadMode mode) {
    final String beside = _besideKey(folder);
    return _save(<String, ReadMode>{
      for (final MapEntry<String, ReadMode> e
          in (state.value ?? const <String, ReadMode>{}).entries)
        if (e.key != folder && e.key != beside) e.key: e.value,
      folder: mode,
      if (mode != ReadMode.photos) beside: mode,
    });
  }

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

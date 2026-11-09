import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/storage/preferences.dart';

enum AlbumSortBy {
  taken('Date taken'),
  name('Name'),
  length('Length');

  const AlbumSortBy(this.label);
  final String label;

  /// Labels for the two directions, first being the default.
  (String, String) get directions => switch (this) {
    AlbumSortBy.taken => ('Newest first', 'Oldest first'),
    AlbumSortBy.name => ('A to Z', 'Z to A'),
    AlbumSortBy.length => ('Longest first', 'Shortest first'),
  };
}

class AlbumSort {
  const AlbumSort(this.by, {this.reversed = false});

  final AlbumSortBy by;

  /// False means the first of [AlbumSortBy.directions].
  final bool reversed;

  static const AlbumSort standard = AlbumSort(AlbumSortBy.taken);

  bool get groupsByDate => by == AlbumSortBy.taken;

  String encode() => '${by.name}:${reversed ? 1 : 0}';

  static AlbumSort decode(String s) {
    final List<String> p = s.split(':');
    final AlbumSortBy by = AlbumSortBy.values.firstWhere(
      (AlbumSortBy b) => b.name == p.first,
      orElse: () => AlbumSortBy.taken,
    );
    return AlbumSort(by, reversed: p.length > 1 && p[1] == '1');
  }

  /// [items] arrive newest first by date taken.
  List<AssetEntity> apply(List<AssetEntity> items) {
    final List<AssetEntity> out = List<AssetEntity>.of(items);
    switch (by) {
      case AlbumSortBy.taken:
        break;
      case AlbumSortBy.name:
        out.sort(
          (AssetEntity a, AssetEntity b) => (a.title ?? '')
              .toLowerCase()
              .compareTo((b.title ?? '').toLowerCase()),
        );
      case AlbumSortBy.length:
        out.sort(
          (AssetEntity a, AssetEntity b) => b.duration.compareTo(a.duration),
        );
    }
    return reversed ? out.reversed.toList() : out;
  }
}

/// Per-album choices fotos keeps itself, because Android has no notion of
/// them for folders: pins (in order), cover photo and sort.
class AlbumPrefs {
  const AlbumPrefs({
    this.pinned = const <String>[],
    this.covers = const <String, String>{},
    this.sorts = const <String, AlbumSort>{},
  });

  final List<String> pinned;
  final Map<String, String> covers;
  final Map<String, AlbumSort> sorts;

  AlbumSort sortFor(String albumId) => sorts[albumId] ?? AlbumSort.standard;
}

class AlbumPrefsNotifier extends AsyncNotifier<AlbumPrefs> {
  static const String _key = 'albums.prefs';

  @override
  Future<AlbumPrefs> build() async {
    final String? raw = await ref.watch(preferencesProvider).getString(_key);
    if (raw == null) return const AlbumPrefs();
    final Map<String, Object?> m = jsonDecode(raw) as Map<String, Object?>;
    return AlbumPrefs(
      pinned: (m['pinned'] as List<Object?>? ?? <Object?>[]).cast<String>(),
      covers: (m['covers'] as Map<String, Object?>? ?? <String, Object?>{})
          .cast<String, String>(),
      sorts: <String, AlbumSort>{
        for (final MapEntry<String, Object?> e
            in (m['sorts'] as Map<String, Object?>? ?? <String, Object?>{})
                .entries)
          e.key: AlbumSort.decode(e.value! as String),
      },
    );
  }

  Future<void> _save(AlbumPrefs p) async {
    state = AsyncData<AlbumPrefs>(p);
    await ref
        .read(preferencesProvider)
        .setString(
          _key,
          jsonEncode(<String, Object>{
            'pinned': p.pinned,
            'covers': p.covers,
            'sorts': <String, String>{
              for (final MapEntry<String, AlbumSort> e in p.sorts.entries)
                e.key: e.value.encode(),
            },
          }),
        );
  }

  AlbumPrefs get _now => state.value ?? const AlbumPrefs();

  Future<void> togglePin(String albumId) {
    final AlbumPrefs p = _now;
    final List<String> pinned = p.pinned.contains(albumId)
        ? (List<String>.of(p.pinned)..remove(albumId))
        : <String>[albumId, ...p.pinned];
    return _save(AlbumPrefs(pinned: pinned, covers: p.covers, sorts: p.sorts));
  }

  Future<void> setCover(String albumId, String assetId) {
    final AlbumPrefs p = _now;
    return _save(
      AlbumPrefs(
        pinned: p.pinned,
        covers: <String, String>{...p.covers, albumId: assetId},
        sorts: p.sorts,
      ),
    );
  }

  Future<void> setSort(String albumId, AlbumSort sort) {
    final AlbumPrefs p = _now;
    return _save(
      AlbumPrefs(
        pinned: p.pinned,
        covers: p.covers,
        sorts: <String, AlbumSort>{...p.sorts, albumId: sort},
      ),
    );
  }
}

final AsyncNotifierProvider<AlbumPrefsNotifier, AlbumPrefs> albumPrefsProvider =
    AsyncNotifierProvider<AlbumPrefsNotifier, AlbumPrefs>(
      AlbumPrefsNotifier.new,
    );

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/format/natural_sort.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/media/read_mode.dart';
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
          (AssetEntity a, AssetEntity b) =>
              naturalCompare(a.title ?? '', b.title ?? ''),
        );
      case AlbumSortBy.length:
        out.sort(
          (AssetEntity a, AssetEntity b) => b.duration.compareTo(a.duration),
        );
    }
    return reversed ? out.reversed.toList() : out;
  }
}

enum AlbumsOrderBy {
  recent('Most recent photo'),
  name('Name'),
  count('Number of items');

  const AlbumsOrderBy(this.label);
  final String label;

  /// Labels for the two directions, first being the default.
  (String, String) get directions => switch (this) {
    AlbumsOrderBy.recent => ('Newest first', 'Oldest first'),
    AlbumsOrderBy.name => ('A to Z', 'Z to A'),
    AlbumsOrderBy.count => ('Most first', 'Fewest first'),
  };
}

/// The order of the albums on the Albums tab. Pinned albums keep their own
/// order above these.
class AlbumsOrder {
  const AlbumsOrder(this.by, {this.reversed = false});

  final AlbumsOrderBy by;

  /// False means the first of [AlbumsOrderBy.directions].
  final bool reversed;

  static const AlbumsOrder standard = AlbumsOrder(AlbumsOrderBy.recent);

  String encode() => '${by.name}:${reversed ? 1 : 0}';

  static AlbumsOrder decode(String s) {
    final List<String> p = s.split(':');
    final AlbumsOrderBy by = AlbumsOrderBy.values.firstWhere(
      (AlbumsOrderBy b) => b.name == p.first,
      orElse: () => AlbumsOrderBy.recent,
    );
    return AlbumsOrder(by, reversed: p.length > 1 && p[1] == '1');
  }

  List<Album> apply(List<Album> albums) {
    // An album's newest item is the one the repository hands over as its
    // cover; an album without one sorts as the oldest.
    int taken(Album a) => a.cover?.createDateTime.millisecondsSinceEpoch ?? 0;
    int byName(Album a, Album b) => naturalCompare(a.name, b.name);
    final List<Album> out = List<Album>.of(albums);
    switch (by) {
      case AlbumsOrderBy.recent:
        out.sort((Album a, Album b) {
          final int c = taken(b).compareTo(taken(a));
          return c != 0 ? c : byName(a, b);
        });
      case AlbumsOrderBy.name:
        out.sort(byName);
      case AlbumsOrderBy.count:
        out.sort((Album a, Album b) {
          final int c = b.count.compareTo(a.count);
          return c != 0 ? c : byName(a, b);
        });
    }
    return reversed ? out.reversed.toList() : out;
  }
}

/// Choices fotos keeps itself, because Android has no notion of them for
/// folders: pins (in order), each album's cover photo and sort, and the
/// order of the albums themselves.
class AlbumPrefs {
  const AlbumPrefs({
    this.pinned = const <String>[],
    this.covers = const <String, String>{},
    this.sorts = const <String, AlbumSort>{},
    this.defaultSort = AlbumSort.standard,
    this.reading = const <String, ReadMode>{},
    this.order = AlbumsOrder.standard,
  });

  final List<String> pinned;
  final Map<String, String> covers;
  final Map<String, AlbumSort> sorts;

  /// The sort of every album not given its own, new albums included.
  final AlbumSort defaultSort;

  /// How each album is read, for those not read as photos.
  final Map<String, ReadMode> reading;
  final AlbumsOrder order;

  AlbumPrefs copyWith({
    List<String>? pinned,
    Map<String, String>? covers,
    Map<String, AlbumSort>? sorts,
    AlbumSort? defaultSort,
    Map<String, ReadMode>? reading,
    AlbumsOrder? order,
  }) => AlbumPrefs(
    pinned: pinned ?? this.pinned,
    covers: covers ?? this.covers,
    sorts: sorts ?? this.sorts,
    defaultSort: defaultSort ?? this.defaultSort,
    reading: reading ?? this.reading,
    order: order ?? this.order,
  );

  ReadMode readingFor(String albumId) => reading[albumId] ?? ReadMode.photos;

  AlbumSort sortFor(String albumId) => sorts[albumId] ?? defaultSort;
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
      reading: <String, ReadMode>{
        for (final MapEntry<String, Object?> e
            in (m['reading'] as Map<String, Object?>? ?? <String, Object?>{})
                .entries)
          e.key: ReadMode.decode(e.value! as String),
      },
      defaultSort: m['defaultSort'] == null
          ? AlbumSort.standard
          : AlbumSort.decode(m['defaultSort']! as String),
      order: m['order'] == null
          ? AlbumsOrder.standard
          : AlbumsOrder.decode(m['order']! as String),
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
            'defaultSort': p.defaultSort.encode(),
            'reading': <String, String>{
              for (final MapEntry<String, ReadMode> e in p.reading.entries)
                e.key: e.value.name,
            },
            'order': p.order.encode(),
          }),
        );
  }

  AlbumPrefs get _now => state.value ?? const AlbumPrefs();

  Future<void> togglePin(String albumId) {
    final AlbumPrefs p = _now;
    final List<String> pinned = p.pinned.contains(albumId)
        ? (List<String>.of(p.pinned)..remove(albumId))
        : <String>[albumId, ...p.pinned];
    return _save(p.copyWith(pinned: pinned));
  }

  Future<void> setCover(String albumId, String assetId) {
    final AlbumPrefs p = _now;
    return _save(
      p.copyWith(covers: <String, String>{...p.covers, albumId: assetId}),
    );
  }

  Future<void> setSort(String albumId, AlbumSort sort) {
    final AlbumPrefs p = _now;
    return _save(
      p.copyWith(sorts: <String, AlbumSort>{...p.sorts, albumId: sort}),
    );
  }

  /// Moves [from]'s pin, cover and sort to [to], for an album whose folder
  /// was renamed and so has a new id.
  Future<void> rekey(String from, String to) {
    final AlbumPrefs p = _now;
    String swap(String id) => id == from ? to : id;
    return _save(
      p.copyWith(
        pinned: <String>[for (final String id in p.pinned) swap(id)],
        covers: <String, String>{
          for (final MapEntry<String, String> e in p.covers.entries)
            swap(e.key): e.value,
        },
        sorts: <String, AlbumSort>{
          for (final MapEntry<String, AlbumSort> e in p.sorts.entries)
            swap(e.key): e.value,
        },
        reading: <String, ReadMode>{
          for (final MapEntry<String, ReadMode> e in p.reading.entries)
            swap(e.key): e.value,
        },
      ),
    );
  }

  /// Makes [sort] the default and lets [albumId] follow it, dropping the
  /// album's own sort.
  Future<void> setSortForAll(String albumId, AlbumSort sort) {
    final AlbumPrefs p = _now;
    return _save(
      p.copyWith(
        defaultSort: sort,
        sorts: <String, AlbumSort>{
          for (final MapEntry<String, AlbumSort> e in p.sorts.entries)
            if (e.key != albumId) e.key: e.value,
        },
      ),
    );
  }

  Future<void> setReading(String albumId, ReadMode mode) {
    final AlbumPrefs p = _now;
    return _save(
      p.copyWith(
        reading: <String, ReadMode>{
          for (final MapEntry<String, ReadMode> e in p.reading.entries)
            if (e.key != albumId) e.key: e.value,
          if (mode != ReadMode.photos) albumId: mode,
        },
      ),
    );
  }

  Future<void> setOrder(AlbumsOrder order) =>
      _save(_now.copyWith(order: order));
}

final AsyncNotifierProvider<AlbumPrefsNotifier, AlbumPrefs> albumPrefsProvider =
    AsyncNotifierProvider<AlbumPrefsNotifier, AlbumPrefs>(
      AlbumPrefsNotifier.new,
    );

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/preferences.dart';
import 'album_prefs.dart';

/// Gallery ids share the pinned list with album ids, which are numbers, so
/// they carry this prefix.
const String galleryIdPrefix = 'gallery:';

/// An album of albums. It exists only in fotos: the folders on the phone stay
/// where they are, so other apps see no change.
class Gallery {
  const Gallery({
    required this.id,
    required this.name,
    this.albumIds = const <String>[],
    this.order = AlbumsOrder.standard,
  });

  final String id;
  final String name;
  final List<String> albumIds;

  /// How the albums inside are ordered.
  final AlbumsOrder order;

  Gallery copyWith({
    String? name,
    List<String>? albumIds,
    AlbumsOrder? order,
  }) => Gallery(
    id: id,
    name: name ?? this.name,
    albumIds: albumIds ?? this.albumIds,
    order: order ?? this.order,
  );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'albums': albumIds,
    'order': order.encode(),
  };

  static Gallery fromJson(Map<String, Object?> m) => Gallery(
    id: m['id']! as String,
    name: m['name']! as String,
    albumIds: (m['albums'] as List<Object?>? ?? const <Object?>[])
        .cast<String>(),
    order: m['order'] == null
        ? AlbumsOrder.standard
        : AlbumsOrder.decode(m['order']! as String),
  );
}

/// The gallery [albumId] is in, if any. An album is in one gallery at most.
Gallery? galleryOf(List<Gallery> galleries, String albumId) {
  for (final Gallery g in galleries) {
    if (g.albumIds.contains(albumId)) return g;
  }
  return null;
}

/// The user's galleries, kept in preferences in the order they were made.
class GalleriesNotifier extends AsyncNotifier<List<Gallery>> {
  static const String _key = 'albums.galleries';

  @override
  Future<List<Gallery>> build() async {
    final String? raw = await ref.watch(preferencesProvider).getString(_key);
    if (raw == null) return const <Gallery>[];
    return <Gallery>[
      for (final Object? g in jsonDecode(raw) as List<Object?>)
        Gallery.fromJson(g! as Map<String, Object?>),
    ];
  }

  List<Gallery> get _now => state.value ?? const <Gallery>[];

  Future<void> _save(List<Gallery> next) async {
    state = AsyncData<List<Gallery>>(next);
    await ref
        .read(preferencesProvider)
        .setString(
          _key,
          jsonEncode(<Object>[for (final Gallery g in next) g.toJson()]),
        );
  }

  /// [galleries] with [albumIds] taken out of every one of them.
  List<Gallery> _without(List<Gallery> galleries, List<String> albumIds) =>
      <Gallery>[
        for (final Gallery g in galleries)
          g.copyWith(
            albumIds: <String>[
              for (final String id in g.albumIds)
                if (!albumIds.contains(id)) id,
            ],
          ),
      ];

  /// Makes a gallery holding [albumIds], taking them out of any other one.
  /// Returns its id.
  Future<String> create(String name, List<String> albumIds) async {
    // The clock can read the same twice in quick succession, so step past
    // an id already in use.
    int n = DateTime.now().microsecondsSinceEpoch;
    while (_now.any((Gallery g) => g.id == '$galleryIdPrefix$n')) {
      n++;
    }
    final String id = '$galleryIdPrefix$n';
    await _save(<Gallery>[
      ..._without(_now, albumIds),
      Gallery(id: id, name: name, albumIds: albumIds),
    ]);
    return id;
  }

  /// Puts [albumIds] into gallery [id], taking them out of any other one.
  Future<void> add(String id, List<String> albumIds) => _save(<Gallery>[
    for (final Gallery g in _without(_now, albumIds))
      g.id == id
          ? g.copyWith(albumIds: <String>[...g.albumIds, ...albumIds])
          : g,
  ]);

  /// Takes [albumId] out of whichever gallery holds it.
  Future<void> remove(String albumId) =>
      _save(_without(_now, <String>[albumId]));

  Future<void> rename(String id, String name) => _save(<Gallery>[
    for (final Gallery g in _now) g.id == id ? g.copyWith(name: name) : g,
  ]);

  Future<void> setOrder(String id, AlbumsOrder order) => _save(<Gallery>[
    for (final Gallery g in _now) g.id == id ? g.copyWith(order: order) : g,
  ]);

  /// Removes the gallery; its albums go back to the Albums tab.
  Future<void> delete(String id) => _save(<Gallery>[
    for (final Gallery g in _now)
      if (g.id != id) g,
  ]);

  /// Follows an album whose folder was renamed and so has a new id.
  Future<void> rekey(String from, String to) => _save(<Gallery>[
    for (final Gallery g in _now)
      g.copyWith(
        albumIds: <String>[
          for (final String id in g.albumIds) id == from ? to : id,
        ],
      ),
  ]);
}

final AsyncNotifierProvider<GalleriesNotifier, List<Gallery>>
galleriesProvider = AsyncNotifierProvider<GalleriesNotifier, List<Gallery>>(
  GalleriesNotifier.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences.dart';

/// Albums created with nothing in them yet. Android lists a folder as an
/// album only once it holds a photo or video, so fotos remembers these names
/// itself until the first item moves in.
class EmptyAlbumsNotifier extends AsyncNotifier<List<String>> {
  static const String _key = 'albums.empty';

  @override
  Future<List<String>> build() async =>
      await ref.watch(preferencesProvider).getStringList(_key) ?? <String>[];

  Future<void> _save(List<String> names) async {
    state = AsyncData<List<String>>(names);
    await ref.read(preferencesProvider).setStringList(_key, names);
  }

  List<String> get _now => state.value ?? <String>[];

  Future<void> add(String name) => _save(<String>[name, ..._now]);

  Future<void> remove(String name) => _save(
    _now.where((String n) => n.toLowerCase() != name.toLowerCase()).toList(),
  );
}

final emptyAlbumsProvider =
    AsyncNotifierProvider<EmptyAlbumsNotifier, List<String>>(
      EmptyAlbumsNotifier.new,
    );

/// Where an album's files live; new albums go under Pictures.
String albumFolder(String name) => 'Pictures/$name/';

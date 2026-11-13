import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/native_channel.dart';
import '../data/album_prefs.dart';
import '../data/galleries.dart';
import 'albums_providers.dart';

/// Moves what is kept per album, its pin, cover, sort, place in a gallery
/// and home screen widgets, from each old id in [moved] to its new one.
/// An album's id changes whenever its folder is renamed or moved.
Future<void> followAlbums(
  ProviderContainer providers,
  Map<String, String> moved,
) async {
  if (moved.isEmpty) return;
  await providers.read(albumPrefsProvider.notifier).rekey(moved);
  await providers.read(galleriesProvider.notifier).rekey(moved);
  final NativeChannel native = providers.read(nativeChannelProvider);
  for (final MapEntry<String, String> e in moved.entries) {
    await native.rekeyWidgetAlbum(e.key, e.value);
  }
}

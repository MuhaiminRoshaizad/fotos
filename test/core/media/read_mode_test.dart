import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/media/read_mode.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late ProviderContainer c;
  ReadMode mode(String folder) =>
      readModeFor(c.read(readModesProvider).value, folder);

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(readModesProvider.future);
  });

  test('the next comic beside one read as a strip opens as a strip', () async {
    await c
        .read(readModesProvider.notifier)
        .set('Comic/Album/Iron Orchard', ReadMode.strip);
    expect(mode('Comic/Album/Night Ferry'), ReadMode.strip);
    // Folders elsewhere are untouched.
    expect(mode('DCIM/Camera'), ReadMode.photos);
    expect(mode('Comic/Album/Night Ferry/Extras'), ReadMode.photos);
  });

  test(
    'a comic set on its own keeps its mode when another is changed',
    () async {
      final ReadModesNotifier modes = c.read(readModesProvider.notifier);
      await modes.set('Comic/Album/Iron Orchard', ReadMode.strip);
      await modes.set('Comic/Album/Night Ferry', ReadMode.photos);
      // Night Ferry was set to Photos itself; that is now what comics beside
      // it start in, and Iron Orchard keeps its strip.
      expect(mode('Comic/Album/Night Ferry'), ReadMode.photos);
      expect(mode('Comic/Album/Iron Orchard'), ReadMode.strip);
      expect(mode('Comic/Album/Blame'), ReadMode.photos);
      await modes.set('Comic/Album/Blame', ReadMode.pages);
      expect(mode('Comic/Album/Akira'), ReadMode.pages);
      expect(mode('Comic/Album/Night Ferry'), ReadMode.photos);
    },
  );

  test('a renamed parent carries the mode its comics start in', () async {
    final ReadModesNotifier modes = c.read(readModesProvider.notifier);
    await modes.set('Comic/Album/Iron Orchard', ReadMode.strip);
    await modes.follow('Comic/Album', 'Comic/Read');
    expect(mode('Comic/Read/Night Ferry'), ReadMode.strip);
    expect(mode('Comic/Read/Iron Orchard'), ReadMode.strip);
    expect(mode('Comic/Album/Night Ferry'), ReadMode.photos);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  _followTests();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('pinning puts the newest first, and pinning again unpins', () async {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(topPinsProvider.future), isEmpty);

    final TopPinsNotifier pins = c.read(topPinsProvider.notifier);
    await pins.toggle('/root/Download');
    await pins.toggle('/root/Download/Comics');
    expect(c.read(topPinsProvider).value, <String>[
      '/root/Download/Comics',
      '/root/Download',
    ]);

    await pins.toggle('/root/Download');
    expect(c.read(topPinsProvider).value, <String>['/root/Download/Comics']);
  });

  test('pins are still there the next time the app starts', () async {
    final ProviderContainer first = ProviderContainer();
    await first.read(topPinsProvider.future);
    await first.read(topPinsProvider.notifier).toggle('/root/Comics');
    first.dispose();

    final ProviderContainer second = ProviderContainer();
    addTearDown(second.dispose);
    expect(await second.read(topPinsProvider.future), <String>['/root/Comics']);
  });
}

void _followTests() {
  test('a pin follows its item through a rename or move, and so do pins '
      'inside a renamed folder', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(topPinsProvider.future);
    final TopPinsNotifier pins = c.read(topPinsProvider.notifier);
    await pins.toggle('/root/Comic/Album/Moonlit Harbor');
    await pins.toggle('/root/Comic/Album');
    await pins.toggle('/root/Comic/Albums of 2025');

    await pins.follow(
      '/root/Comic/Album/Moonlit Harbor',
      '/root/Comic/Album/Moonlit Harbor Vol. 03',
    );
    await pins.follow('/root/Comic/Album', '/root/Comic/Read');

    expect(c.read(topPinsProvider).value, <String>[
      // A folder that only starts with the same name is left alone.
      '/root/Comic/Albums of 2025',
      '/root/Comic/Read',
      '/root/Comic/Read/Moonlit Harbor Vol. 03',
    ]);
  });
}

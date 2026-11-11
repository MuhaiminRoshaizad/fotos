import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/files/presentation/files_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('pinning puts the newest first, and pinning again unpins', () async {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(pinnedProvider.future), isEmpty);

    final PinnedNotifier pins = c.read(pinnedProvider.notifier);
    await pins.toggle('/root/Download');
    await pins.toggle('/root/Download/Comics');
    expect(c.read(pinnedProvider).value, <String>[
      '/root/Download/Comics',
      '/root/Download',
    ]);

    await pins.toggle('/root/Download');
    expect(c.read(pinnedProvider).value, <String>['/root/Download/Comics']);
  });

  test('pins are still there the next time the app starts', () async {
    final ProviderContainer first = ProviderContainer();
    await first.read(pinnedProvider.future);
    await first.read(pinnedProvider.notifier).toggle('/root/Comics');
    first.dispose();

    final ProviderContainer second = ProviderContainer();
    addTearDown(second.dispose);
    expect(await second.read(pinnedProvider.future), <String>['/root/Comics']);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/preferences.dart';

class ViewerSettings {
  const ViewerSettings({this.loop = false, this.muted = false});
  final bool loop;
  final bool muted;
}

/// Video loop and mute, remembered between sessions.
class ViewerSettingsNotifier extends AsyncNotifier<ViewerSettings> {
  static const String _loopKey = 'viewer.loop';
  static const String _mutedKey = 'viewer.muted';

  @override
  Future<ViewerSettings> build() async {
    final prefs = ref.watch(preferencesProvider);
    return ViewerSettings(
      loop: await prefs.getBool(_loopKey) ?? false,
      muted: await prefs.getBool(_mutedKey) ?? false,
    );
  }

  Future<void> setLoop(bool v) async {
    final ViewerSettings now = state.value ?? const ViewerSettings();
    state = AsyncData<ViewerSettings>(
      ViewerSettings(loop: v, muted: now.muted),
    );
    await ref.read(preferencesProvider).setBool(_loopKey, v);
  }

  Future<void> setMuted(bool v) async {
    final ViewerSettings now = state.value ?? const ViewerSettings();
    state = AsyncData<ViewerSettings>(ViewerSettings(loop: now.loop, muted: v));
    await ref.read(preferencesProvider).setBool(_mutedKey, v);
  }
}

final AsyncNotifierProvider<ViewerSettingsNotifier, ViewerSettings>
viewerSettingsProvider =
    AsyncNotifierProvider<ViewerSettingsNotifier, ViewerSettings>(
      ViewerSettingsNotifier.new,
    );

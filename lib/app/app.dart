import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/stable_insets.dart';
import '../core/widgets/tap_outside_closes_keyboard.dart';
import '../features/video_editor/presentation/save_end_listener.dart';
import '../features/video_editor/presentation/save_stop_listener.dart';
import '../features/viewer/presentation/view_intent_handler.dart';
import 'handle_every_back.dart';
import 'router.dart';
import 'splash_pluck.dart';

class FotosApp extends ConsumerWidget {
  const FotosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'fotos',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      onNavigationNotification: handleEveryBack,
      builder: (BuildContext context, Widget? child) => HandleEveryBack(
        child: StableInsets(
          child: SplashPluck(
            child: ViewIntentHandler(
              child: SaveEndListener(
                child: SaveStopListener(
                  child: TapOutsideClosesKeyboard(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

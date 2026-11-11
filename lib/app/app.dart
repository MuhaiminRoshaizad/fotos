import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/stable_insets.dart';
import '../core/widgets/tap_outside_closes_keyboard.dart';
import '../features/viewer/presentation/view_intent_handler.dart';
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
      builder: (BuildContext context, Widget? child) => StableInsets(
        child: SplashPluck(
          child: ViewIntentHandler(
            child: TapOutsideClosesKeyboard(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

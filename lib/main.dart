import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/tab_order.dart';
import 'features/home_widget/presentation/widget_setup_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status and navigation bars; screens handle the insets.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  // Android opens the photo widget's setup on its own route, from its own
  // activity; that is the setup screen alone, not the app.
  final bool widgetSetup = PlatformDispatcher.instance.defaultRouteName
      .startsWith(widgetSetupRoute);
  // fotos opens on the first tab of the saved order; reading it first keeps
  // Photos from showing for a moment before it.
  final List<int> tabs = widgetSetup
      ? defaultTabOrder
      : await TabOrderNotifier.load(SharedPreferencesAsync());
  runApp(
    ProviderScope(
      overrides: [initialTabOrderProvider.overrideWithValue(tabs)],
      child: widgetSetup ? const WidgetSetupApp() : const FotosApp(),
    ),
  );
}

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/home_widget/presentation/widget_setup_app.dart';

void main() {
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
  runApp(
    ProviderScope(
      child: widgetSetup ? const WidgetSetupApp() : const FotosApp(),
    ),
  );
}

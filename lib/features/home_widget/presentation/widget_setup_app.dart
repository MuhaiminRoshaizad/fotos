import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/widget_config.dart';
import 'widget_setup_screen.dart';

/// The route Android's widget setup activity starts fotos on.
const String widgetSetupRoute = '/widget-setup/';

/// fotos as the photo widget's setup screen: started by
/// WidgetSetupActivity on its own, without the tabs or the launch flower.
/// Leaving by the back gesture closes the activity, which places no widget.
class WidgetSetupApp extends StatefulWidget {
  const WidgetSetupApp({super.key});

  @override
  State<WidgetSetupApp> createState() => _WidgetSetupAppState();
}

class _WidgetSetupAppState extends State<WidgetSetupApp> {
  static const MethodChannel _channel = MethodChannel('my.minned.fotos/widget');

  /// The widget's saved settings, or null for a new one.
  late final Future<Map<Object?, Object?>?> _saved = _channel
      .invokeMapMethod<Object?, Object?>('load');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fotos',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: FutureBuilder<Map<Object?, Object?>?>(
        future: _saved,
        builder:
            (BuildContext context, AsyncSnapshot<Map<Object?, Object?>?> s) =>
                s.connectionState != ConnectionState.done
                ? const Scaffold(body: SizedBox.shrink())
                : WidgetSetupScreen(
                    initial: s.data == null
                        ? null
                        : WidgetConfig.fromMap(s.data!),
                    onDone: (WidgetConfig c) =>
                        _channel.invokeMethod<void>('save', c.toMap()),
                    onCancel: () => _channel.invokeMethod<void>('cancel'),
                  ),
      ),
    );
  }
}

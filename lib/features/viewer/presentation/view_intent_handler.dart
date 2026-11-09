import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../app/router.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/widgets/toast.dart';
import '../../albums/presentation/albums_providers.dart';
import 'viewer_screen.dart';

/// The MediaStore id in a content://media/... address, if it is one.
String? mediaStoreId(String uri) {
  final Uri? u = Uri.tryParse(uri);
  if (u == null || u.scheme != 'content' || u.host != 'media') return null;
  final String last = u.pathSegments.isEmpty ? '' : u.pathSegments.last;
  return int.tryParse(last) == null ? null : last;
}

/// Opens the viewer when fotos is started (or brought back) to show one
/// photo or video: the camera's thumbnail, or another app's "View".
class ViewIntentHandler extends ConsumerStatefulWidget {
  const ViewIntentHandler({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ViewIntentHandler> createState() => _ViewIntentHandlerState();
}

class _ViewIntentHandlerState extends ConsumerState<ViewIntentHandler> {
  StreamSubscription<Object?>? _sub;

  @override
  void initState() {
    super.initState();
    final native = ref.read(nativeChannelProvider);
    _sub = native.events('openUri').listen((Object? uri) {
      if (uri is String) _open(uri);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final String? uri = await native.invoke<String>('launchUri');
        if (uri != null) await _open(uri);
      } on PlatformException {
        // Opened normally, from the launcher: nothing to show.
      } on MissingPluginException {
        // Widget tests run without the Android side.
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _open(String uri) async {
    final String? id = mediaStoreId(uri);
    final BuildContext? ctx = rootNavigatorKey.currentContext;
    if (id == null) {
      if (ctx != null && ctx.mounted) {
        showToast(
          ctx,
          'fotos opens photos and videos from this phone\'s library only.',
        );
      }
      return;
    }
    if (await ref.read(mediaAccessProvider.future) == MediaAccess.denied) {
      await ref.read(mediaAccessProvider.notifier).request();
    }
    final AssetEntity? asset = await AssetEntity.fromId(id);
    if (asset == null) {
      if (ctx != null && ctx.mounted) {
        showToast(
          ctx,
          'That item isn\'t available. Allow photo access and try again.',
        );
      }
      return;
    }
    // Page through the rest of the library from there, as the camera's
    // own gallery does.
    final List<AssetEntity> all = await ref.read(
      libraryProvider(MediaKind.all).future,
    );
    final int i = all.indexWhere((AssetEntity e) => e.id == id);
    ref
        .read(routerProvider)
        .push(
          '/viewer',
          extra: ViewerArgs(
            items: i < 0 ? <AssetEntity>[asset] : all,
            index: i < 0 ? 0 : i,
            heroPrefix: 'intent',
          ),
        );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

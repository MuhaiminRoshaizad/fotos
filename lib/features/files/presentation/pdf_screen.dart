import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../albums/presentation/albums_providers.dart';

final _pageCountProvider = FutureProvider.autoDispose.family<int, String>(
  (Ref ref, String path) => ref.read(nativeChannelProvider).pdfPageCount(path),
);

final _pageProvider = FutureProvider.autoDispose
    .family<Uint8List, (String, int, int)>(
      (Ref ref, (String, int, int) key) =>
          ref.read(nativeChannelProvider).pdfPage(key.$1, key.$2, key.$3),
    );

/// Reads a PDF page by page with Android's own renderer. Tap a page to zoom.
class PdfScreen extends ConsumerStatefulWidget {
  const PdfScreen({super.key, required this.path});
  final String path;

  @override
  ConsumerState<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends ConsumerState<PdfScreen> {
  final ValueNotifier<int> _page = ValueNotifier<int>(1);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<int> count = ref.watch(_pageCountProvider(widget.path));
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          p.basename(widget.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Share',
            onPressed: () => SharePlus.instance.share(
              ShareParams(files: <XFile>[XFile(widget.path)]),
            ),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: count.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const EmptyState(
          icon: Icons.picture_as_pdf_outlined,
          title: 'This PDF can\'t be opened',
          message: 'It may be damaged or protected with a password.',
        ),
        data: (int pages) => LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double pageWidth = c.maxWidth - AppSpacing.lg * 2;
            final int px = (pageWidth * MediaQuery.devicePixelRatioOf(context))
                .round();
            return Stack(
              children: <Widget>[
                NotificationListener<ScrollUpdateNotification>(
                  onNotification: (ScrollUpdateNotification n) {
                    // Pages are A4-ish; this is precise enough for a counter.
                    final double pageExtent = pageWidth * 1.414 + AppSpacing.md;
                    _page.value = (n.metrics.pixels / pageExtent + 1.5)
                        .floor()
                        .clamp(1, pages);
                    return false;
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppNavMetrics.clearance(
                        MediaQuery.paddingOf(context).bottom,
                      ),
                    ),
                    itemCount: pages,
                    itemBuilder: (BuildContext context, int i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _Page(
                        path: widget.path,
                        index: i,
                        px: px,
                        width: pageWidth,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom:
                      AppNavMetrics.clearance(
                        MediaQuery.paddingOf(context).bottom,
                      ) -
                      AppSpacing.xl,
                  child: Center(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _page,
                      builder: (_, int v, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.inverseSurface,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            '$v / $pages',
                            style: TextStyle(
                              color: cs.onInverseSurface,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Page extends ConsumerWidget {
  const _Page({
    required this.path,
    required this.index,
    required this.px,
    required this.width,
  });
  final String path;
  final int index;
  final int px;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Uint8List> page = ref.watch(
      _pageProvider((path, index, px)),
    );
    return Semantics(
      label: 'Page ${index + 1}',
      image: true,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: <BoxShadow>[
            BoxShadow(blurRadius: 3, color: Color(0x33000000)),
          ],
        ),
        child: page.when(
          loading: () => SizedBox(width: width, height: width * 1.414),
          error: (_, _) => SizedBox(
            width: width,
            height: width * 1.414,
            child: const Center(child: Text('This page can\'t be shown.')),
          ),
          data: (Uint8List bytes) => GestureDetector(
            // Tap a page to read it zoomed; pinch and pan there.
            onTap: () => showDialog<void>(
              context: context,
              useRootNavigator: true,
              builder: (BuildContext ctx) => Dialog.fullscreen(
                backgroundColor: Colors.black,
                child: Stack(
                  children: <Widget>[
                    InteractiveViewer(
                      maxScale: 6,
                      child: Center(
                        child: Image.memory(bytes, gaplessPlayback: true),
                      ),
                    ),
                    SafeArea(
                      child: IconButton(
                        tooltip: 'Close',
                        color: Colors.white,
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child: Image.memory(
              bytes,
              width: width,
              fit: BoxFit.fitWidth,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

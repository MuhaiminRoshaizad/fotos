import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart'
    show CupertinoButton, CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/viewer_glass.dart';
import '../../albums/presentation/albums_providers.dart';
import '../../../core/widgets/bottom_bar_space.dart';

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
    return LargeTitleScaffold(
      title: p.basename(widget.path),
      leading: BackBarButton(label: p.basename(p.dirname(widget.path))),
      trailing: <Widget>[
        BarButton.icon(
          icon: CupertinoIcons.square_arrow_up,
          tooltip: 'Share',
          onPressed: () => SharePlus.instance.share(
            ShareParams(files: <XFile>[XFile(widget.path)]),
          ),
        ),
      ],
      body: (BuildContext context, Widget header) => count.when(
        loading: () => header,
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            const Expanded(
              child: EmptyState(
                icon: CupertinoIcons.doc_richtext,
                title: 'This PDF can\'t be opened',
                message: 'It may be damaged or protected with a password.',
              ),
            ),
          ],
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
                    padding: EdgeInsets.only(bottom: bottomClearance(context)),
                    // The title first, then the pages.
                    itemCount: pages + 1,
                    itemBuilder: (BuildContext context, int i) => i == 0
                        ? header
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.md,
                            ),
                            child: _Page(
                              path: widget.path,
                              index: i - 1,
                              px: px,
                              width: pageWidth,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: math.max(
                    bottomClearance(context) - AppSpacing.xl,
                    MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
                  ),
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
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => _PageZoom(bytes: bytes),
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

/// One page full screen on black, to pinch and pan, closed with the same
/// glass button as the viewer.
class _PageZoom extends StatelessWidget {
  const _PageZoom({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.memory(bytes, gaplessPlayback: true)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: ViewerGlass(
                shape: const CircleBorder(),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    color: Colors.white,
                    semanticLabel: 'Close',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

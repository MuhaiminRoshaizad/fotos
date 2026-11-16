import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/widgets/zoom_view.dart';
import 'package:fotos/features/viewer/presentation/viewer_screen.dart';

/// The viewer's gesture stack around a video, without the video: the
/// swipe-down page, the page view with the viewer's own drag rule, and each
/// page's swipe-down handler around a ZoomView (viewer_screen.dart,
/// video_page.dart).
class _Viewer extends StatefulWidget {
  const _Viewer();

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  final GlobalKey<ExtendedImageSlidePageState> _slide =
      GlobalKey<ExtendedImageSlidePageState>();
  final ExtendedPageController pages = ExtendedPageController();
  bool zoomed = false;

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExtendedImageSlidePage(
    key: _slide,
    slideAxis: SlideAxis.both,
    slideType: SlideType.onlyImage,
    child: ExtendedImageGesturePageView.builder(
      controller: pages,
      itemCount: 3,
      canScrollPage: (_) => !zoomed,
      shouldAccpetHorizontalOrVerticalDrag:
          (Map<int, VelocityTracker> fingers) =>
              pageMayTakeDrag(fingers.length, videoZoomed: zoomed),
      itemBuilder: (BuildContext context, int i) =>
          ExtendedImageSlidePageHandler(
            extendedImageSlidePageState: _slide.currentState,
            child: ZoomView(
              onZoomed: (bool z) => setState(() => zoomed = z),
              child: SizedBox.expand(
                child: ColoredBox(
                  color: Colors.teal,
                  child: Center(child: Text('video $i')),
                ),
              ),
            ),
          ),
    ),
  );
}

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: _Viewer()));
    await tester.pumpAndSettle();
    // Zoom in, as a pinch would.
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
  }

  Offset at(WidgetTester tester) {
    final Matrix4 m = tester
        .state<ZoomViewState>(find.byType(ZoomView).first)
        .transform;
    return Offset(m.storage[12], m.storage[13]);
  }

  /// One finger moved in small steps, as a hand moves it.
  Future<void> drag(WidgetTester tester, Offset step) async {
    final TestGesture g = await tester.startGesture(const Offset(200, 400));
    for (int i = 0; i < 10; i++) {
      await g.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  for (final (String way, Offset step) in <(String, Offset)>[
    ('sideways', const Offset(-15, 0)),
    ('up', const Offset(0, -15)),
    ('down', const Offset(0, 15)),
    ('diagonally', const Offset(-12, -12)),
  ]) {
    testWidgets('a zoomed-in video pans $way under one finger', (
      WidgetTester tester,
    ) async {
      await open(tester);
      final _ViewerState v = tester.state<_ViewerState>(find.byType(_Viewer));
      expect(v.zoomed, isTrue);
      final Offset before = at(tester);
      await drag(tester, step);
      final Offset after = at(tester);
      expect(
        (after - before).distance,
        greaterThan(60),
        reason: 'moved from $before to $after',
      );
      expect(v.pages.page, 0);
    });
  }

  testWidgets('at normal size a swipe still turns to the next video', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: _Viewer()));
    await tester.pumpAndSettle();
    await tester.fling(find.text('video 0'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(tester.state<_ViewerState>(find.byType(_Viewer)).pages.page, 1);
  });
}

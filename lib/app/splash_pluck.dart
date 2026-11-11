import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/albums/presentation/albums_providers.dart';

/// The second half of the launch: fotos' flower, plucked apart over the
/// app's first page.
///
/// Android draws the launch screen itself, with the petals pulled in to the
/// centre (res/drawable/splash_flower.xml). This widget draws the same
/// flower, at the same size and place, over the app from Flutter's first
/// frame. When Android's screen goes there is no visible change, and then
/// each petal is tugged and pulled away along its own direction while the
/// page behind fades up.
///
/// The petal shape, colours and size here match tool/gen_icon.py, which
/// writes the Android side.
class SplashPluck extends ConsumerStatefulWidget {
  const SplashPluck({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SplashPluck> createState() => _SplashPluckState();
}

class _SplashPluckState extends ConsumerState<SplashPluck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _handOver());
  }

  /// Covers a launch where Android never answers. Held here, not as a
  /// timeout on the call, so that disposing the widget cancels it.
  Timer? _limit;
  bool _started = false;

  void _handOver() {
    _limit = Timer(const Duration(milliseconds: 2500), _pluck);
    // Android answers once its pull-in has finished and its screen is down.
    ref
        .read(nativeChannelProvider)
        .awaitSplash()
        .then(
          (_) => _pluck(),
          onError: (Object e) {
            if (e is MissingPluginException) {
              // Widget tests have no Android side and no launch screen.
              _limit?.cancel();
              if (mounted) setState(() => _done = true);
            } else {
              // Carry on: the flower is on screen and should not stay there.
              _pluck();
            }
          },
        );
  }

  void _pluck() {
    _limit?.cancel();
    if (_started || !mounted) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _done = true);
    } else {
      unawaited(_c.forward());
    }
  }

  @override
  void dispose() {
    _limit?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    // The app keeps its place in the tree when the flower goes. Returning
    // the child on its own instead would rebuild the whole app beneath, and
    // a photo opened from another app during launch lost which photo it was.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (!_done)
          IgnorePointer(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _FlowerPainter(
                  progress: _c,
                  background: cs.surface,
                  core: cs.onSurface,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FlowerPainter extends CustomPainter {
  _FlowerPainter({
    required this.progress,
    required this.background,
    required this.core,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color background;
  final Color core;

  static const List<Color> _colors = <Color>[
    Color(0xFFFF5F6D),
    Color(0xFFFFB347),
    Color(0xFFFFE66D),
    Color(0xFF4FD1A5),
    Color(0xFF5B9BFF),
    Color(0xFFB388FF),
  ];

  /// The petal reaches 132 path units from the centre and is drawn 84
  /// logical pixels long, as on Android's launch screen.
  static const double _scale = 84 / 132;

  /// "M0,-10 C16,-30 42,-62 42,-90 A42,42 0 0 0 -42,-90 C-42,-62 -16,-30
  /// 0,-10 Z": a rounded teardrop pointing up from the centre.
  static final Path _petal = Path()
    ..moveTo(0, -10)
    ..cubicTo(16, -30, 42, -62, 42, -90)
    ..arcToPoint(
      const Offset(-42, -90),
      radius: const Radius.circular(42),
      clockwise: false,
    )
    ..cubicTo(-42, -62, -16, -30, 0, -10)
    ..close();

  // In milliseconds of the 900 ms run.
  static const double _total = 900;
  static const double _stagger = 70;
  static const double _each = 520;
  static const double _tug = 0.28;

  @override
  void paint(Canvas canvas, Size size) {
    final double ms = progress.value * _total;
    // The page comes up under the petals as they leave.
    final double veil =
        1 - Curves.easeOut.transform(((ms - 120) / 520).clamp(0.0, 1.0));
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = background.withValues(alpha: veil),
    );
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(_scale);
    for (int i = 0; i < _colors.length; i++) {
      final double t = ((ms - i * _stagger) / _each).clamp(0.0, 1.0);
      double out;
      double grow;
      double turn = 0;
      double spin = 0;
      double alpha = 0.92;
      if (t < _tug) {
        // The tug: the petal is drawn a little way out and swells.
        final double u = Curves.easeOut.transform(t / _tug);
        out = 14 * u;
        grow = 1 + 0.06 * u;
      } else {
        // Then it is pulled away, turning as it goes.
        final double u = Curves.easeIn.transform((t - _tug) / (1 - _tug));
        out = 14 + (380 - 14) * u;
        grow = 1.06 - 0.16 * u;
        turn = -16 * u;
        spin = -50 * u;
        alpha = 0.92 * (1 - u);
      }
      canvas
        ..save()
        ..rotate((i * 60 + turn) * math.pi / 180)
        ..translate(0, -out)
        ..rotate(spin * math.pi / 180)
        ..scale(grow)
        ..drawPath(_petal, Paint()..color = _colors[i].withValues(alpha: alpha))
        ..restore();
    }
    final double shrink =
        1 - Curves.easeIn.transform(((ms - 380) / 260).clamp(0.0, 1.0));
    if (shrink > 0) {
      canvas.drawCircle(
        Offset.zero,
        9 * shrink,
        Paint()..color = core.withValues(alpha: shrink),
      );
    }
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.background != background || old.core != core;
}

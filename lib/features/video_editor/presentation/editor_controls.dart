import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/motion.dart';
import '../domain/cut_plan.dart';
import 'cut_timeline_painter.dart' show editYellow;

/// A time with tenths, for placing a cut: "1:23.4".
String clock(int ms) {
  final int tenths = (ms / 100).floor();
  final int s = tenths ~/ 10;
  final int h = s ~/ 3600;
  final int m = (s ~/ 60) % 60;
  final String ss = (s % 60).toString().padLeft(2, '0');
  final String t = '$ss.${tenths % 10}';
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$t' : '$m:$t';
}

/// A time typed as "30", "1:30", "1:02:30" or with tenths, "0:30.5", in
/// ms; null when it isn't one. Seconds and minutes after the first part go
/// up to 59.
int? parseClock(String text) {
  final String t = text.trim();
  // At most six digits up front and three after the point: enough for any
  // video, and short of what int.parse can't read.
  if (!RegExp(r'^\d{1,6}(:\d{1,2}){0,2}(\.\d{1,3})?$').hasMatch(t)) {
    return null;
  }
  final List<String> dot = t.split('.');
  final List<int> parts = dot.first.split(':').map(int.parse).toList();
  for (int i = 1; i < parts.length; i++) {
    if (parts[i] > 59) return null;
  }
  int seconds = 0;
  for (final int p in parts) {
    seconds = seconds * 60 + p;
  }
  final int fraction = dot.length < 2
      ? 0
      : (double.parse('0.${dot[1]}') * 1000).round();
  return seconds * 1000 + fraction;
}

class EditorTopBar extends StatelessWidget {
  const EditorTopBar({
    super.key,
    required this.canSave,
    required this.onCancel,
    required this.onSave,
  });

  final bool canSave;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: <Widget>[
          Pressable(
            label: 'Cancel',
            onTap: onCancel,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white, fontSize: 17),
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Edit video',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Dim until there is something to save, then fades bright.
          Pressable(
            label: 'Save',
            onTap: canSave ? onSave : null,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Save',
                style: TextStyle(
                  color: editYellow,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditorPlayBadge extends StatelessWidget {
  const EditorPlayBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x8C1C1C1E),
        ),
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Icon(CupertinoIcons.play_fill, size: 32, color: Colors.white),
        ),
      ),
    );
  }
}

class EditorReadout extends StatelessWidget {
  const EditorReadout({super.key, required this.plan, required this.position});

  final CutPlan plan;
  final int position;

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      child: Row(
        children: <Widget>[
          Text(clock(position), style: style),
          const Spacer(),
          Text(
            plan.changed
                ? 'New length ${clock(plan.keptLength)}'
                : 'Length ${clock(plan.duration)}',
            style: style.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// Under the timeline: fine adjustment for a selected handle, and the cut
/// buttons.
class EditorTools extends StatelessWidget {
  const EditorTools({
    super.key,
    required this.plan,
    required this.selected,
    required this.selectedCut,
    required this.canAddCut,
    required this.onAddCut,
    required this.onStartHere,
    required this.onTypeTime,
    required this.onKeepCut,
    required this.onNudge,
  });

  final CutPlan plan;
  final Handle? selected;
  final int? selectedCut;
  final bool canAddCut;
  final VoidCallback onAddCut;

  /// Starts the edit at the playhead: play through an intro, then tap.
  final VoidCallback? onStartHere;
  final VoidCallback onKeepCut;
  final ValueChanged<int> onNudge;

  /// Opens a box to type the selected handle's time.
  final VoidCallback onTypeTime;

  static const TextStyle _label = TextStyle(color: Colors.white, fontSize: 15);

  String _name(Handle h) => switch (h.kind) {
    HandleKind.start => 'Start',
    HandleKind.end => 'End',
    HandleKind.cutStart => 'Cut from',
    HandleKind.cutEnd => 'Cut to',
  };

  @override
  Widget build(BuildContext context) {
    final Handle? h = selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 48,
            child: AnimatedSwitcher(
              duration: _motion(context),
              child: h == null
                  ? const Center(
                      key: ValueKey<String>('hint'),
                      child: Text(
                        'Drag the yellow ends to trim. Pinch the timeline to '
                        'zoom in on a long video.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    )
                  : Row(
                      key: const ValueKey<String>('handle'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _Nudge(
                          icon: CupertinoIcons.chevron_left,
                          label: 'Back a tenth of a second',
                          onStep: (int size) => onNudge(-size),
                        ),
                        // Tap to type the time instead.
                        Pressable(
                          label: 'Type a time for ${_name(h)}',
                          onTap: onTypeTime,
                          child: SizedBox(
                            width: 170,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  '${_name(h)} ${clock(plan.at(h))}',
                                  style: _label.copyWith(
                                    fontFeatures: const <FontFeature>[
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(
                                  CupertinoIcons.pencil,
                                  size: 16,
                                  color: Colors.white70,
                                ),
                              ],
                            ),
                          ),
                        ),
                        _Nudge(
                          icon: CupertinoIcons.chevron_right,
                          label: 'On a tenth of a second',
                          onStep: (int size) => onNudge(size),
                        ),
                      ],
                    ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _ToolButton(
                icon: CupertinoIcons.arrow_right_to_line,
                label: 'Start here',
                onTap: onStartHere,
              ),
              const SizedBox(width: AppSpacing.md),
              // A selected cut can only be kept; with none, a new one can
              // be made. One slot keeps the row on one line, and the two
              // trade places with a quick fade.
              AnimatedSwitcher(
                duration: _motion(context),
                transitionBuilder: (Widget child, Animation<double> a) =>
                    FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.92, end: 1).animate(a),
                        child: child,
                      ),
                    ),
                child: selectedCut != null
                    ? _ToolButton(
                        key: const ValueKey<String>('keep'),
                        icon: CupertinoIcons.arrow_uturn_left,
                        label: 'Keep this part',
                        onTap: onKeepCut,
                      )
                    : _ToolButton(
                        key: const ValueKey<String>('cut'),
                        icon: CupertinoIcons.scissors,
                        label: 'Cut a section',
                        onTap: canAddCut ? onAddCut : null,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A short fade for the editor's controls; none with "Remove animations".
Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.short;

/// A step button that repeats while held: a tenth of a second a step at
/// first, then a whole second once held for about a second.
class _Nudge extends StatefulWidget {
  const _Nudge({required this.icon, required this.label, required this.onStep});

  final IconData icon;
  final String label;

  /// Called with the step's size in ms.
  final ValueChanged<int> onStep;

  @override
  State<_Nudge> createState() => _NudgeState();
}

class _NudgeState extends State<_Nudge> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pressable gives the tap and the press-in sink; holding is caught
    // around it, so a held button sinks too.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) {
        widget.onStep(100);
        int steps = 0;
        _repeat = Timer.periodic(const Duration(milliseconds: 90), (_) {
          steps++;
          widget.onStep(steps < 11 ? 100 : 1000);
        });
      },
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: Pressable(
        label: widget.label,
        minSize: const Size(48, 48),
        onTap: () => widget.onStep(100),
        child: Icon(widget.icon, color: Colors.white),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Pressable dims it, with a fade, while it can't be used.
    const Color color = Colors.white;
    return Pressable(
      label: label,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: const TextStyle(color: color, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

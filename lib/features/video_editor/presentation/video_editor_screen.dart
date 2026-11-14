import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../core/video/video_session.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/dialogs.dart';
import '../../albums/presentation/albums_providers.dart'
    show nativeChannelProvider;
import '../data/video_cutter.dart';
import '../domain/cut_plan.dart';
import 'cut_timeline.dart';
import 'timeline_frames.dart';
import 'editor_controls.dart';
import 'save_progress.dart';

/// What the editor saved, and whether replacing the original was asked for.
typedef EditOutcome = ({SavedEdit saved, bool askedToReplace});

/// Cuts parts out of a video: the ends with the yellow handles, anything
/// in between with Cut a section. Preview plays the result, skipping what
/// is cut. Save writes a new video, or replaces the original, which then
/// waits in Recently deleted.
class VideoEditorScreen extends ConsumerStatefulWidget {
  const VideoEditorScreen({super.key, required this.asset});

  final AssetEntity asset;

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen> {
  late final VideoSession _session = VideoSession(_newController)
    ..addListener(_tick);
  File? _file;

  final GlobalKey<CutTimelineState> _timeline = GlobalKey<CutTimelineState>();

  /// The timeline's frames, read for whatever stretch it shows.
  TimelineFrames? _frames;
  bool _failed = false;
  CutPlan? _plan;
  Handle? _selected;
  int? _selectedCut;
  bool _dragging = false;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      await _session.start();
    } on Exception {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final VideoPlayerController? c = _session.controller;
    if (!mounted || c == null) return;
    setState(() => _plan = CutPlan.whole(c.value.duration.inMilliseconds));
  }

  Future<VideoPlayerController> _newController() async {
    final File? f = _file ??= await widget.asset.file;
    if (f == null) throw const FileSystemException('The video has no file');
    _frames ??= TimelineFrames(
      (List<int> times) =>
          ref.read(nativeChannelProvider).videoFramesAt(f.path, times, 120),
    );
    final VideoPlayerController c = VideoPlayerController.file(f);
    try {
      await c.initialize();
    } on Object {
      await c.dispose();
      rethrow;
    }
    return c;
  }

  /// While previewing, steps over what is cut and stops after the end.
  void _tick() {
    final CutPlan? plan = _plan;
    final VideoPlayerController? c = _session.controller;
    if (plan != null &&
        c != null &&
        c.value.isPlaying &&
        !_dragging &&
        _session.target == null) {
      final int at = c.value.position.inMilliseconds;
      final int? next = plan.keptFrom(at);
      if (next == null) {
        _session.pause();
        _session.seekTo(Duration(milliseconds: plan.end));
      } else if (next != at) {
        _session.seekTo(Duration(milliseconds: next));
      }
    }
    if (mounted) setState(() {});
  }

  int get _position => _session.position.inMilliseconds;

  void _togglePlay() {
    final VideoPlayerController? c = _session.controller;
    final CutPlan? plan = _plan;
    if (c == null || plan == null) return;
    if (c.value.isPlaying) {
      _session.pause();
      return;
    }
    // From the start of the edit when the playhead is past it or outside it.
    final int? from = plan.keptFrom(_position);
    final int start = from == null || _position >= plan.end ? plan.start : from;
    if (start != _position) _session.seekTo(Duration(milliseconds: start));
    _session.settled.then((_) {
      if (mounted) _session.play();
    });
  }

  void _dragStart() {
    _dragging = true;
    _wasPlaying = _session.controller?.value.isPlaying ?? false;
    _session.pause();
  }

  void _dragEnd() {
    _dragging = false;
    if (!_wasPlaying) {
      setState(() {});
      return;
    }
    _session.settled.then((_) {
      if (mounted && !_dragging) _session.play();
    });
  }

  void _move(Handle h, int ms) {
    final CutPlan? plan = _plan;
    if (plan == null) return;
    final CutPlan next = plan.move(h, ms);
    // The frame at the cut point, so the finger can find the exact spot.
    _session.seekTo(Duration(milliseconds: next.at(h)));
    setState(() {
      _plan = next;
      _selected = h;
      _selectedCut = null;
    });
  }

  void _scrub(int ms) {
    _session.seekTo(Duration(milliseconds: ms));
    setState(() {});
  }

  void _select(Handle? h) {
    setState(() {
      _selected = h;
      _selectedCut = null;
    });
    if (h != null) {
      _session.pause();
      _session.seekTo(Duration(milliseconds: _plan!.at(h)));
    }
  }

  void _selectCut(int? i) => setState(() {
    _selectedCut = i;
    _selected = null;
  });

  /// Nudges the selected handle by [ms], for a spot too fine for a finger.
  void _nudge(int ms) {
    final Handle? h = _selected;
    final CutPlan? plan = _plan;
    if (h == null || plan == null) return;
    _session.pause();
    _move(h, plan.at(h) + ms);
  }

  /// Asks for the selected handle's time typed out, for a moment already
  /// known, such as an ad from 12:40 to 14:05.
  Future<void> _typeTime() async {
    final Handle? h = _selected;
    final CutPlan? plan = _plan;
    if (h == null || plan == null) return;
    _session.pause();
    final String? typed = await promptName(
      context,
      title: 'Set the time',
      label: 'Time',
      hint: 'e.g. 0:30 or 1:02:30.5',
      confirmLabel: 'Set',
      initial: clock(plan.at(h)),
      keyboardType: TextInputType.datetime,
      subject: 'time',
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp('[0-9:.]')),
      ],
      validate: (String v) {
        final int? ms = parseClock(v);
        if (ms == null) return 'Type a time like 0:30 or 1:02:30';
        if (ms > plan.duration) {
          return 'The video is only ${clock(plan.duration)} long';
        }
        return null;
      },
    );
    final int? ms = typed == null ? null : parseClock(typed);
    if (ms == null || !mounted) return;
    // Stops at its neighbours, as a drag does; the label shows where.
    _move(h, ms);
  }

  /// The edit starts at the playhead: everything before it goes, as when
  /// an intro has just finished playing.
  void _startHere() {
    final CutPlan? plan = _plan;
    if (plan == null) return;
    _session.pause();
    // Stops short of a cut after it, as a drag does.
    setState(() {
      _plan = plan.move(const Handle.start(), _position);
      _selected = const Handle.start();
      _selectedCut = null;
    });
  }

  void _addCut() {
    final CutPlan? plan = _plan;
    if (plan == null) return;
    // A third of what the strip shows, so both of its edges are in view
    // at any zoom: seconds on a zoomed-in hour, not six minutes.
    final int? span = _timeline.currentState?.visibleSpan;
    final (CutPlan, int)? added = plan.addCut(_position, visible: span);
    if (added == null) {
      return;
    }
    _session.pause();
    setState(() {
      _plan = added.$1;
      _selectedCut = added.$2;
      _selected = null;
    });
  }

  void _keepCut() {
    final int? i = _selectedCut;
    final CutPlan? plan = _plan;
    if (i == null || plan == null) return;
    setState(() {
      _plan = plan.removeCut(i);
      _selectedCut = null;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!(_plan?.changed ?? false)) return true;
    return confirmAction(
      context,
      title: 'Discard this edit?',
      message: 'The video stays as it is.',
      confirmLabel: 'Discard',
    );
  }

  Future<void> _save() async {
    final CutPlan? plan = _plan;
    if (plan == null || !plan.changed) return;
    _session.pause();
    final native = ref.read(nativeChannelProvider);
    if (!await native.hasAllFilesAccess()) {
      if (!mounted) return;
      final bool open = await confirmAction(
        context,
        title: 'Allow All files access',
        message:
            'fotos saves the edit in the same folder as the original, which '
            'needs All files access.',
        confirmLabel: 'Open settings',
        destructive: false,
      );
      if (open) await native.openAllFilesAccessSettings();
      return;
    }
    if (!mounted) return;
    final bool? replace = await showActionSheet<bool>(
      context,
      title: 'Save edit',
      message:
          'Both keep the same folder. Replacing moves the original to '
          'Recently deleted, where it can be restored for 30 days.',
      choices: const <SheetChoice<bool>>[
        SheetChoice<bool>(false, 'Save as new video'),
        SheetChoice<bool>(true, 'Replace original'),
      ],
    );
    if (replace == null || !mounted) return;
    final SavedEdit? saved = await saveWithProgress(
      context,
      VideoCutter(native),
      id: widget.asset.id,
      plan: plan,
      replace: replace,
    );
    if (saved == null || !mounted) return;
    Navigator.of(
      context,
    ).pop<EditOutcome>((saved: saved, askedToReplace: replace));
  }

  @override
  void dispose() {
    _session.removeListener(_tick);
    _session.dispose();
    _frames?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CutPlan? plan = _plan;
    final VideoPlayerController? c = _session.controller;
    return PopScope(
      canPop: !(plan?.changed ?? false),
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              children: <Widget>[
                EditorTopBar(
                  canSave: plan?.changed ?? false,
                  onCancel: () async {
                    if (await _confirmDiscard() && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  onSave: _save,
                ),
                Expanded(
                  child: _failed
                      ? const Center(
                          child: Text(
                            'This video can\'t be opened for editing.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : c == null || plan == null
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _togglePlay,
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              AspectRatio(
                                aspectRatio: c.value.aspectRatio,
                                child: VideoPlayer(c),
                              ),
                              // As in the viewer: the badge pops in when
                              // playback stops and shrinks away as it starts.
                              AnimatedSwitcher(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 220),
                                reverseDuration: const Duration(
                                  milliseconds: 140,
                                ),
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder:
                                    (Widget child, Animation<double> a) =>
                                        FadeTransition(
                                          opacity: a,
                                          child: ScaleTransition(
                                            scale: Tween<double>(
                                              begin: 0.7,
                                              end: 1,
                                            ).animate(a),
                                            child: child,
                                          ),
                                        ),
                                child: c.value.isPlaying
                                    ? const SizedBox.shrink()
                                    : const EditorPlayBadge(),
                              ),
                            ],
                          ),
                        ),
                ),
                if (plan != null && c != null) ...<Widget>[
                  EditorReadout(plan: plan, position: _position),
                  CutTimeline(
                    key: _timeline,
                    plan: plan,
                    frames: _frames!,
                    position: _position,
                    playing: c.value.isPlaying,
                    selected: _selected,
                    selectedCut: _selectedCut,
                    onMove: _move,
                    onScrub: _scrub,
                    onDragStart: _dragStart,
                    onDragEnd: _dragEnd,
                    onSelect: _select,
                    onSelectCut: _selectCut,
                  ),
                  EditorTools(
                    plan: plan,
                    selected: _selected,
                    selectedCut: _selectedCut,
                    canAddCut: plan.addCut(_position) != null,
                    onAddCut: _addCut,
                    onStartHere: _position > plan.start ? _startHere : null,
                    onKeepCut: _keepCut,
                    onNudge: _nudge,
                    onTypeTime: _typeTime,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

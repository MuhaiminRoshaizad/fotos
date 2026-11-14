import 'package:flutter/foundation.dart';

/// A stretch of a video, in milliseconds from its start.
@immutable
class Span {
  const Span(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  bool contains(int ms) => ms >= start && ms < end;

  @override
  bool operator ==(Object other) =>
      other is Span && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Span($start, $end)';
}

/// One of the handles on the timeline.
@immutable
class Handle {
  const Handle.start() : kind = HandleKind.start, cut = -1;
  const Handle.end() : kind = HandleKind.end, cut = -1;
  const Handle.cutStart(this.cut) : kind = HandleKind.cutStart;
  const Handle.cutEnd(this.cut) : kind = HandleKind.cutEnd;

  final HandleKind kind;

  /// Which cut, for a cut's handles.
  final int cut;

  @override
  bool operator ==(Object other) =>
      other is Handle && other.kind == kind && other.cut == cut;

  @override
  int get hashCode => Object.hash(kind, cut);

  @override
  String toString() => 'Handle($kind, $cut)';
}

enum HandleKind { start, end, cutStart, cutEnd }

/// What to keep of a video: from [start] to [end], less the [cuts] taken
/// out between them.
///
/// Every change goes through a method that keeps the plan valid, so the
/// timeline can pass a finger's position straight in: a handle stops at its
/// neighbour instead of crossing it, nothing kept or cut is shorter than
/// [minPart], and the cuts stay in order without touching.
@immutable
class CutPlan {
  const CutPlan._(this.duration, this.start, this.end, this.cuts);

  /// The whole of a video [duration] ms long: nothing cut yet.
  factory CutPlan.whole(int duration) =>
      CutPlan._(duration, 0, duration, const <Span>[]);

  /// The shortest part kept or cut, so every part can still be seen and
  /// grabbed on the timeline.
  static const int minPart = 500;

  final int duration;
  final int start;
  final int end;

  /// Parts taken out between [start] and [end], in order.
  final List<Span> cuts;

  bool get changed => start > 0 || end < duration || cuts.isNotEmpty;

  /// The parts saved, in order.
  List<Span> get kept {
    final List<Span> out = <Span>[];
    int from = start;
    for (final Span c in cuts) {
      out.add(Span(from, c.start));
      from = c.end;
    }
    out.add(Span(from, end));
    return out;
  }

  /// How long the saved video will be.
  int get keptLength => kept.fold(0, (int sum, Span s) => sum + s.length);

  /// Where [h] sits.
  int at(Handle h) => switch (h.kind) {
    HandleKind.start => start,
    HandleKind.end => end,
    HandleKind.cutStart => cuts[h.cut].start,
    HandleKind.cutEnd => cuts[h.cut].end,
  };

  /// Every handle on the timeline, left to right.
  List<Handle> get handles => <Handle>[
    const Handle.start(),
    for (int i = 0; i < cuts.length; i++) ...<Handle>[
      Handle.cutStart(i),
      Handle.cutEnd(i),
    ],
    const Handle.end(),
  ];

  /// [h] moved as near to [ms] as it can go.
  CutPlan move(Handle h, int ms) {
    // Each handle lives between its neighbours, minPart away from each.
    final List<Handle> all = handles;
    final int i = all.indexOf(h);
    if (i < 0) return this;
    final int lo = i == 0 ? 0 : at(all[i - 1]) + minPart;
    final int hi = i == all.length - 1 ? duration : at(all[i + 1]) - minPart;
    if (lo > hi) return this;
    final int to = ms.clamp(lo, hi);
    return switch (h.kind) {
      HandleKind.start => CutPlan._(duration, to, end, cuts),
      HandleKind.end => CutPlan._(duration, start, to, cuts),
      HandleKind.cutStart => _withCut(h.cut, Span(to, cuts[h.cut].end)),
      HandleKind.cutEnd => _withCut(h.cut, Span(cuts[h.cut].start, to)),
    };
  }

  CutPlan _withCut(int i, Span s) => CutPlan._(
    duration,
    start,
    end,
    List<Span>.unmodifiable(<Span>[...cuts]..[i] = s),
  );

  /// A new cut around [ms] in the kept part [ms] falls in: a tenth of the
  /// video, or a third of the [visible] stretch of the timeline if that is
  /// less, so both its edges are in view at any zoom; narrower if the part
  /// is. Null when the part is too short to leave something kept either
  /// side.
  (CutPlan, int)? addCut(int ms, {int? visible}) {
    final List<Span> parts = kept;
    final int p = parts.indexWhere((Span s) => s.contains(ms));
    if (p < 0) return null;
    final Span part = parts[p];
    final int room = part.length - 2 * minPart;
    if (room < minPart) return null;
    final int tenth = duration ~/ 10;
    final int wanted = visible == null || visible ~/ 3 > tenth
        ? tenth
        : visible ~/ 3;
    final int w = wanted.clamp(minPart, room);
    final int lo = part.start + minPart;
    final int hi = part.end - minPart - w;
    final int from = (ms - w ~/ 2).clamp(lo, hi);
    final List<Span> next = <Span>[...cuts]..insert(p, Span(from, from + w));
    return (CutPlan._(duration, start, end, List<Span>.unmodifiable(next)), p);
  }

  /// The plan with cut [i] kept after all.
  CutPlan removeCut(int i) => CutPlan._(
    duration,
    start,
    end,
    List<Span>.unmodifiable(<Span>[...cuts]..removeAt(i)),
  );

  /// The cut [ms] falls in, if any.
  int? cutAt(int ms) {
    final int i = cuts.indexWhere((Span c) => c.contains(ms));
    return i < 0 ? null : i;
  }

  /// Where playback of the saved video would be at [ms] of the original:
  /// [ms] itself when it is kept, else the start of the next kept part,
  /// or null past the last.
  int? keptFrom(int ms) {
    for (final Span s in kept) {
      if (ms < s.start) return s.start;
      if (ms < s.end) return ms;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is CutPlan &&
      other.duration == duration &&
      other.start == start &&
      other.end == end &&
      listEquals(other.cuts, cuts);

  @override
  int get hashCode => Object.hash(duration, start, end, Object.hashAll(cuts));
}

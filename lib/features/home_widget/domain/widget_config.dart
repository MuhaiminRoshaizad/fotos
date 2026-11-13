/// One photo widget's settings, as its setup screen edits them. The Android
/// side keeps them per widget (widget/WidgetConfig.kt), with the same keys
/// and values; keep the two alike.
library;

enum WidgetShow { photos, videos, both }

enum WidgetSource { all, albums, favourites, day }

enum WidgetOrder { shuffle, years, newest }

enum WidgetFit { fill, whole }

enum WidgetCaption { date, ago, album, none }

/// The intervals Android can run a widget's flipper at, in seconds.
const List<int> widgetIntervals = <int>[10, 60, 900, 3600];

class WidgetConfig {
  const WidgetConfig({
    this.show = WidgetShow.photos,
    this.source = WidgetSource.all,
    this.albums = const <String>{},
    this.leaveOut = const <String>{},
    this.order = WidgetOrder.shuffle,
    this.every = 10,
    this.fit = WidgetFit.whole,
    this.caption = WidgetCaption.date,
    this.skip = true,
  });

  final WidgetShow show;
  final WidgetSource source;

  /// Album ids (MediaStore bucket ids) shown when [source] is albums.
  final Set<String> albums;

  /// Album ids skipped for the other sources.
  final Set<String> leaveOut;
  final WidgetOrder order;

  /// Seconds between pictures, one of [widgetIntervals].
  final int every;
  final WidgetFit fit;
  final WidgetCaption caption;

  /// Whether the widget shows a skip arrow.
  final bool skip;

  /// Done is allowed unless "Chosen albums" has none chosen.
  bool get complete => source != WidgetSource.albums || albums.isNotEmpty;

  WidgetConfig copyWith({
    WidgetShow? show,
    WidgetSource? source,
    Set<String>? albums,
    Set<String>? leaveOut,
    WidgetOrder? order,
    int? every,
    WidgetFit? fit,
    WidgetCaption? caption,
    bool? skip,
  }) => WidgetConfig(
    show: show ?? this.show,
    source: source ?? this.source,
    albums: albums ?? this.albums,
    leaveOut: leaveOut ?? this.leaveOut,
    order: order ?? this.order,
    every: every ?? this.every,
    fit: fit ?? this.fit,
    caption: caption ?? this.caption,
    skip: skip ?? this.skip,
  );

  /// The keys and values the Android side reads.
  Map<String, Object> toMap() => <String, Object>{
    'show': show.name,
    'source': source.name,
    'albums': albums.toList(),
    'leaveOut': leaveOut.toList(),
    'order': order.name,
    'every': every,
    'fit': fit.name,
    'caption': caption.name,
    'skip': skip,
  };

  static WidgetConfig fromMap(Map<Object?, Object?> m) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((T v) => v.name == name).firstOrNull ?? fallback;
    Set<String> ids(Object? v) => <String>{
      for (final Object? e in (v as List<Object?>?) ?? <Object?>[])
        ?e as String?,
    };
    final int every = (m['every'] as num?)?.toInt() ?? 10;
    return WidgetConfig(
      show: pick(WidgetShow.values, m['show'], WidgetShow.photos),
      source: pick(WidgetSource.values, m['source'], WidgetSource.all),
      albums: ids(m['albums']),
      leaveOut: ids(m['leaveOut']),
      order: pick(WidgetOrder.values, m['order'], WidgetOrder.shuffle),
      every: widgetIntervals.contains(every) ? every : 10,
      fit: pick(WidgetFit.values, m['fit'], WidgetFit.whole),
      caption: pick(WidgetCaption.values, m['caption'], WidgetCaption.date),
      skip: (m['skip'] as bool?) ?? true,
    );
  }
}

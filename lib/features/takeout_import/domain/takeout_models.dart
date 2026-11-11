/// Counts the importer reports, both while running and when finished.
class TakeoutCounts {
  const TakeoutCounts({
    this.imported = 0,
    this.duplicates = 0,
    this.review = 0,
    this.locked = 0,
    this.failed = 0,
    this.done = 0,
    this.total = 0,
    this.current = '',
    this.cancelled = false,
  });

  factory TakeoutCounts.fromMap(Map<Object?, Object?> m) {
    int n(String k) => ((m[k] as num?) ?? 0).toInt();
    return TakeoutCounts(
      imported: n('imported'),
      duplicates: n('duplicates'),
      review: n('review'),
      locked: n('locked'),
      failed: n('failed'),
      done: n('done'),
      total: n('total'),
      current: (m['current'] as String?) ?? '',
      cancelled: (m['cancelled'] as bool?) ?? false,
    );
  }

  final int imported;

  /// Identical bytes already on the phone, skipped.
  final int duplicates;

  /// Possible duplicates set aside for the user to decide.
  final int review;

  /// Locked Folder items, skipped on purpose.
  final int locked;
  final int failed;
  final int done;
  final int total;
  final String current;
  final bool cancelled;

  double get fraction => total == 0 ? 0 : done / total;
}

/// Why an item was set aside rather than imported.
enum ReviewReason {
  name('Same name as a photo already on the phone, but different bytes.'),
  time('Taken at the same moment as one already on the phone.'),
  motion(
    'The moving part of a Pixel Motion Photo, which Google exports a second '
    'time on its own. The photo itself still has it inside, so discarding '
    'this loses nothing. Import it only if you want it as a separate video.',
  );

  const ReviewReason(this.explanation);
  final String explanation;
}

/// A Takeout item waiting for Keep both / Keep phone's / Keep Takeout's.
class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.path,
    required this.name,
    required this.video,
    required this.size,
    required this.reason,
    this.taken,
    this.phoneId,
  });

  factory ReviewItem.fromMap(Map<Object?, Object?> m) => ReviewItem(
    id: m['id']! as String,
    path: m['path']! as String,
    name: m['name']! as String,
    video: (m['video'] as bool?) ?? false,
    size: ((m['size'] as num?) ?? 0).toInt(),
    reason: ReviewReason.values.firstWhere(
      (ReviewReason r) => r.name == m['reason'],
      orElse: () => ReviewReason.name,
    ),
    taken: m['taken'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['taken']! as num).toInt()),
    phoneId: m['phoneId'] as String?,
  );

  final String id;

  /// The staged Takeout copy, inside fotos' own storage.
  final String path;
  final String name;
  final bool video;
  final int size;
  final ReviewReason reason;
  final DateTime? taken;

  /// The phone item it may duplicate, if any.
  final String? phoneId;
}

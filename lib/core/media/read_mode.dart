/// How an album's photos are read, chosen per album under Read as.
enum ReadMode {
  /// Swipe sideways; a tap shows or hides the controls.
  photos('Photos'),

  /// As photos, but a tap on the left or right third turns the page, for
  /// comics; the middle third shows or hides the controls.
  pages('Pages'),

  /// Every page joined top to bottom in one long scroll.
  strip('Strip');

  const ReadMode(this.label);
  final String label;

  static ReadMode decode(String s) => ReadMode.values.firstWhere(
    (ReadMode m) => m.name == s,
    orElse: () => ReadMode.photos,
  );
}

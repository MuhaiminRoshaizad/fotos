/// Whether a photo's file name says it is a Motion Photo.
///
/// The grid marks Motion Photos from the name alone, because the sure test
/// (reading the file for its embedded video, as the viewer does) is too
/// slow to run for every tile scrolled past. Pixel cameras name them
/// `PXL_….MP.jpg`, and before that `MVIMG_….jpg`. A Motion Photo that was
/// renamed is still found by the viewer; it just has no mark in the grid.
bool looksLikeMotionPhoto(String? name) {
  if (name == null) return false;
  final String n = name.toLowerCase();
  return RegExp(r'\.mp\.(jpe?g|heic)$').hasMatch(n) ||
      (n.startsWith('mvimg_') && RegExp(r'\.(jpe?g|heic)$').hasMatch(n));
}

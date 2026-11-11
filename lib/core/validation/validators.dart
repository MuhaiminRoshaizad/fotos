import 'dart:convert';

/// Album, folder and file names: not empty, no path separators, not hidden,
/// not too long, and not already used in the same place (ignoring case, as
/// Android's shared storage does). Returns the message to show, or null.
String? validateFolderName(
  String v,
  Iterable<String> taken, {
  String? current,
}) {
  if (v.isEmpty) return 'Enter a name';
  if (v.contains('/') || v.contains(r'\')) {
    return r"Names can't contain / or \";
  }
  if (v.startsWith('.')) return "Names can't start with a dot";
  // The filesystem limit is 255 bytes; a long comic name (tags, circle,
  // language) fits well within it. Count bytes so multibyte titles don't
  // overshoot it.
  if (utf8.encode(v).length > 255) return 'That name is too long';
  final String lower = v.toLowerCase();
  final bool clash = taken.any(
    (String t) => t.toLowerCase() == lower && t != current,
  );
  return clash ? 'That name is already used' : null;
}

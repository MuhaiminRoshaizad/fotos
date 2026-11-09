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
  if (v.length > 60) return 'Keep it under 60 characters';
  final String lower = v.toLowerCase();
  final bool clash = taken.any(
    (String t) => t.toLowerCase() == lower && t != current,
  );
  return clash ? 'That name is already used' : null;
}

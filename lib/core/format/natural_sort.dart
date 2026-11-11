/// Orders names the way a person reading a file list expects: a run of digits
/// counts as the number it spells, so page 2 comes before page 10 instead of
/// after it. A plain `String.compareTo` reads left to right and so lands on
/// 1, 10, 11, 2, 20, 3 — the order of comic pages unzipped from a folder is a
/// textbook case. Letters compare ignoring case, matching every other name
/// order in the app.
///
/// Digit runs are compared by value without being parsed into an `int`, so a
/// page count past the 64-bit range still sorts correctly, and "01" and "1"
/// keep a stable order rather than being treated as equal.
int naturalCompare(String a, String b) {
  // Lowercase once so letters compare case-insensitively, including non-ASCII;
  // the originals break the final tie so "A" and "a" keep a stable order.
  final String la = a.toLowerCase();
  final String lb = b.toLowerCase();
  int i = 0;
  int j = 0;
  while (i < la.length && j < lb.length) {
    if (_isDigit(la.codeUnitAt(i)) && _isDigit(lb.codeUnitAt(j))) {
      final int startA = i;
      final int startB = j;
      while (i < la.length && _isDigit(la.codeUnitAt(i))) {
        i++;
      }
      while (j < lb.length && _isDigit(lb.codeUnitAt(j))) {
        j++;
      }
      final int c = _compareDigits(la, startA, i, lb, startB, j);
      if (c != 0) return c;
    } else {
      final int c = la.codeUnitAt(i).compareTo(lb.codeUnitAt(j));
      if (c != 0) return c;
      i++;
      j++;
    }
  }
  // Whichever name ran out first is the prefix and sorts earlier; a true tie
  // falls back to the originals so the order is deterministic.
  final int c = (la.length - i).compareTo(lb.length - j);
  return c != 0 ? c : a.compareTo(b);
}

const int _zero = 0x30; // '0'
const int _nine = 0x39; // '9'

bool _isDigit(int unit) => unit >= _zero && unit <= _nine;

/// Compares the digit runs `a[sa..ea)` and `b[sb..eb)` by numeric value. More
/// significant digits means a larger number; on an equal value the run with
/// fewer leading zeros sorts first, so "1" precedes "01".
int _compareDigits(String a, int sa, int ea, String b, int sb, int eb) {
  int ia = sa;
  while (ia < ea - 1 && a.codeUnitAt(ia) == _zero) {
    ia++;
  }
  int ib = sb;
  while (ib < eb - 1 && b.codeUnitAt(ib) == _zero) {
    ib++;
  }
  final int lenA = ea - ia;
  final int lenB = eb - ib;
  if (lenA != lenB) return lenA - lenB;
  for (int k = 0; k < lenA; k++) {
    final int c = a.codeUnitAt(ia + k).compareTo(b.codeUnitAt(ib + k));
    if (c != 0) return c;
  }
  return (ea - sa) - (eb - sb);
}

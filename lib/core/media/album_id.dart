/// The id Android gives the album of the folder at [absolutePath], which is
/// MediaStore's BUCKET_ID: Java's String hash of the path in lower case.
/// Android doesn't document this; it was checked against MediaStore on the
/// phone (13/11/2026). It lets a folder renamed or moved in Files take its
/// album's pin along without asking MediaStore for the new id.
String albumIdOf(String absolutePath) {
  int h = 0;
  for (final int unit in absolutePath.toLowerCase().codeUnits) {
    h = (31 * h + unit) & 0xFFFFFFFF;
  }
  return (h >= 0x80000000 ? h - 0x100000000 : h).toString();
}

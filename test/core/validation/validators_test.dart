import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/validation/validators.dart';

void main() {
  const List<String> taken = <String>['Camera', 'Holiday 2019'];

  test('accepts a new, plain name', () {
    expect(validateFolderName('Receipts', taken), isNull);
  });

  test('rejects empty, separators, hidden and overlong names', () {
    expect(validateFolderName('', taken), 'Enter a name');
    expect(validateFolderName('a/b', taken), contains('/'));
    expect(validateFolderName(r'a\b', taken), contains('/'));
    expect(validateFolderName('.secret', taken), contains('dot'));
    expect(validateFolderName('x' * 256, taken), 'That name is too long');
  });

  test('allows a long comic name, within the filesystem limit', () {
    const String comic =
        '(C97) [Circle (Author)] A Very Long Comic Title Volume 1 '
        '(Some Series) [English] [Digital]';
    expect(comic.length, greaterThan(60));
    expect(validateFolderName('$comic.cbz', taken), isNull);
    // 255 bytes is the ceiling; one over is rejected.
    expect(validateFolderName('x' * 255, taken), isNull);
    expect(validateFolderName('x' * 256, taken), 'That name is too long');
  });

  test('rejects a clash regardless of case, but not the current name', () {
    expect(validateFolderName('camera', taken), 'That name is already used');
    expect(validateFolderName('Camera', taken, current: 'Camera'), isNull);
  });
}

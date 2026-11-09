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
    expect(validateFolderName('x' * 61, taken), contains('60'));
  });

  test('rejects a clash regardless of case, but not the current name', () {
    expect(validateFolderName('camera', taken), 'That name is already used');
    expect(validateFolderName('Camera', taken, current: 'Camera'), isNull);
  });
}

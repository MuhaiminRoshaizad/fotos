import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/core/format/formatters.dart';

void main() {
  test('sizes keep one decimal and drop a trailing .0', () {
    expect(Fmt.size(110860000000), '110.9 GB');
    expect(Fmt.size(4000000000), '4 GB');
    expect(Fmt.size(2500000), '2.5 MB');
    expect(Fmt.size(12000000), '12 MB');
    expect(Fmt.size(1500), '2 KB');
    expect(Fmt.size(512), '512 B');
  });
}

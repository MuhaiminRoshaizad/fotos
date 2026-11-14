import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/video_editor/presentation/editor_controls.dart';

void main() {
  test('typed times read as hours, minutes, seconds and tenths', () {
    expect(parseClock('30'), 30000);
    expect(parseClock('0:30'), 30000);
    expect(parseClock('1:30'), 90000);
    expect(parseClock('12:40'), 760000);
    expect(parseClock('1:02:30.5'), 3750500);
    expect(parseClock(' 0:07.9 '), 7900);
    expect(parseClock('1:75'), isNull);
    expect(parseClock('1::2'), isNull);
    expect(parseClock('abc'), isNull);
    expect(parseClock(''), isNull);
  });
}

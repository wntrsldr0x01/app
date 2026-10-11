import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_metadata.dart';

void main() {
  test('calendar interpretation preserves microseconds and labels UTC', () {
    final date = oeCalendarTime(1791720544409945)!;
    expect(date.isUtc, true);
    expect(date.microsecondsSinceEpoch, 1791720544409945);
    expect(oeDateLabel(1791720544409945), contains('clock interpretation'));
  });
  test('uptime and absent clocks do not become confident dates', () {
    expect(oeCalendarTime(null), isNull);
    expect(oeCalendarTime(1000000), isNull);
    expect(oeDateLabel(null), contains('unverified'));
    expect(oeEarLabel(0), 'Left ear');
    expect(oeEarLabel(1), 'Right ear');
    expect(oeEarLabel(9), 'Ear side unknown');
  });
}

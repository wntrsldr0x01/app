import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_pairing.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'oe_fixture.dart';

void main() {
  OeRecording recording(int side, int device, List<int> timestamps) {
    final bytes = oeFixture(timestamps: timestamps);
    ByteData.sublistView(bytes)
      ..setUint64(18, device, Endian.little)
      ..setUint8(26, side);
    return OeRecording.parse(bytes);
  }

  const start = 1791720544676608;
  test('Complementary devices and overlapping matching channels are candidates',
      () {
    final result = OePairing.assess(
      recording(0, 1, [start, start + 10000000]),
      recording(1, 2, [start + 1000, start + 10001000]),
    );
    expect(result.likelyConcurrent, isTrue);
    expect(result.matchingChannels, 2);
    expect(result.description, contains('not verified synchronization'));
  });
  test('Sequential recordings are not concurrent', () {
    final result = OePairing.assess(
      recording(0, 1, [start, start + 10000000]),
      recording(1, 2, [start + 20000000, start + 30000000]),
    );
    expect(result.likelyConcurrent, isFalse);
    expect(result.overlapSeconds, 0);
  });
  test('Same device, uptime clocks and backwards packets fail evidence check',
      () {
    for (final pair in [
      (
        recording(0, 1, [start, start + 1000]),
        recording(1, 1, [start, start + 1000])
      ),
      (recording(0, 1, [1000, 2000]), recording(1, 2, [1000, 2000])),
      (
        recording(0, 1, [start + 1000, start]),
        recording(1, 2, [start, start + 1000])
      ),
    ]) {
      expect(OePairing.assess(pair.$1, pair.$2).likelyConcurrent, isFalse);
    }
  });
}

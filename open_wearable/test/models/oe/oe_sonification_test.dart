import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_sonification.dart';

void main() {
  test('scaling preserves order and source; WAV records selected rate', () {
    final input = [-4.0, 2.0, 0.0, 4.0];
    final result = OeSonification.build(input, 24000, .5);
    final data = ByteData.sublistView(result.wav);
    expect(result.sourcePeak, 4);
    expect(result.frames, 4);
    expect(data.getUint32(24, Endian.little), 24000);
    expect(data.getUint32(40, Endian.little), 8);
    expect(
        [for (var i = 0; i < 4; i++) data.getInt16(44 + i * 2, Endian.little)],
        [-16384, 8192, 0, 16384],);
    expect(input, [-4, 2, 0, 4]);
  });
  test('zero and constant inputs retain DC; extreme finite inputs work', () {
    expect(
        OeSonification.build([0, 0], 8000, .25).wav.sublist(44), [0, 0, 0, 0],);
    expect(
        ByteData.sublistView(OeSonification.build([3, 3], 8000, .25).wav)
            .getInt16(44, Endian.little),
        8192,);
    expect(
        ByteData.sublistView(
                OeSonification.build([-1e308, 1e308], 8000, .5).wav,)
            .getInt16(44, Endian.little),
        -16384,);
  });
  test('invalid samples and settings are refused', () {
    for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(() => OeSonification.build([1, bad, 2], 8000, .5),
          throwsFormatException,);
    }
    expect(() => OeSonification.build([], 8000, .5), throwsArgumentError);
    expect(() => OeSonification.build([1], 0, .5), throwsArgumentError);
    expect(
        () => OeSonification.build([1], 8000, double.nan), throwsArgumentError,);
  });
}

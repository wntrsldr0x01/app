import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'oe_fixture.dart';

void main() {
  test(
      'prefix inspection preserves all bytes and stops without resynchronizing',
      () {
    final valid = oeFixture();
    final bytes = Uint8List.fromList(
      [...valid, 224, 255, ...List.filled(30, 255), ...valid],
    );
    expect(() => OeRecording.parse(bytes), throwsFormatException);
    final prefix = OeRecording.inspectPrefix(bytes);
    expect(prefix.bytes, bytes);
    expect(prefix.validatedBytes, valid.length);
    expect(prefix.incompleteReason, contains('undeclared sensor ID 224'));
    expect(
      prefix.sensors[2]!.frameCount,
      OeRecording.parse(valid).sensors[2]!.frameCount,
    );
    expect(
      prefix.wav(prefix.sensors[2]!, 0, 24000),
      OeRecording.parse(valid)
          .wav(OeRecording.parse(valid).sensors[2]!, 0, 24000),
    );
  });
  test(
      'exact duplicate tail opens with explicit provenance and unchanged bytes',
      () {
    final valid = oeFixture();
    final tail = valid.sublist(valid.length - 11);
    final bytes = Uint8List.fromList([...valid, ...tail]);
    final result = OeRecording.parse(bytes);
    expect(result.hasExactDuplicatedTail, isTrue);
    expect(result.validatedBytes, valid.length);
    expect(result.bytes, bytes);
  });
  test('metadata errors are never relaxed', () {
    expect(
      () => OeRecording.inspectPrefix(Uint8List.fromList([0, 0])),
      throwsFormatException,
    );
  });
  final source = Platform.environment['OE_DAMAGED_REFERENCE'];
  test(
    'private failing file stops at independently verified boundary',
    () {
      final bytes = File(source!).readAsBytesSync();
      final prefix = OeRecording.parse(bytes);
      expect(prefix.hasExactDuplicatedTail, isTrue);
      expect(
        prefix.digest,
        'e8283b30d386ac881d076eb0d70d6e1edc1195c9db6636d277a5952fa4e28f6f',
      );
      expect(prefix.validatedBytes, 29927339);
      expect(prefix.bytes.length - prefix.validatedBytes, 988);
      expect(
        prefix.sensors.values.fold<int>(0, (n, s) => n + s.packets.length),
        252888,
      );
      expect(prefix.bytes, bytes);
    },
    skip: source == null ? 'Private reference not supplied' : false,
  );
}

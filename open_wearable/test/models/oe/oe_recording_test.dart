import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/models/oe/oe_plot.dart';
import 'oe_fixture.dart';

void main() {
  test(
      'preserves byte identity, precise timestamps, device ID and original channel order',
      () {
    final bytes = oeFixture(), r = OeRecording.parse(bytes), s = r.sensors[2]!;
    expect(r.bytes, bytes);
    expect(r.digest, sha256.convert(bytes).toString());
    bytes[0] = 99;
    expect(r.bytes[0], 3);
    expect(() => r.bytes[0] = 99, throwsUnsupportedError);
    expect(r.deviceId, 'fedcba9876543210');
    expect(r.timestampUs, 1791720544676608);
    expect(s.components.map((c) => c.name), ['OUTER', 'INNER']);
    expect(s.headerDefaultRate, 48000);
    expect(s.frameCount, 4);
    expect(r.rawValue(s, s.packets.first, 0, 0), 32768);
    expect(r.value(s, s.packets.first, 0, 0), -32768);
    expect(r.value(s, s.packets.first, 0, 1), 32767);
    expect(r.value(s, s.packets.first, 1, 0), -1);
  });
  test('WAV is bit-exact mono and requires an explicit playback rate', () {
    final r = OeRecording.parse(oeFixture()), s = r.sensors[2]!;
    final wav = r.wav(s, 1, 24000), d = ByteData.sublistView(wav);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(d.getUint32(24, Endian.little), 24000);
    expect(d.getUint32(40, Endian.little), 8);
    expect(
      [for (var i = 44; i < wav.length; i += 2) d.getInt16(i, Endian.little)],
      [32767, 0, -456, -300],
    );
    expect(r.wav(s, 1, 48000).sublist(44), wav.sublist(44));
    expect(() => r.wav(s, 1, 0), throwsArgumentError);
  });
  test('keeps repeated/backwards timestamps and large gaps in file order', () {
    final r = OeRecording.parse(
      oeFixture(
        audio: [
          [1, 2],
          [3, 4],
          [5, 6],
          [7, 8],
        ],
        timestamps: [
          9000,
          9000,
          1000,
          9999999,
        ],
      ),
    );
    expect(
      r.sensors[2]!.packets.map((p) => p.timestampUs),
      [9000, 9000, 1000, 9999999],
    );
  });
  test('every partial header or packet is rejected, never silently recovered',
      () {
    final bytes = oeFixture();
    final r = OeRecording.parse(bytes);
    final boundaries = {
      r.sensors[2]!.packets[0].offset,
      r.sensors[2]!.packets[1].offset,
    };
    for (var n = 0; n < bytes.length; n++) {
      if (boundaries.contains(n)) {
        continue; // Valid record boundaries can end a file.
      }
      expect(
        () => OeRecording.parse(Uint8List.sublistView(bytes, 0, n)),
        throwsFormatException,
        reason: 'length $n',
      );
    }
  });
  test('rejects unknown version, unknown SID, incomplete PCM and extra bytes',
      () {
    final bytes = oeFixture();
    final first = OeRecording.parse(bytes).sensors[2]!.packets.first.offset;
    for (final change in [(0, 2), (first, 99), (first + 1, 7)]) {
      final b = Uint8List.fromList(bytes);
      b[change.$1] = change.$2;
      expect(() => OeRecording.parse(b), throwsFormatException);
    }
    expect(
      () => OeRecording.parse(Uint8List.fromList([...bytes, 0])),
      throwsFormatException,
    );
  });
  test('rejects microphone schemas with uncertain channel order', () {
    final bytes = oeFixture();
    final index = ascii.decode(bytes, allowInvalid: true).indexOf('OUTER');
    bytes[index] = 88;
    expect(() => OeRecording.parse(bytes), throwsFormatException);
  });
  test(
      'envelopes retain extrema including short spikes, and frame lookup is exact',
      () {
    final r = OeRecording.parse(oeFixture()), s = r.sensors[2]!;
    final p = OePlot.build(r, s, 0, 0, 4, maxBins: 1);
    expect(p.bins.single.min, -32768);
    expect(p.bins.single.max, 300);
    final zoom = OePlot.build(r, s, 1, 2, 4, maxBins: 2);
    expect(zoom.bins.map((b) => b.min), [-456, -300]);
    expect(r.packetForFrame(s, 2).firstFrame, 2);
  });
  test('decodes all declared non-audio types and preserves buffered delta', () {
    // Independent hand-built schema: int8,uint8,int16,uint16,int32,uint32,float,double.
    final base = oeFixture();
    final original = OeRecording.parse(base);
    final info = BytesBuilder()..add([1, 7]);
    final scheme = BytesBuilder()..add([7, 1, 83, 8]);
    for (var type = 0; type < 8; type++) {
      scheme.add([type, 1, 71, 1, 65 + type, 1, 85]);
    }
    scheme.add([0]);
    final sb = scheme.toBytes();
    info.add([sb.length, 0]);
    info.add(sb);
    final ib = info.toBytes(), header = Uint8List.fromList(base.sublist(0, 27));
    final h = ByteData.sublistView(header);
    h.setUint32(10, 27 + ib.length, Endian.little);
    h.setUint32(14, ib.length, Endian.little);
    final payload = ByteData(26)
      ..setInt8(0, -128)
      ..setUint8(1, 255)
      ..setInt16(2, -32768, Endian.little)
      ..setUint16(4, 65535, Endian.little)
      ..setInt32(6, -2147483648, Endian.little)
      ..setUint32(10, 4294967295, Endian.little)
      ..setFloat32(14, 1.25, Endian.little)
      ..setFloat64(18, -2.5, Endian.little);
    final packet = ByteData(10)
      ..setUint8(0, 7)
      ..setUint8(1, 54)
      ..setUint64(2, original.timestampUs, Endian.little);
    final r = OeRecording.parse(
      Uint8List.fromList([
        ...header,
        ...ib,
        ...packet.buffer.asUint8List(),
        ...payload.buffer.asUint8List(),
        ...payload.buffer.asUint8List(),
        0xe8,
        3,
      ]),
    );
    final s = r.sensors[7]!;
    expect(s.frameCount, 2);
    expect(s.packets.single.bufferedDeltaUs, 1000);
    expect(
      [for (var c = 0; c < 8; c++) r.value(s, s.packets.single, 1, c)],
      [-128, 255, -32768, 65535, -2147483648, 4294967295, 1.25, -2.5],
    );
  });
  final reference = Platform.environment['OE_REFERENCE_JSON'];
  test(
    'full user recording matches independent strict Python decoder, every PCM byte and timestamp',
    () {
      final m = jsonDecode(File(reference!).readAsStringSync())
          as Map<String, dynamic>;
      final r =
              OeRecording.parse(File(m['source'] as String).readAsBytesSync()),
          s = r.sensors[2]!;
      expect(r.digest, m['sha256']);
      expect(s.frameCount, m['frames']);
      expect(s.packets.length, m['packets']);
      for (var c = 0; c < 2; c++) {
        expect(
          sha256.convert(r.wav(s, c, 24000).sublist(44)).toString(),
          (m['pcm_sha256_outer_inner'] as List)[c],
        );
      }
      final time = ByteData(s.packets.length * 8);
      for (var i = 0; i < s.packets.length; i++) {
        time.setUint64(i * 8, s.packets[i].timestampUs, Endian.little);
      }
      expect(
        sha256.convert(time.buffer.asUint8List()).toString(),
        m['timestamps_sha256'],
      );
    },
    skip: reference == null
        ? 'Set OE_REFERENCE_JSON for private full-file verification'
        : false,
  );
}

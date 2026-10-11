import 'dart:convert';
import 'dart:typed_data';

/// Synthetic fixture, never a user's recording. Channel order is OUTER, INNER.
Uint8List oeFixture({List<List<int>>? audio, List<int>? timestamps}) {
  final header = BytesBuilder();
  final scheme = BytesBuilder()..add([2]);
  void text(String s) {
    final bytes = utf8.encode(s);
    scheme.add([bytes.length, ...bytes]);
  }

  text('Microphones');
  scheme.add([2]);
  for (final name in ['OUTER', 'INNER']) {
    scheme.add([3]);
    text('MICROPHONE');
    text(name);
    text('ADC');
  }
  scheme.add([0x12, 2, 1, 1]);
  final rates = ByteData(8)
    ..setFloat32(0, 24000, Endian.little)
    ..setFloat32(4, 48000, Endian.little);
  scheme.add(rates.buffer.asUint8List());
  final blob = scheme.toBytes();
  final info = BytesBuilder()
    ..add([1, 2, blob.length & 255, blob.length >> 8])
    ..add(blob);
  final metadata = info.toBytes();
  final fixed = ByteData(27)
    ..setUint16(0, 3, Endian.little)
    ..setUint64(2, 1791720544676608, Endian.little)
    ..setUint32(10, 27 + metadata.length, Endian.little)
    ..setUint32(14, metadata.length, Endian.little)
    ..setUint64(18, 0xfedcba9876543210, Endian.little)
    ..setUint8(26, 1);
  header.add(fixed.buffer.asUint8List());
  header.add(metadata);
  final samples = audio ??
      [
        [-32768, 32767, -1, 0],
        [123, -456, 300, -300],
      ];
  for (var i = 0; i < samples.length; i++) {
    final packet = ByteData(10 + samples[i].length * 2)
      ..setUint8(0, 2)
      ..setUint8(1, samples[i].length * 2)
      ..setUint64(
        2,
        timestamps?[i] ?? (1791720544676608 + i * 1000),
        Endian.little,
      );
    for (var j = 0; j < samples[i].length; j++) {
      packet.setInt16(10 + j * 2, samples[i][j], Endian.little);
    }
    header.add(packet.buffer.asUint8List());
  }
  return header.toBytes();
}

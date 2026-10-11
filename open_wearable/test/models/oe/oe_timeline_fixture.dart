import 'dart:convert';
import 'dart:typed_data';

/// Synthetic two-sensor timeline with recorded per-sample buffered intervals.
Uint8List timelineFixture({bool anomalies = false}) {
  final schemes = <Uint8List>[];
  for (final id in [0, 7]) {
    final s = BytesBuilder()..add([id]);
    void text(String value) {
      final b = utf8.encode(value);
      s.add([b.length, ...b]);
    }

    text(id == 0 ? 'IMU' : 'Bone');
    s.add([3]);
    for (final axis in ['X', 'Y', 'Z']) {
      s.add([id == 0 ? 6 : 2]);
      text('ACCELEROMETER');
      text(axis);
      text(id == 0 ? 'm/s^2' : 'g');
    }
    s.add([0]);
    schemes.add(s.toBytes());
  }
  final info = BytesBuilder()..add([2, 0, 7]);
  for (final schema in schemes) {
    info.add([schema.length & 255, schema.length >> 8]);
    info.add(schema);
  }
  final metadata = info.toBytes();
  final header = ByteData(27)
    ..setUint16(0, 3, Endian.little)
    ..setUint64(2, 1791720544000000, Endian.little)
    ..setUint32(10, 27 + metadata.length, Endian.little)
    ..setUint32(14, metadata.length, Endian.little);
  final output = BytesBuilder()
    ..add(header.buffer.asUint8List())
    ..add(metadata);
  void packet(int sid, int offset, List<num> values, {int? delta}) {
    final width = sid == 0 ? 4 : 2,
        size = values.length * (sid == 0 ? 4 : 2) + (delta == null ? 0 : 2);
    final data = ByteData(10 + size)
      ..setUint8(0, sid)
      ..setUint8(1, size)
      ..setUint64(2, 1791720544000000 + offset, Endian.little);
    for (var i = 0; i < values.length; i++) {
      if (sid == 0) {
        data.setFloat32(10 + i * width, values[i].toDouble(), Endian.little);
      } else {
        data.setInt16(10 + i * width, values[i].toInt(), Endian.little);
      }
    }
    if (delta != null) data.setUint16(10 + size - 2, delta, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  packet(0, 0, [1, 2, 3]);
  packet(7, 0, [10, 20, 30, 11, 21, 31, 12, 22, 32], delta: 1000);
  packet(0, 2000, [4, 5, anomalies ? double.nan : 6]);
  packet(0, anomalies ? 2000 : 4000, [7, 8, 9]);
  if (anomalies) {
    packet(0, 1000, [10, 11, 12]);
    packet(0, 4000, [13, 14, 15]);
    packet(0, 100000, [16, 17, 18]);
  }
  return output.toBytes();
}

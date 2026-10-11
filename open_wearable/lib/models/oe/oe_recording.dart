import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Strict, lossless index of a self-describing OE v3 file.
///
/// The original bytes and integer packet timestamps are retained. No repair,
/// resynchronization, interpolation, calibration or rate inference is applied.
class OeRecording {
  final Uint8List bytes;
  final String digest;
  final int timestampUs;
  final String deviceId;
  final int side;
  final Map<int, OeSensor> sensors;

  OeRecording._(
    this.bytes,
    this.digest,
    this.timestampUs,
    this.deviceId,
    this.side,
    this.sensors,
  );

  static const maxFileBytes = 128 * 1024 * 1024;

  /// Rejects incomplete, ambiguous or unsupported records with a byte offset.
  static OeRecording parse(Uint8List source) {
    if (source.length > maxFileBytes) {
      throw const FormatException(
        'Files larger than 128 MiB are not supported.',
      );
    }
    final bytes = Uint8List.fromList(source).asUnmodifiableView();
    final r = _Reader(bytes);
    final version = r.u16();
    if (version != 3) {
      throw FormatException(
        'OE version $version is unsupported. Only self-describing v3 logs are accepted; legacy layouts are not guessed.',
        null,
        0,
      );
    }
    final timestamp = r.timestamp();
    final headerSize = r.u32();
    final infoSize = r.u32();
    final deviceLow = r.u32();
    final deviceHigh = r.u32();
    final device =
        '${deviceHigh.toRadixString(16).padLeft(8, '0')}${deviceLow.toRadixString(16).padLeft(8, '0')}';
    final side = r.u8();
    if (headerSize < 27 ||
        infoSize != headerSize - 27 ||
        headerSize > bytes.length) {
      r.fail('Invalid header or ParseInfo length');
    }
    final info = r.section(infoSize);
    final count = info.u8();
    final ids = List.generate(count, (_) => info.u8());
    if (ids.toSet().length != ids.length) info.fail('Duplicate sensor IDs');
    final sensors = <int, OeSensor>{};
    for (final id in ids) {
      final scheme = info.section(info.u16());
      if (scheme.u8() != id) scheme.fail('Sensor ID disagrees with scheme');
      final name = scheme.text();
      final components = <OeComponent>[];
      final componentCount = scheme.u8();
      if (componentCount == 0) scheme.fail('Empty sensor scheme');
      var frameSize = 0;
      for (var c = 0; c < componentCount; c++) {
        final type = scheme.u8();
        if (type > 7) scheme.fail('Unsupported numeric type $type');
        final component = OeComponent(
          type,
          scheme.text(),
          scheme.text(),
          scheme.text(),
          frameSize,
        );
        frameSize += component.width;
        components.add(component);
      }
      final options = scheme.u8();
      final frequencies = <double>[];
      double? defaultRate;
      if (options & 0x10 != 0) {
        final n = scheme.u8();
        final defaultIndex = scheme.u8();
        final maxBleIndex = scheme.u8();
        if (n == 0 || defaultIndex >= n || maxBleIndex >= n) {
          scheme.fail('Invalid frequency indices');
        }
        for (var i = 0; i < n; i++) {
          final rate = scheme.number(6).toDouble();
          if (!rate.isFinite || rate <= 0) {
            scheme.fail('Invalid frequency option');
          }
          frequencies.add(rate);
        }
        defaultRate = frequencies[defaultIndex];
      }
      scheme.end();
      // Firmware SID 2 has special PCM framing. Fail closed if its schema changes.
      final pcm = id == 2;
      if (pcm &&
          (components.length != 2 ||
              components[0].group != 'MICROPHONE' ||
              components[1].group != 'MICROPHONE' ||
              components[0].name != 'OUTER' ||
              components[1].name != 'INNER' ||
              components.any((c) => c.type != 3 && c.type != 2))) {
        scheme.fail('Unrecognized microphone channel layout');
      }
      sensors[id] = OeSensor(
        id,
        name,
        List.unmodifiable(components),
        frameSize,
        pcm,
        List.unmodifiable(frequencies),
        defaultRate,
      );
    }
    info.end();
    while (r.remaining > 0) {
      final offset = r.offset;
      r.require(10);
      final sid = r.u8();
      final size = r.u8();
      final time = r.timestamp();
      final sensor = sensors[sid];
      if (sensor == null) r.fail('Packet references unknown sensor $sid');
      if (size == 0) r.fail('Empty packet');
      r.require(size);
      var dataSize = size;
      int? delta;
      if (sensor.isPcm) {
        if (size % sensor.frameSize != 0) r.fail('Incomplete stereo PCM frame');
      } else if (size != sensor.frameSize) {
        if (size < sensor.frameSize + 2 || (size - 2) % sensor.frameSize != 0) {
          r.fail('Payload length disagrees with sensor scheme');
        }
        dataSize -= 2;
        delta = r.data.getUint16(r.offset + dataSize, Endian.little);
      }
      final frames = dataSize ~/ sensor.frameSize;
      sensor._packets.add(
        OePacket(offset, r.offset, time, frames, sensor.frameCount, delta),
      );
      sensor._frameCount += frames;
      r.offset += size;
    }
    return OeRecording._(
      bytes,
      sha256.convert(bytes).toString(),
      timestamp,
      device,
      side,
      Map.unmodifiable(sensors),
    );
  }

  /// Original numeric word. Microphone header uint16 values remain accessible.
  num rawValue(OeSensor sensor, OePacket packet, int frame, int channel) {
    if (frame < 0 ||
        frame >= packet.frames ||
        channel < 0 ||
        channel >= sensor.components.length) {
      throw RangeError('Sample or channel outside packet');
    }
    final c = sensor.components[channel];
    final r = _Reader(
      bytes,
      packet.payloadOffset + frame * sensor.frameSize + c.offset,
    );
    return r.number(c.type);
  }

  /// Firmware PCM interpretation, with unchanged bits and explicit signedness.
  num value(OeSensor sensor, OePacket packet, int frame, int channel) {
    final raw = rawValue(sensor, packet, frame, channel);
    return sensor.isPcm && raw > 32767 ? raw.toInt() - 65536 : raw;
  }

  /// Find the packet containing an exact, zero-based frame index.
  OePacket packetForFrame(OeSensor sensor, int frame) {
    if (frame < 0 || frame >= sensor.frameCount) {
      throw RangeError.index(frame, sensor.packets);
    }
    var low = 0;
    var high = sensor.packets.length;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (sensor.packets[mid].firstFrame <= frame) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return sensor.packets[low];
  }

  /// Derived WAV: explicit user rate; original mono PCM bits in packet order.
  /// Packet gaps are NOT filled and timestamps are NOT represented in a WAV.
  Uint8List wav(OeSensor sensor, int channel, int rate) {
    if (!sensor.isPcm ||
        channel < 0 ||
        channel >= 2 ||
        rate < 1 ||
        rate > 192000) {
      throw ArgumentError(
        'WAV requires a known PCM channel and rate 1–192000 Hz',
      );
    }
    final output = Uint8List(44 + sensor.frameCount * 2);
    final d = ByteData.sublistView(output);
    void text(int pos, String s) =>
        output.setRange(pos, pos + s.length, ascii.encode(s));
    text(0, 'RIFF');
    d.setUint32(4, output.length - 8, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);
    d.setUint16(22, 1, Endian.little);
    d.setUint32(24, rate, Endian.little);
    d.setUint32(28, rate * 2, Endian.little);
    d.setUint16(32, 2, Endian.little);
    d.setUint16(34, 16, Endian.little);
    text(36, 'data');
    d.setUint32(40, output.length - 44, Endian.little);
    var pos = 44;
    for (final p in sensor.packets) {
      for (var f = 0; f < p.frames; f++) {
        final src = p.payloadOffset +
            f * sensor.frameSize +
            sensor.components[channel].offset;
        output[pos++] = bytes[src];
        output[pos++] = bytes[src + 1];
      }
    }
    return output;
  }
}

/// Schema labels and units come verbatim from the file, without calibration.
class OeComponent {
  final int type;
  final String group, name, unit;
  final int offset;
  const OeComponent(this.type, this.group, this.name, this.unit, this.offset);
  int get width => const [1, 1, 2, 2, 4, 4, 4, 8][type];
  String get typeName => const [
        'int8',
        'uint8',
        'int16',
        'uint16',
        'int32',
        'uint32',
        'float32',
        'float64',
      ][type];
  String get label => '$group.$name';
}

/// Indexed packets avoid expanding millions of samples into boxed values.
class OeSensor {
  final int id;
  final String name;
  final List<OeComponent> components;
  final int frameSize;
  final bool isPcm;
  final List<double> availableRates;
  final double? headerDefaultRate;
  final List<OePacket> _packets = [];
  int _frameCount = 0;
  int get frameCount => _frameCount;
  OeSensor(
    this.id,
    this.name,
    this.components,
    this.frameSize,
    this.isPcm,
    this.availableRates,
    this.headerDefaultRate,
  );
  List<OePacket> get packets => UnmodifiableListView(_packets);
}

/// Exact packet coordinates. Delta is retained without inventing sample times.
class OePacket {
  final int offset, payloadOffset, timestampUs, frames, firstFrame;
  final int? bufferedDeltaUs;
  const OePacket(
    this.offset,
    this.payloadOffset,
    this.timestampUs,
    this.frames,
    this.firstFrame,
    this.bufferedDeltaUs,
  );
}

class _Reader {
  final Uint8List bytes;
  late final ByteData data = ByteData.sublistView(bytes);
  int offset;
  final int limit;
  _Reader(this.bytes, [this.offset = 0, int? limit])
      : limit = limit ?? bytes.length;
  int get remaining => limit - offset;
  Never fail(String message) => throw FormatException(message, null, offset);
  void require(int n) {
    if (n < 0 || n > remaining) {
      fail('Truncated data: need $n bytes, have $remaining');
    }
  }

  void end() {
    if (remaining != 0) fail('Unexpected trailing metadata');
  }

  int u8() {
    require(1);
    return data.getUint8(offset++);
  }

  int u16() {
    require(2);
    final v = data.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int u32() {
    require(4);
    final v = data.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int timestamp() {
    final low = u32(), high = u32();
    // Exact on both native Dart and JavaScript. Never silently round uint64.
    if (high > 0x1fffff) {
      fail('Timestamp exceeds exact cross-platform integer range');
    }
    return high * 4294967296 + low;
  }

  _Reader section(int n) {
    require(n);
    final part = _Reader(bytes, offset, offset + n);
    offset += n;
    return part;
  }

  String text() {
    final n = u8();
    require(n);
    final result =
        utf8.decode(bytes.sublist(offset, offset + n), allowMalformed: false);
    offset += n;
    return result;
  }

  num number(int type) {
    final width = const [1, 1, 2, 2, 4, 4, 4, 8][type];
    require(width);
    final pos = offset;
    offset += width;
    return switch (type) {
      0 => data.getInt8(pos),
      1 => data.getUint8(pos),
      2 => data.getInt16(pos, Endian.little),
      3 => data.getUint16(pos, Endian.little),
      4 => data.getInt32(pos, Endian.little),
      5 => data.getUint32(pos, Endian.little),
      6 => data.getFloat32(pos, Endian.little),
      _ => data.getFloat64(pos, Endian.little),
    };
  }
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'oe_recording.dart';

/// Absolute integer device timestamps are subtracted before conversion to
/// seconds. Audio frames share their containing packet's timestamp: no audio
/// rate, timestamp interpolation, or gap repair is inferred. For buffered
/// non-audio data, match the official decoder convention: first sample at
/// packet timestamp + delta, subsequent samples at successive deltas.
int oeFrameTime(OeSensor sensor, OePacket packet, int frame) =>
    packet.timestampUs +
    (sensor.isPcm ? 0 : (frame + 1) * (packet.bufferedDeltaUs ?? 0));

class OeTimelineBounds {
  final int originUs, endUs;
  final Map<int, OeTimingSummary> sensors;
  OeTimelineBounds(this.originUs, this.endUs, this.sensors);
  double get seconds => (endUs - originUs) / 1e6;

  factory OeTimelineBounds.fromRecording(OeRecording r) {
    int? first, last;
    final summaries = <int, OeTimingSummary>{};
    for (final sensor in r.sensors.values.where((s) => s.frameCount > 0)) {
      final intervals = <int>[];
      var backwards = 0, repeated = 0;
      int? previous, minimum, maximum;
      var buffered = false;
      for (final p in sensor.packets) {
        final end = oeFrameTime(sensor, p, p.frames - 1);
        minimum =
            minimum == null ? p.timestampUs : math.min(minimum, p.timestampUs);
        maximum = maximum == null ? end : math.max(maximum, end);
        buffered |= !sensor.isPcm && p.frames > 1;
        if (previous != null) {
          final delta = p.timestampUs - previous;
          if (delta < 0) backwards++;
          if (delta == 0) repeated++;
          if (delta > 0) intervals.add(delta);
        }
        previous = p.timestampUs;
      }
      intervals.sort();
      final median =
          intervals.isEmpty ? null : intervals[intervals.length ~/ 2];
      summaries[sensor.id] = OeTimingSummary(
          minimum!, maximum!, median, backwards, repeated, buffered,);
      first = first == null ? minimum : math.min(first, minimum);
      last = last == null ? maximum : math.max(last, maximum);
    }
    return OeTimelineBounds(
        first ?? r.timestampUs, last ?? r.timestampUs, summaries,);
  }
}

class OeTimingSummary {
  final int firstUs, lastUs;
  final int? medianPositivePacketIntervalUs;
  final int backwards, repeated;
  final bool buffered;
  OeTimingSummary(
      this.firstUs,
      this.lastUs,
      this.medianPositivePacketIntervalUs,
      this.backwards,
      this.repeated,
      this.buffered,);
}

class OeTimeBin {
  final int index;
  int count = 0;
  double min = double.infinity, max = double.negativeInfinity;
  int firstFrame = 0, lastFrame = 0, firstTimeUs = 0;
  num firstValue = 0;
  OeTimeBin(this.index);
  void add(num value, int frame, int timeUs) {
    if (count == 0) {
      firstFrame = frame;
      firstTimeUs = timeUs;
      firstValue = value;
    }
    count++;
    lastFrame = frame;
    min = math.min(min, value.toDouble());
    max = math.max(max, value.toDouble());
  }
}

class OeTimeSeries {
  final int sensorId, channel;
  final List<OeTimeBin> bins;
  final int finiteCount, nonFiniteCount;
  final double min, max;
  OeTimeSeries(this.sensorId, this.channel, this.bins, this.finiteCount,
      this.nonFiniteCount, this.min, this.max,);
  String get key => '$sensorId:$channel';
}

class OeTimeJump {
  final int sensorId;
  final double fromSeconds, toSeconds;
  OeTimeJump(this.sensorId, this.fromSeconds, this.toSeconds);
}

class OeTimelinePlot {
  final double startSeconds, endSeconds;
  final int binCount;
  final List<OeTimeSeries> series;
  final List<OeTimeJump> jumps;
  OeTimelinePlot(this.startSeconds, this.endSeconds, this.binCount, this.series,
      this.jumps,);
}

class OeTimelineRequest {
  final OeRecording recording;
  final OeTimelineBounds bounds;
  final Set<String> channels;
  final double startSeconds, endSeconds;
  final int bins;
  OeTimelineRequest(this.recording, this.bounds, this.channels,
      this.startSeconds, this.endSeconds,
      {this.bins = 900,});
}

/// All finite source values in the visible interval contribute to exact
/// min/max envelopes. No decimation by stride or averaging. Empty time bins
/// stay empty, and input sample order is never changed.
OeTimelinePlot buildOeTimeline(OeTimelineRequest request) {
  final r = request.recording, bounds = request.bounds;
  final start = request.startSeconds, end = request.endSeconds;
  if (!start.isFinite || !end.isFinite || end <= start || request.bins < 1) {
    throw ArgumentError('Invalid timeline window');
  }
  final data = ByteData.sublistView(r.bytes);
  final result = <OeTimeSeries>[];
  final jumps = <OeTimeJump>[];
  for (final sensor in r.sensors.values) {
    final channels = [
      for (var c = 0; c < sensor.components.length; c++)
        if (request.channels.contains('${sensor.id}:$c')) c,
    ];
    if (channels.isEmpty || sensor.frameCount == 0) continue;
    final buffers = {for (final c in channels) c: <int, OeTimeBin>{}};
    final counts = {for (final c in channels) c: 0};
    final invalid = {for (final c in channels) c: 0};
    final median = bounds.sensors[sensor.id]?.medianPositivePacketIntervalUs;
    int? previousTime, previousEnd;
    for (final packet in sensor.packets) {
      final packetStart = (packet.timestampUs - bounds.originUs) / 1e6;
      final packetEnd =
          (oeFrameTime(sensor, packet, packet.frames - 1) - bounds.originUs) /
              1e6;
      if (previousTime != null &&
          median != null &&
          packet.timestampUs - previousTime > median * 5 &&
          packetStart >= start &&
          (previousEnd! - bounds.originUs) / 1e6 <= end) {
        jumps.add(OeTimeJump(
            sensor.id, (previousEnd - bounds.originUs) / 1e6, packetStart,),);
      }
      previousTime = packet.timestampUs;
      previousEnd = oeFrameTime(sensor, packet, packet.frames - 1);
      if (packetEnd < start || packetStart > end) continue;
      for (var f = 0; f < packet.frames; f++) {
        final time = oeFrameTime(sensor, packet, f);
        final x = (time - bounds.originUs) / 1e6;
        if (x < start || x > end) continue;
        final bin = (((x - start) / (end - start)) * request.bins)
            .floor()
            .clamp(0, request.bins - 1);
        for (final c in channels) {
          final component = sensor.components[c];
          final offset =
              packet.payloadOffset + f * sensor.frameSize + component.offset;
          final value = sensor.isPcm
              ? data.getInt16(offset, Endian.little)
              : _number(data, offset, component.type);
          if (!value.isFinite) {
            invalid[c] = invalid[c]! + 1;
            continue;
          }
          final accumulator =
              buffers[c]!.putIfAbsent(bin, () => OeTimeBin(bin));
          accumulator.add(value, packet.firstFrame + f, time);
          counts[c] = counts[c]! + 1;
        }
      }
    }
    for (final c in channels) {
      final bins = buffers[c]!.values.toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      var low = double.infinity, high = double.negativeInfinity;
      for (final b in bins) {
        low = math.min(low, b.min);
        high = math.max(high, b.max);
      }
      result.add(
          OeTimeSeries(sensor.id, c, bins, counts[c]!, invalid[c]!, low, high),);
    }
  }
  return OeTimelinePlot(start, end, request.bins, result, jumps);
}

num _number(ByteData d, int offset, int type) => switch (type) {
      0 => d.getInt8(offset),
      1 => d.getUint8(offset),
      2 => d.getInt16(offset, Endian.little),
      3 => d.getUint16(offset, Endian.little),
      4 => d.getInt32(offset, Endian.little),
      5 => d.getUint32(offset, Endian.little),
      6 => d.getFloat32(offset, Endian.little),
      _ => d.getFloat64(offset, Endian.little),
    };

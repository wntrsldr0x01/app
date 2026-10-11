import 'dart:math' as math;
import 'oe_recording.dart';

/// One plotted range with exact extrema; never an average or filtered sample.
class OeBin {
  final int firstFrame, lastFrame;
  final double min, max;
  const OeBin(this.firstFrame, this.lastFrame, this.min, this.max);
}

/// Plot data includes every finite value in the requested sample interval.
class OePlot {
  final List<OeBin> bins;
  final double min, max;
  final int nonFiniteCount;
  const OePlot(this.bins, this.min, this.max, this.nonFiniteCount);

  static OePlot build(
    OeRecording recording,
    OeSensor sensor,
    int channel,
    int start,
    int end, {
    int maxBins = 600,
  }) {
    if (start < 0 || end > sensor.frameCount || start >= end || maxBins < 1) {
      throw ArgumentError('Invalid plot range');
    }
    final width = math.max(1, ((end - start) / maxBins).ceil());
    final bins = <OeBin>[];
    var nonFinite = 0;
    var minimum = double.infinity, maximum = double.negativeInfinity;
    var lo = double.infinity, hi = double.negativeInfinity;
    var binStart = start;
    for (final p in sensor.packets) {
      if (p.firstFrame + p.frames <= start) continue;
      if (p.firstFrame >= end) break;
      for (var f = math.max(0, start - p.firstFrame);
          f < math.min(p.frames, end - p.firstFrame);
          f++) {
        final index = p.firstFrame + f;
        final value = recording.value(sensor, p, f, channel).toDouble();
        if (value.isFinite) {
          lo = math.min(lo, value);
          hi = math.max(hi, value);
          minimum = math.min(minimum, value);
          maximum = math.max(maximum, value);
        } else {
          nonFinite++;
        }
        if (index == end - 1 || index - binStart + 1 == width) {
          if (lo.isFinite) bins.add(OeBin(binStart, index, lo, hi));
          binStart = index + 1;
          lo = double.infinity;
          hi = double.negativeInfinity;
        }
      }
    }
    return OePlot(bins, minimum, maximum, nonFinite);
  }
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'oe_recording.dart';
import 'oe_timeline.dart';

class OeSpectrumRequest {
  final OeRecording recording;
  final int sensorId, channel, firstFrame, fftSize, windows;
  final double rate;
  final bool removeMean, mel, spectrogram;
  const OeSpectrumRequest(
    this.recording,
    this.sensorId,
    this.channel,
    this.firstFrame,
    this.fftSize,
    this.windows,
    this.rate, {
    this.removeMean = true,
    this.mel = false,
    this.spectrogram = false,
  });
}

class OeSpectrumResult {
  final List<double> psd;
  final List<List<double>> melDb;
  final List<List<double>> spectrogramDb;
  final List<double> melCenters;
  final int samples, hop, irregularIntervals;
  final double minIntervalUs, maxIntervalUs;
  OeSpectrumResult(
    this.psd,
    this.melDb,
    this.melCenters,
    this.samples,
    this.hop,
    this.irregularIntervals,
    this.minIntervalUs,
    this.maxIntervalUs, {
    this.spectrogramDb = const [],
  });
}

/// Radix-2 DFT, unnormalized, negative exponent. Kept independent of UI.
List<double> oePeriodogram(
  List<double> values,
  double rate, {
  bool removeMean = true,
}) {
  final n = values.length;
  if (n < 2 ||
      (n & (n - 1)) != 0 ||
      !rate.isFinite ||
      rate <= 0 ||
      values.any((v) => !v.isFinite)) {
    throw ArgumentError(
      'FFT needs finite samples, a power-of-two length and positive rate',
    );
  }
  final re = Float64List(n), im = Float64List(n);
  final mean = removeMean ? values.reduce((a, b) => a + b) / n : 0.0;
  var energy = 0.0;
  for (var i = 0; i < n; i++) {
    final w = .5 - .5 * math.cos(2 * math.pi * i / n); // periodic Hann
    re[i] = (values[i] - mean) * w;
    energy += w * w;
  }
  for (int i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final t = re[i];
      re[i] = re[j];
      re[j] = t;
    }
  }
  for (var length = 2; length <= n; length <<= 1) {
    final angle = -2 * math.pi / length;
    for (var base = 0; base < n; base += length) {
      for (var j = 0; j < length ~/ 2; j++) {
        final a = base + j, b = a + length ~/ 2;
        final wr = math.cos(angle * j), wi = math.sin(angle * j);
        final tr = wr * re[b] - wi * im[b], ti = wr * im[b] + wi * re[b];
        re[b] = re[a] - tr;
        im[b] = im[a] - ti;
        re[a] += tr;
        im[a] += ti;
      }
    }
  }
  return List.generate(
    n ~/ 2 + 1,
    (k) =>
        (re[k] * re[k] + im[k] * im[k]) /
        (rate * energy) *
        (k == 0 || k == n ~/ 2 ? 1 : 2),
  );
}

double oeMel(double hz) => 2595 * math.log(1 + hz / 700) / math.ln10;
double oeMelHz(double mel) => 700 * (math.pow(10, mel / 2595) - 1);

/// HTK mel-spaced, unit-height triangular filters; integrate one-sided PSD
/// with df to obtain weighted band power in native units squared.
List<double> oeMelPower(
  List<double> psd,
  double rate,
  int n, {
  int bands = 64,
}) {
  final edges = List.generate(
    bands + 2,
    (i) => oeMelHz(oeMel(rate / 2) * i / (bands + 1)),
  );
  return List.generate(bands, (b) {
    var power = 0.0;
    for (var k = 0; k < psd.length; k++) {
      final hz = k * rate / n;
      final weight = math.max(
        0.0,
        math.min(
          (hz - edges[b]) / (edges[b + 1] - edges[b]),
          (edges[b + 2] - hz) / (edges[b + 2] - edges[b + 1]),
        ),
      );
      power += psd[k] * weight * rate / n;
    }
    return power;
  });
}

OeSpectrumResult buildOeSpectrum(OeSpectrumRequest q) {
  final sensor = q.recording.sensors[q.sensorId]!;
  final n = q.fftSize, hop = n ~/ 4;
  if (n < 32 ||
      n > 32768 ||
      (n & (n - 1)) != 0 ||
      q.windows < 1 ||
      q.windows > 512 ||
      (q.spectrogram && n > 4096) ||
      !q.rate.isFinite ||
      q.rate <= 0 ||
      q.rate > 1000000 ||
      q.channel < 0 ||
      q.channel >= sensor.components.length ||
      (q.mel && !sensor.isPcm)) {
    throw ArgumentError('Invalid spectrum settings');
  }
  final count = n + ((q.mel || q.spectrogram) ? q.windows - 1 : 0) * hop;
  if (q.firstFrame < 0 || q.firstFrame + count > sensor.frameCount) {
    throw ArgumentError(
      'Selected interval exceeds the channel. Choose fewer windows, a smaller FFT, or an earlier start. No padding is added.',
    );
  }
  final values = <double>[];
  int? previous;
  var irregular = 0, minDt = double.infinity, maxDt = double.negativeInfinity;
  for (final packet in sensor.packets) {
    if (packet.firstFrame + packet.frames <= q.firstFrame) continue;
    if (packet.firstFrame >= q.firstFrame + count) break;
    for (var f = 0; f < packet.frames; f++) {
      final index = packet.firstFrame + f;
      if (index < q.firstFrame || index >= q.firstFrame + count) continue;
      final value = q.recording.value(sensor, packet, f, q.channel).toDouble();
      if (!value.isFinite) {
        throw FormatException(
          'Non-finite sample at frame $index. Analysis stopped; samples are not removed or repaired.',
        );
      }
      values.add(value);
      final time = oeFrameTime(sensor, packet, f);
      if (!sensor.isPcm && previous != null) {
        final dt = (time - previous).toDouble();
        minDt = math.min(minDt, dt);
        maxDt = math.max(maxDt, dt);
        if ((dt - 1e6 / q.rate).abs() > math.max(1.0, .01 * 1e6 / q.rate)) {
          irregular++;
        }
      }
      previous = time;
    }
  }
  final psd =
      oePeriodogram(values.sublist(0, n), q.rate, removeMean: q.removeMean);
  final mel = <List<double>>[];
  final spectrogram = <List<double>>[];
  if (q.mel || q.spectrogram) {
    for (var i = 0; i < q.windows; i++) {
      final p = oePeriodogram(
        values.sublist(i * hop, i * hop + n),
        q.rate,
        removeMean: q.removeMean,
      );
      if (q.spectrogram) {
        spectrogram.add(
          p.map((v) => 10 * math.log(math.max(1e-30, v)) / math.ln10).toList(),
        );
      }
      if (q.mel) {
        mel.add(
          oeMelPower(p, q.rate, n)
              .map((v) => 10 * math.log(math.max(1e-30, v)) / math.ln10)
              .toList(),
        );
      }
    }
  }
  if (psd.any((v) => !v.isFinite) ||
      mel.any((row) => row.any((v) => !v.isFinite)) ||
      spectrogram.any((row) => row.any((v) => !v.isFinite))) {
    throw const FormatException(
      'Numerical overflow in spectrum. No result displayed.',
    );
  }
  return OeSpectrumResult(
    psd,
    mel,
    List.generate(64, (i) => oeMelHz(oeMel(q.rate / 2) * (i + 1) / 65)),
    count,
    hop,
    irregular,
    minDt,
    maxDt,
    spectrogramDb: spectrogram,
  );
}

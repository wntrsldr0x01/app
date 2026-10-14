import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_spectrum.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'oe_fixture.dart';

void main() {
  test('Hann periodogram matches independent direct DFT in every bin', () {
    const n = 64, rate = 200.0;
    final x =
        List.generate(n, (i) => 2 + math.sin(i * .7) + .3 * math.cos(i * .13));
    final actual = oePeriodogram(x, rate);
    final mean = x.reduce((a, b) => a + b) / n;
    var energy = 0.0;
    final w = List.generate(n, (i) {
      final v = .5 - .5 * math.cos(2 * math.pi * i / n);
      energy += v * v;
      return v;
    });
    for (var k = 0; k <= n ~/ 2; k++) {
      var re = 0.0, im = 0.0;
      for (var i = 0; i < n; i++) {
        re += (x[i] - mean) * w[i] * math.cos(2 * math.pi * k * i / n);
        im -= (x[i] - mean) * w[i] * math.sin(2 * math.pi * k * i / n);
      }
      final expected = (re * re + im * im) /
          (rate * energy) *
          (k == 0 || k == n ~/ 2 ? 1 : 2);
      expect(actual[k], closeTo(expected, 1e-12));
    }
  });
  test('bin-centered sinusoid has correct frequency and integrated power', () {
    const n = 1024, rate = 1024.0;
    final psd = oePeriodogram(
      List.generate(n, (i) => 3 * math.sin(2 * math.pi * 64 * i / n)),
      rate,
    );
    expect(psd.indexOf(psd.reduce(math.max)), 64);
    expect(psd.reduce((a, b) => a + b) * rate / n, closeTo(4.5, 1e-10));
  });
  test('DC removal is optional; Nyquist not doubled; invalid values rejected',
      () {
    expect(oePeriodogram(List.filled(64, 3), 64).every((v) => v == 0), isTrue);
    final dc = oePeriodogram(List.filled(64, 3), 64, removeMean: false);
    expect(dc.reduce((a, b) => a + b), closeTo(9, 1e-10));
    final nyquist =
        oePeriodogram(List.generate(64, (i) => i.isEven ? 1.0 : -1.0), 64);
    expect(nyquist.reduce((a, b) => a + b), closeTo(1, 1e-10));
    expect(() => oePeriodogram([1, double.nan], 100), throwsArgumentError);
  });
  test(
      'mel filter weights match triangle at known frequency and scale linearly',
      () {
    const n = 1024, rate = 24000.0, k = 50;
    final p = List.filled(n ~/ 2 + 1, 0.0)..[k] = 2;
    final mel = oeMelPower(p, rate, n);
    for (var b = 0; b < 64; b++) {
      final l = oeMelHz(oeMel(rate / 2) * b / 65),
          m = oeMelHz(oeMel(rate / 2) * (b + 1) / 65),
          h = oeMelHz(oeMel(rate / 2) * (b + 2) / 65);
      final hz = k * rate / n;
      final weight = hz < l || hz > h
          ? 0.0
          : hz <= m
              ? (hz - l) / (m - l)
              : (h - hz) / (h - m);
      expect(mel[b], closeTo(2 * weight * rate / n, 1e-10));
    }
  });
  test('analysis reads signed original samples; no padding or source changes',
      () {
    final audio = List.generate(64, (i) => [i.isEven ? 32768 : 32767, i * 10]);
    final recording = OeRecording.parse(oeFixture(audio: audio));
    final before = recording.bytes.toList();
    final q = OeSpectrumRequest(recording, 2, 0, 3, 32, 3, 24000, mel: true);
    final r = buildOeSpectrum(q);
    final source =
        List.generate(32, (i) => (i + 3).isEven ? -32768.0 : 32767.0);
    expect(r.psd, oePeriodogram(source, 24000));
    expect(r.samples, 48);
    expect(r.melDb.length, 3);
    expect(r.hop, 8);
    expect(recording.bytes, before);
    expect(
      () => buildOeSpectrum(
        OeSpectrumRequest(recording, 2, 0, 40, 32, 1, 24000),
      ),
      throwsArgumentError,
    );
  });
  test('linear spectrogram preserves every STFT window and frequency bin', () {
    final audio = List.generate(
      96,
      (i) => [
        (10000 * math.sin(2 * math.pi * (i < 48 ? 4 : 10) * i / 32)).round() &
            0xffff,
        0,
      ],
    );
    final recording = OeRecording.parse(oeFixture(audio: audio));
    final result = buildOeSpectrum(
      OeSpectrumRequest(recording, 2, 0, 0, 32, 9, 3200, spectrogram: true),
    );
    expect(result.samples, 96);
    expect(result.spectrogramDb.length, 9);
    expect(result.spectrogramDb.first.length, 17);
    for (final window in [0, 8]) {
      final source = List.generate(32, (i) {
        final value = audio[window * 8 + i][0];
        return (value >= 32768 ? value - 65536 : value).toDouble();
      });
      final expected = oePeriodogram(source, 3200);
      for (var k = 0; k < expected.length; k++) {
        expect(
          result.spectrogramDb[window][k],
          closeTo(
            10 * math.log(math.max(1e-30, expected[k])) / math.ln10,
            1e-10,
          ),
        );
      }
    }
    expect(
      result.spectrogramDb.first
          .indexOf(result.spectrogramDb.first.reduce(math.max)),
      4,
    );
    expect(
      result.spectrogramDb.last
          .indexOf(result.spectrogramDb.last.reduce(math.max)),
      10,
    );
    expect(
      () => buildOeSpectrum(
        OeSpectrumRequest(
          recording,
          2,
          0,
          32,
          32,
          9,
          3200,
          spectrogram: true,
        ),
      ),
      throwsArgumentError,
    );
  });
  test('playback WAV contains only the analyzed range and chosen channel', () {
    final recording = OeRecording.parse(
        oeFixture(audio: List.generate(96, (i) => [i, 65535 - i])),);
    final wav = recording.wav(recording.sensors[2]!, 1, 24000,
        firstFrame: 8, frameCount: 48,);
    final data = ByteData.sublistView(wav);
    expect(wav.length, 44 + 48 * 2);
    expect(data.getUint32(24, Endian.little), 24000);
    expect(data.getUint32(40, Endian.little), 96);
    for (var i = 0; i < 48; i++) {
      expect(data.getInt16(44 + i * 2, Endian.little), -1 - (i + 8));
    }
    expect(
        () => recording.wav(recording.sensors[2]!, 0, 24000,
            firstFrame: 80, frameCount: 48,),
        throwsArgumentError,);
  });
  final reference = Platform.environment['OE_TIMELINE_REFERENCE'];
  test(
    'real recording: every channel FFT and microphone mel preserve source',
    () {
      final r = OeRecording.parse(File(reference!).readAsBytesSync());
      final digest = r.digest;
      for (final sensor
          in r.sensors.values.where((s) => s.frameCount >= 1024)) {
        for (var c = 0; c < sensor.components.length; c++) {
          final result = buildOeSpectrum(
            OeSpectrumRequest(
              r,
              sensor.id,
              c,
              0,
              1024,
              sensor.isPcm ? 128 : 1,
              sensor.isPcm ? 24000 : 100,
              mel: sensor.isPcm,
            ),
          );
          expect(result.psd.length, 513);
          expect(result.psd.every((v) => v.isFinite && v >= 0), isTrue);
          if (sensor.isPcm) expect(result.melDb.length, 128);
        }
      }
      expect(OeRecording.parse(r.bytes).digest, digest);
    },
    skip: reference == null,
  );
}

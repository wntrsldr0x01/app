import 'dart:typed_data';

/// Derived audio only. One source value becomes one PCM sample, without
/// resampling, DC removal or timestamp reconstruction.
class OeSonification {
  final Uint8List wav;
  final double sourcePeak;
  final int frames;
  OeSonification(this.wav, this.sourcePeak, this.frames);

  static OeSonification build(List<double> values, int rate, double level) {
    if (values.isEmpty ||
        rate < 8000 ||
        rate > 96000 ||
        !level.isFinite ||
        level <= 0 ||
        level > 1) {
      throw ArgumentError('Invalid sonification settings or empty channel.');
    }
    var peak = 0.0;
    for (final value in values) {
      if (!value.isFinite) {
        throw const FormatException(
            'Sonification refused: non-finite source value. No samples were skipped.',);
      }
      if (value.abs() > peak) peak = value.abs();
    }
    final bytes = Uint8List(44 + values.length * 2);
    final data = ByteData.sublistView(bytes);
    void tag(int offset, String text) =>
        bytes.setRange(offset, offset + 4, text.codeUnits);
    tag(0, 'RIFF');
    data.setUint32(4, bytes.length - 8, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    data.setUint32(40, values.length * 2, Endian.little);
    for (var i = 0; i < values.length; i++) {
      data.setInt16(
          44 + i * 2,
          peak == 0 ? 0 : ((values[i] / peak) * level * 32767).round(),
          Endian.little,);
    }
    return OeSonification(bytes, peak, values.length);
  }
}

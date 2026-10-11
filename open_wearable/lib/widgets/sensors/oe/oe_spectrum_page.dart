import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/models/oe/oe_spectrum.dart';

class OeSpectrumPage extends StatefulWidget {
  final OeRecording recording;
  final String name;
  final int sensorId, channel, firstFrame;
  const OeSpectrumPage(
      {super.key,
      required this.recording,
      required this.name,
      required this.sensorId,
      required this.channel,
      this.firstFrame = 0,});
  @override
  State<OeSpectrumPage> createState() => _OeSpectrumPageState();
}

class _OeSpectrumPageState extends State<OeSpectrumPage> {
  final _rate = TextEditingController(),
      _first = TextEditingController(),
      _windows = TextEditingController(text: '128');
  int _n = 1024;
  bool _mel = false, _removeMean = true, _accepted = false, _busy = false;
  String? _error;
  OeSpectrumResult? _result;
  OeSpectrumRequest? _request;
  Offset? _cursor;
  OeSensor get _sensor => widget.recording.sensors[widget.sensorId]!;
  @override
  void initState() {
    super.initState();
    _first.text = '${widget.firstFrame}';
    while (_n > 32 && _n > _sensor.frameCount - widget.firstFrame) {
      _n ~/= 2;
    }
  }

  @override
  void dispose() {
    _rate.dispose();
    _first.dispose();
    _windows.dispose();
    super.dispose();
  }

  void _invalidate() => setState(() {
        _result = null;
        _error = null;
        _cursor = null;
      });
  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final q = OeSpectrumRequest(
          widget.recording,
          widget.sensorId,
          widget.channel,
          int.parse(_first.text),
          _n,
          _mel ? int.parse(_windows.text) : 1,
          double.parse(_rate.text),
          removeMean: _removeMean,
          mel: _mel,);
      final result = await compute(buildOeSpectrum, q);
      if (mounted) {
        setState(() {
          _request = q;
          _result = result;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final q = _request!, r = _result!;
    final payload = {
      'source': widget.name,
      'sha256': widget.recording.digest,
      'partial_reason': widget.recording.incompleteReason,
      'sensor_id': q.sensorId,
      'channel': _sensor.components[q.channel].label,
      'unit': _sensor.isPcm
          ? 'signed PCM counts'
          : _sensor.components[q.channel].unit,
      'assumed_uniform_rate_hz': q.rate,
      'first_frame': q.firstFrame,
      'sample_count': r.samples,
      'fft_size': q.fftSize,
      'hop_samples': r.hop,
      'window': 'periodic Hann',
      'remove_mean_per_window': q.removeMean,
      'padding': 'none',
      'resampling': 'none',
      'fft':
          'one-sided PSD abs(FFT)^2 / (rate * sum(window^2)); interior bins doubled',
      'psd': r.psd,
      'frequency_step_hz': q.rate / q.fftSize,
      'mel':
          '64 HTK-spaced unit-height triangles, sum(PSD * weight * df); dB re 1 native unit squared; numerical floor -300 dB',
      'mel_centers_hz': r.melCenters,
      'mel_db_time_rows': r.melDb,
      'mel_first_center_seconds': (q.firstFrame + q.fftSize / 2) / q.rate,
      'mel_step_seconds': r.hop / q.rate,
      'non_pcm_intervals_outside_1percent_or_1us': r.irregularIntervals,
    };
    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
          files: [
            XFile.fromData(
                Uint8List.fromList(utf8.encode(
                    const JsonEncoder.withIndent('  ').convert(payload),),),
                mimeType: 'application/json',
                name: 'spectrum.json',),
          ],
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,),);
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result, q = _request;
    final unit =
        _sensor.isPcm ? 'PCM counts' : _sensor.components[widget.channel].unit;
    return Scaffold(
        appBar: AppBar(title: const Text('Frequency analysis'), actions: [
          IconButton(
              onPressed: r == null ? null : _export,
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export spectrum + analysis settings',),
        ],),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
              '${widget.name}\n${_sensor.name} · ${_sensor.components[widget.channel].label}',
              style: Theme.of(context).textTheme.titleMedium,),
          Text(
              '${_sensor.frameCount} original frames · SHA-256 ${widget.recording.digest.substring(0, 12)}…',),
          if (widget.recording.incompleteReason != null)
            Text('Source interpretation: ${widget.recording.incompleteReason}'),
          const SizedBox(height: 12),
          const Text(
              'Frequency is meaningful only for uniformly sampled data at the correct rate. Enter a rate explicitly; the header default is not evidence of the active recording rate. No resampling, gap filling, calibration, or source edits are performed.',),
          if (_sensor.isPcm)
            const Text(
                'Audio timing within packets is not stored. This analysis treats consecutive signed PCM samples as contiguous at your assumed rate; packet gaps are not repaired.',),
          const SizedBox(height: 18),
          Wrap(spacing: 16, runSpacing: 12, children: [
            SizedBox(
                width: 210,
                child: TextField(
                    controller: _rate,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                        labelText: 'Assumed sample rate (Hz)',),
                    onChanged: (_) => _invalidate(),),),
            SizedBox(
                width: 210,
                child: TextField(
                    controller: _first,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                        labelText: 'First frame (zero-based)',),
                    onChanged: (_) => _invalidate(),),),
            SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                    initialValue: _n,
                    decoration: const InputDecoration(labelText: 'FFT samples'),
                    items: [
                      for (final n in [
                        32,
                        64,
                        128,
                        256,
                        512,
                        1024,
                        2048,
                        4096,
                        8192,
                        16384,
                        32768,
                      ])
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) {
                            _n = v!;
                            _invalidate();
                          },),),
            if (_mel)
              SizedBox(
                  width: 200,
                  child: TextField(
                      controller: _windows,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                          labelText: 'STFT windows (1–512)',),
                      onChanged: (_) => _invalidate(),),),
          ],),
          if (_sensor.isPcm)
            SwitchListTile(
                title: const Text('Mel-spectrogram'),
                subtitle:
                    const Text('64 HTK mel bands · 75% overlap · no padding'),
                value: _mel,
                onChanged: _busy
                    ? null
                    : (v) {
                        _mel = v;
                        _invalidate();
                      },),
          SwitchListTile(
              title: const Text('Remove mean per analysis window'),
              value: _removeMean,
              onChanged: _busy
                  ? null
                  : (v) {
                      _removeMean = v;
                      _invalidate();
                    },),
          CheckboxListTile(
              title: const Text(
                  'Analyze sample order using my assumed uniform rate',),
              subtitle: const Text(
                  'Timestamp irregularities can make Hz interpretations misleading. This choice is an analysis assumption, not a change to the recording.',),
              value: _accepted,
              onChanged: _busy
                  ? null
                  : (v) {
                      _accepted = v!;
                      _invalidate();
                    },),
          FilledButton(
              onPressed: _busy || !_accepted ? null : _run,
              child: Text(_mel
                  ? 'Compute mel-spectrogram'
                  : 'Compute FFT power spectrum',),),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            SelectableText(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),),
          if (r != null && q != null) ...[
            const SizedBox(height: 16),
            Text(
                'Frames ${q.firstFrame}–${q.firstFrame + r.samples - 1} · ${r.samples} samples · ${(r.samples / q.rate).toStringAsFixed(6)} s at assumed ${q.rate} Hz\nPeriodic Hann · Δf ${(q.rate / q.fftSize).toStringAsFixed(4)} Hz · Nyquist ${q.rate / 2} Hz · mean removal ${q.removeMean ? "on" : "off"}',),
            if (!_sensor.isPcm)
              Text(
                  'Recorded/derived sample intervals: ${r.minIntervalUs}–${r.maxIntervalUs} µs. ${r.irregularIntervals} intervals differ from the assumed period by >1% or 1 µs. No time interpolation was performed.',
                  style: TextStyle(
                      color: r.irregularIntervals > 0
                          ? Theme.of(context).colorScheme.error
                          : null,),),
            Text(_mel
                ? 'Mel band power · dB re 1 ($unit)². Color scale: peak−80 dB to peak (not dB SPL). Time is derived from sample index / assumed rate. Each column represents a full Hann window; overlapping columns are placed at window centers.'
                : 'One-sided power spectral density · ($unit)²/Hz. Display: 10 log10(PSD), dB re 1 ($unit)²/Hz. This is one FFT window, not an average over the log.',),
            SizedBox(
                height: 360,
                child: LayoutBuilder(
                    builder: (context, constraints) => MouseRegion(
                          onHover: (event) => setState(() => _cursor = Offset(
                              ((event.localPosition.dx - 75) /
                                      math.max(1, constraints.maxWidth - 100))
                                  .clamp(0, 1),
                              ((event.localPosition.dy - 20) / 290)
                                  .clamp(0, 1),),),
                          child: CustomPaint(
                              size: Size(constraints.maxWidth, 360),
                              painter: _SpectrumPainter(r, q, _mel),),
                        ),),),
            if (_cursor != null) Text(_readout(r, q)),
          ],
        ],),);
  }

  String _readout(OeSpectrumResult r, OeSpectrumRequest q) {
    if (_mel) {
      final t =
          (_cursor!.dx * r.melDb.length).floor().clamp(0, r.melDb.length - 1);
      final b = ((1 - _cursor!.dy) * 64).floor().clamp(0, 63);
      return 'Window $t · center ${((q.firstFrame + t * r.hop + q.fftSize / 2) / q.rate).toStringAsFixed(6)} s · band center ${r.melCenters[b].toStringAsFixed(2)} Hz · ${r.melDb[t][b].toStringAsFixed(3)} dB';
    }
    final k = (_cursor!.dx * (r.psd.length - 1)).round();
    return 'Bin $k · ${(k * q.rate / q.fftSize).toStringAsFixed(4)} Hz · PSD ${r.psd[k].toStringAsPrecision(8)}';
  }
}

class _SpectrumPainter extends CustomPainter {
  final OeSpectrumResult r;
  final OeSpectrumRequest q;
  final bool mel;
  _SpectrumPainter(this.r, this.q, this.mel);
  void label(Canvas c, String s, Offset p) {
    final t = TextPainter(
        text: TextSpan(
            text: s,
            style: const TextStyle(color: Colors.black87, fontSize: 11),),
        textDirection: TextDirection.ltr,)
      ..layout();
    t.paint(c, p);
  }

  @override
  void paint(Canvas c, Size size) {
    final rect = Rect.fromLTWH(75, 20, math.max(1, size.width - 100), 290);
    c.drawRect(rect, Paint()..color = Colors.white);
    if (mel) {
      final peak = r.melDb.expand((v) => v).reduce(math.max), low = peak - 80;
      for (var t = 0; t < r.melDb.length; t++) {
        for (var b = 0; b < 64; b++) {
          final f = ((r.melDb[t][b] - low) / 80).clamp(0.0, 1.0);
          c.drawRect(
              Rect.fromLTRB(
                  rect.left + t / r.melDb.length * rect.width,
                  rect.bottom - (b + 1) / 64 * rect.height,
                  rect.left + (t + 1) / r.melDb.length * rect.width + .2,
                  rect.bottom - b / 64 * rect.height + .2,),
              Paint()
                ..isAntiAlias = false
                ..color = Color.lerp(
                    const Color(0xFF120B35), const Color(0xFFFFD54F), f,)!,);
        }
      }
      label(
          c,
          'Color: ${low.toStringAsFixed(1)} → ${peak.toStringAsFixed(1)} dB',
          const Offset(75, 0),);
      for (var i = 0; i <= 4; i++) {
        final f = i / 4;
        label(c, '${oeMelHz(oeMel(q.rate / 2) * (.5 + f * 64) / 65).toStringAsFixed(0)} Hz',
            Offset(0, rect.bottom - f * rect.height - 6),);
        final center = (q.firstFrame +
                q.fftSize / 2 +
                (f * r.melDb.length - .5) * r.hop) /
            q.rate;
        label(c, '${center.toStringAsFixed(3)} s',
            Offset(rect.left + f * (rect.width - 45), rect.bottom + 10),);
      }
    } else {
      final db = r.psd
          .map((v) => 10 * math.log(math.max(v, 1e-30)) / math.ln10)
          .toList();
      final high = db.reduce(math.max) + 3, low = db.reduce(math.max) - 100;
      final path = Path();
      for (var k = 0; k < db.length; k++) {
        final x = rect.left + k / (db.length - 1) * rect.width,
            y = rect.bottom -
                ((db[k] - low) / (high - low)).clamp(0, 1) * rect.height;
        if (k == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      c.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF0072B2)
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke,);
      for (var i = 0; i <= 4; i++) {
        final f = i / 4;
        label(c, '${(low + f * (high - low)).toStringAsFixed(1)} dB',
            Offset(0, rect.bottom - f * rect.height - 6),);
        label(c, '${(f * q.rate / 2).toStringAsFixed(1)} Hz',
            Offset(rect.left + f * (rect.width - 50), rect.bottom + 10),);
      }
      label(c, 'Display floor: peak−100 dB; export retains full PSD',
          const Offset(75, 340),);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) =>
      old.r != r || old.mel != mel;
}

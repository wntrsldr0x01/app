import 'dart:convert';
import 'dart:async';
import 'oe_sonification_panel.dart';
import 'oe_log_info.dart';
import 'oe_timeline_page.dart';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_wearable/models/oe/oe_plot.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';

/// Inspect original values and packet timing without choosing an audio rate.
class OeViewerPage extends StatefulWidget {
  final String name;
  final OeRecording recording;
  const OeViewerPage({super.key, required this.name, required this.recording});
  @override
  State<OeViewerPage> createState() => _OeViewerPageState();
}

class _OeViewerPageState extends State<OeViewerPage> {
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _audioSubscriptions = [];
  PlayerState _audioState = PlayerState.stopped;
  Duration _audioPosition = Duration.zero;
  double _volume = 1;
  int? _hoverFrame;

  AudioPlayer _ensurePlayer() {
    if (_player != null) return _player!;
    final player = _player = AudioPlayer();
    _audioSubscriptions.add(player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _audioPosition = position);
    }),);
    _audioSubscriptions.add(player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _audioState = state);
    }),);
    return player;
  }

  void _resetAudio() {
    _player?.stop();
    _audioPosition = Duration.zero;
    _audioState = PlayerState.stopped;
  }

  late final List<OeSensor> _sensors =
      widget.recording.sensors.values.where((s) => s.frameCount > 0).toList();
  int _sensorIndex = 0, _channel = 0, _first = 0;
  int? _rate;
  double _zoom = 1, _position = 0;
  bool _busy = false;
  String? _error;
  Future<OePlot>? _plot;
  final _sampleController = TextEditingController(text: '0');
  OeSensor get _sensor => _sensors[_sensorIndex];
  int get _window => math.max(1, (_sensor.frameCount / _zoom).ceil());
  int get _start => ((_sensor.frameCount - _window) * _position).round();
  int get _end => math.min(_sensor.frameCount, _start + _window);

  @override
  void initState() {
    super.initState();
    if (_sensors.isNotEmpty) _refreshPlot();
  }

  @override
  void dispose() {
    for (final subscription in _audioSubscriptions) {
      subscription.cancel();
    }
    _player?.dispose();
    _sampleController.dispose();
    super.dispose();
  }

  void _refreshPlot() {
    final recording = widget.recording, sensor = _sensor;
    final channel = _channel, start = _start, end = _end;
    _plot = compute(_buildPlot, (recording, sensor.id, channel, start, end));
  }

  void _change(VoidCallback update) {
    _resetAudio();
    _hoverFrame = null;
    setState(() {
      update();
      _refreshPlot();
    });
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(List<XFile> files) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        fileNameOverrides: files.map((file) => file.name).toList(),
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Map<String, Object?> _manifest() => {
        'source_name': widget.name,
        'source_sha256': widget.recording.digest,
        'source_bytes': widget.recording.bytes.length,
        'incomplete_reason': widget.recording.incompleteReason,
        'exact_duplicated_tail': widget.recording.hasExactDuplicatedTail,
        'validated_prefix_bytes': widget.recording.validatedBytes,
        'oe_version': 3,
        'device_id_hex': widget.recording.deviceId,
        'side_raw': widget.recording.side,
        'header_timestamp_us': widget.recording.timestampUs,
        'sensor_id': _sensor.id,
        'channel': _sensor.components[_channel].label,
        'header_type': _sensor.components[_channel].typeName,
        'interpretation': _sensor.isPcm
            ? 'signed int16 PCM; original bit pattern'
            : 'header numeric type',
        'frame_count': _sensor.frameCount,
        'packet_count': _sensor.packets.length,
        'header_default_rate_hz_not_active_rate': _sensor.headerDefaultRate,
        'user_selected_playback_rate_hz_not_verified': _rate,
        'processing':
            'No filtering, normalization, resampling, interpolation, or silent repair.',
        'wav_timing':
            'Samples concatenated in file order. Packet gaps are not filled. Original packet timestamps are NOT represented by WAV playback.',
      };

  Widget _card(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    return Scaffold(
      appBar: AppBar(title: const Text('Recorded log viewer')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OeTimelinePage(recording: r, name: widget.name),
            ),),
            icon: const Icon(Icons.stacked_line_chart),
            label: const Text('Compare sensors · shared time axis'),
          ),
          const SizedBox(height: 8),
          OeLogInfo(recording: r, filename: widget.name),
          if (r.incompleteReason != null)
            _card(
                r.hasExactDuplicatedTail
                    ? 'Exact duplicated file tail detected'
                    : 'PARTIAL INTERPRETATION · unparsed tail',
                [
                  SelectableText(
                    'Parsing stopped at byte ${r.validatedBytes}. ${r.bytes.length - r.validatedBytes} trailing bytes are retained in the original but NOT interpreted.\n${r.incompleteReason}',
                  ),
                  if (r.hasExactDuplicatedTail)
                    Text(
                      'The last ${r.bytes.length - r.validatedBytes} bytes exactly repeat the immediately preceding bytes. They are retained in the original and are not counted again as samples. No original bytes have been removed. The cause of the repeated write is not verified.',
                    )
                  else
                    Text(
                      'The cause of the unparsed tail is not established. All counts, plots, tables and audio below cover only packets accepted before that boundary. No resynchronization, skipped bytes or repaired samples. Sharing the original preserves the entire file. This inspection is temporary and is not saved as a complete library entry.',
                    ),
                ]),
          _card('Original copy · SHA-256 checked', [
            SelectableText(
              '${r.bytes.length} bytes · OE v3\nDevice 0x${r.deviceId} · side ${r.side == 0 ? 'left' : r.side == 1 ? 'right' : 'unknown (${r.side})'}\nHeader timestamp: ${r.timestampUs} µs (clock origin not verified)\nSHA-256: ${r.digest}',
            ),
            const SizedBox(height: 8),
            const Text(
              'Values retain their original precision and units. No calibration, filtering, normalization or repair. Packet timestamps are kept as integers; no wall-clock date is assumed. Copy checksums cannot verify sensor accuracy or detect corruption already present in the source.',
            ),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _action(
                        () => _share([
                          XFile.fromData(
                            r.bytes,
                            mimeType: 'application/octet-stream',
                            name: widget.name,
                          ),
                        ]),
                      ),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share unchanged original'),
            ),
          ]),
          if (_error != null)
            SelectableText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_sensors.isEmpty)
            const Text('Valid header, but no recorded samples.')
          else
            ..._dataWidgets(),
        ],
      ),
    );
  }

  List<Widget> _dataWidgets() {
    final s = _sensor, c = _sensor.components[_channel];
    final packets = s.packets;
    var backwards = 0, duplicates = 0, maxInterval = 0;
    for (var i = 1; i < packets.length; i++) {
      final d = packets[i].timestampUs - packets[i - 1].timestampUs;
      if (d < 0) backwards++;
      if (d == 0) duplicates++;
      maxInterval = math.max(maxInterval, d);
    }
    final span = packets.last.timestampUs - packets.first.timestampUs;
    return [
      _card('Recorded channels', [
        DropdownButtonFormField<int>(
          initialValue: _sensorIndex,
          decoration:
              const InputDecoration(labelText: 'Sensor with recorded data'),
          items: [
            for (var i = 0; i < _sensors.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text('${_sensors[i].name} (SID ${_sensors[i].id})'),
              ),
          ],
          onChanged: _busy
              ? null
              : (i) {
                  if (i != null) {
                    _change(() {
                      _sensorIndex = i;
                      _channel = 0;
                      _rate = null;
                      _zoom = 1;
                      _position = 0;
                      _first = 0;
                      _sampleController.text = '0';
                    });
                  }
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: ValueKey(s.id),
          initialValue: _channel,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Channel in original file order',
          ),
          items: [
            for (var i = 0; i < s.components.length; i++)
              DropdownMenuItem(value: i, child: Text(s.components[i].label)),
          ],
          onChanged: _busy
              ? null
              : (i) {
                  if (i != null) _change(() => _channel = i);
                },
        ),
        const SizedBox(height: 12),
        Text(
          '${s.frameCount} frames · ${packets.length} packets\nHeader unit: ${c.unit.isEmpty ? '(none)' : c.unit} · declared type: ${c.typeName}\nHeader default rate: ${s.headerDefaultRate ?? 'not supplied'} Hz — NOT a recorded active-rate setting.',
        ),
        if (s.isPcm)
          const Text(
            'Microphone display: signed int16 PCM, as used by the firmware. Its header may declare uint16. The table exposes both interpretations of the same bits. These counts are not calibrated sound pressure.',
          ),
      ]),
      if (s.isPcm)
        _card('Microphone playback · ${c.name}', [
          const Text(
            'The active sample rate is not stored in this header. Choose a rate only if you know it. This changes playback speed and duration; it does not verify the recording rate. Samples play in file order, with packet gaps omitted.',
          ),
          DropdownButtonFormField<int>(
            key: ValueKey('rate-${s.id}'),
            initialValue: _rate,
            decoration: const InputDecoration(
              labelText: 'Choose playback rate (unverified assumption)',
            ),
            items: [
              for (final rate in s.availableRates
                  .toSet()
                  .where((r) => r == r.roundToDouble() && r <= 192000))
                DropdownMenuItem(
                  value: rate.toInt(),
                  child: Text('${rate.toInt()} Hz'),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    _resetAudio();
                    setState(() => _rate = v);
                  },
          ),
          if (_rate != null)
            Text(
              'Derived playback duration: ${(s.frameCount / _rate!).toStringAsFixed(6)} s at your selected $_rate Hz.',
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _rate == null || _busy
                    ? null
                    : () => _action(() async {
                          await _player?.stop();
                          final bytes = await compute(
                            _buildWav,
                            (widget.recording, s.id, _channel, _rate!),
                          );
                          if (!mounted) return;
                          final player = _ensurePlayer();
                          await player.setVolume(_volume);
                          await player
                              .play(BytesSource(bytes, mimeType: 'audio/wav'));
                        }),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play selected channel'),
              ),
              TextButton.icon(
                onPressed: _busy ||
                        (_audioState != PlayerState.playing &&
                            _audioState != PlayerState.paused)
                    ? null
                    : () => _action(() async {
                          if (_audioState == PlayerState.playing) {
                            await _player?.pause();
                          } else {
                            await _player?.resume();
                          }
                        }),
                icon: Icon(_audioState == PlayerState.paused
                    ? Icons.play_arrow
                    : Icons.pause,),
                label: Text(
                    _audioState == PlayerState.paused ? 'Resume' : 'Pause',),
              ),
              TextButton(
                onPressed: () => setState(_resetAudio),
                child: const Text('Stop'),
              ),
              TextButton(
                onPressed: _rate == null || _busy
                    ? null
                    : () => _action(() async {
                          final bytes = await compute(
                            _buildWav,
                            (widget.recording, s.id, _channel, _rate!),
                          );
                          final stem =
                              '${widget.recording.digest.substring(0, 12)}_${c.name}_user-rate-$_rate';
                          if (!mounted) return;
                          await _share([
                            XFile.fromData(
                              bytes,
                              mimeType: 'audio/wav',
                              name: '$stem.wav',
                            ),
                            XFile.fromData(
                              Uint8List.fromList(
                                utf8.encode(
                                  const JsonEncoder.withIndent('  ')
                                      .convert(_manifest()),
                                ),
                              ),
                              mimeType: 'application/json',
                              name: '$stem.provenance.json',
                            ),
                          ]);
                        }),
                child: const Text('Share WAV + provenance'),
              ),
            ],
          ),
          Text(
              'Playback: ${_audioState.name} · ${(_audioPosition.inMilliseconds / 1000).toStringAsFixed(2)} s'
              '${_rate == null ? "" : " / ${(s.frameCount / _rate!).toStringAsFixed(2)} s"}'),
          Slider(
            value: _rate == null
                ? 0
                : (_audioPosition.inMicroseconds / 1e6)
                    .clamp(0, s.frameCount / _rate!)
                    .toDouble(),
            max: _rate == null ? 1 : s.frameCount / _rate!,
            label: 'Playback position',
            onChanged: _busy ||
                    _rate == null ||
                    (_audioState != PlayerState.playing &&
                        _audioState != PlayerState.paused)
                ? null
                : (seconds) => _action(() async {
                      await _player?.seek(
                          Duration(microseconds: (seconds * 1e6).round()),);
                    }),
          ),
          Row(children: [
            Text('Listening volume: ${(_volume * 100).round()}%'),
            Expanded(
                child: Slider(
                    value: _volume,
                    onChanged: (value) {
                      setState(() => _volume = value);
                      _player?.setVolume(value);
                    },),),
          ],),
          const Text(
              'Listening volume affects speaker output only; exported PCM and chart values are unchanged.',),
        ]),
      _card(
          _rate == null
              ? 'Recorded waveform · sample index'
              : 'Recorded waveform · assumed playback time',
          [
            const Text(
              'Overview bars retain the exact minimum and maximum of every sample bin. Zoom to individual samples to see a line trace; the connecting lines are visual guides. Hover to inspect an exact value. A seconds axis uses only your chosen playback rate and omits packet gaps.',
            ),
            FutureBuilder<OePlot>(
              future: _plot,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Plot failed: ${snapshot.error}');
                }
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData) {
                  return const SizedBox(
                    height: 260,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final p = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Frames $_start–${_end - 1} · ${p.bins.length} bins · ${p.nonFiniteCount} non-finite values excluded from graph',
                    ),
                    if (p.bins.isEmpty)
                      const Text('No finite values to plot.')
                    else ...[
                      Text(
                        'Minimum ${p.min} · maximum ${p.max} ${s.isPcm ? 'signed PCM counts' : c.unit}',
                      ),
                      SizedBox(
                        height: 260,
                        width: double.infinity,
                        child: LayoutBuilder(
                            builder: (context, constraints) => MouseRegion(
                                onExit: (_) =>
                                    setState(() => _hoverFrame = null),
                                onHover: (event) {
                                  final fraction =
                                      ((event.localPosition.dx - 78) /
                                              math.max(
                                                  1, constraints.maxWidth - 90,))
                                          .clamp(0.0, 1.0);
                                  setState(() => _hoverFrame = _start +
                                      (fraction *
                                              math.max(0, _end - _start - 1))
                                          .round(),);
                                },
                                child: CustomPaint(
                                  painter: _EnvelopePainter(
                                    p,
                                    _start,
                                    _end,
                                    Theme.of(context).colorScheme.primary,
                                    rate: _rate,
                                    cursorFrame: _hoverFrame ??
                                        (s.isPcm &&
                                                _rate != null &&
                                                _audioState !=
                                                    PlayerState.stopped
                                            ? (_audioPosition.inMicroseconds /
                                                    1e6 *
                                                    _rate!)
                                                .floor()
                                            : null),
                                  ),
                                ),),),
                      ),
                    ],
                  ],
                );
              },
            ),
            if (_hoverFrame != null &&
                _hoverFrame! >= _start &&
                _hoverFrame! < _end)
              SelectableText(
                  'Frame $_hoverFrame · ${c.label}: ${widget.recording.value(s, widget.recording.packetForFrame(s, _hoverFrame!), _hoverFrame! - widget.recording.packetForFrame(s, _hoverFrame!).firstFrame, _channel)} ${s.isPcm ? "signed PCM counts" : c.unit} · packet timestamp ${widget.recording.packetForFrame(s, _hoverFrame!).timestampUs} µs',),
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: () => setState(() {
                        _zoom = 1;
                        _position = 0;
                        _hoverFrame = null;
                        _refreshPlot();
                      }),
                  child: const Text('Fit entire recording'),),
              TextButton(
                  onPressed: () => setState(() {
                        _zoom = math.max(1, s.frameCount / 300);
                        _hoverFrame = null;
                        _refreshPlot();
                      }),
                  child: const Text('Inspect 300 samples'),),
              if (s.isPcm && _rate != null)
                TextButton(
                    onPressed: () => setState(() {
                          _zoom = math.max(1, s.frameCount / (_rate! * 5));
                          final frame =
                              (_audioPosition.inMicroseconds / 1e6 * _rate!)
                                  .floor();
                          _position = s.frameCount == _window
                              ? 0
                              : (frame / (s.frameCount - _window))
                                  .clamp(0.0, 1.0);
                          _hoverFrame = null;
                          _refreshPlot();
                        }),
                    child: const Text('View 5 s at playback position'),),
            ],),
            Text('Zoom: ${_zoom.toStringAsFixed(0)}×'),
            Slider(
              value: math.log(_zoom) / math.ln10,
              min: 0,
              max: math.log(math.max(1, s.frameCount).toDouble()) / math.ln10,
              onChanged: (v) => setState(() {
                _zoom = math.pow(10, v).toDouble();
                _plot = null;
              }),
              onChangeEnd: (_) => setState(_refreshPlot),
            ),
            const Text('Position in recording'),
            Slider(
              value: _position,
              onChanged: (v) => setState(() {
                _position = v;
                _plot = null;
              }),
              onChangeEnd: (_) => setState(_refreshPlot),
            ),
          ]),
      _card('Packet timing · original clock', [
        SelectableText(
          'First packet: ${packets.first.timestampUs} µs\nLast packet: ${packets.last.timestampUs} µs\nFirst-to-last packet span: $span µs (excludes unknown final packet duration)\nLargest forward packet interval: $maxInterval µs\nBackward transitions: $backwards · repeated timestamps: $duplicates',
        ),
        const Text(
          'Packet timing can contain jitter, gaps or clock changes. No timestamps are sorted, gaps filled, or per-sample times invented. Inspect individual packet timestamps in the table below.',
        ),
      ]),
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.macOS &&
          c.group.toUpperCase() == 'ACCELEROMETER')
        OeSonificationPanel(
          key: ValueKey('sonification-${s.id}-$_channel'),
          recording: widget.recording,
          sensor: s,
          channel: _channel,
        ),
      _card('Exact sample inspector', [
        TextField(
          controller: _sampleController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Jump to frame (0–${s.frameCount - 1})',
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: _jump,
            ),
          ),
          onSubmitted: (_) => _jump(),
        ),
        const Text(
          'Timestamp is the containing packet’s original timestamp, not a reconstructed sample timestamp. Buffered Δ is the original trailing interval field, where present.',
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Frame')),
              DataColumn(label: Text('Value')),
              DataColumn(label: Text('Header interpretation')),
              DataColumn(label: Text('Packet µs')),
              DataColumn(label: Text('Packet byte offset')),
              DataColumn(label: Text('Buffered Δ µs')),
            ],
            rows: [
              for (var i = _first; i < math.min(_first + 12, s.frameCount); i++)
                _row(i),
            ],
          ),
        ),
        Row(
          children: [
            TextButton(
              onPressed: _first == 0
                  ? null
                  : () => setState(() => _first = math.max(0, _first - 12)),
              child: const Text('Previous'),
            ),
            TextButton(
              onPressed: _first + 12 >= s.frameCount
                  ? null
                  : () => setState(() => _first += 12),
              child: const Text('Next'),
            ),
          ],
        ),
      ]),
    ];
  }

  void _jump() {
    final index = int.tryParse(_sampleController.text);
    if (index == null || index < 0 || index >= _sensor.frameCount) {
      setState(
        () => _error =
            'Frame index must be between 0 and ${_sensor.frameCount - 1}.',
      );
      return;
    }
    setState(() {
      _first = index;
      _error = null;
    });
  }

  DataRow _row(int index) {
    final r = widget.recording,
        s = _sensor,
        p = r.packetForFrame(s, index),
        f = index - p.firstFrame;
    return DataRow(
      cells: [
        for (final text in [
          '$index',
          '${r.value(s, p, f, _channel)}',
          '${r.rawValue(s, p, f, _channel)}',
          '${p.timestampUs}',
          '${p.offset}',
          '${p.bufferedDeltaUs ?? '—'}',
        ])
          DataCell(SelectableText(text)),
      ],
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  final OePlot plot;
  final int start, end;
  final Color color;
  final int? rate, cursorFrame;
  _EnvelopePainter(this.plot, this.start, this.end, this.color,
      {this.rate, this.cursorFrame,});
  @override
  void paint(Canvas canvas, Size size) {
    const left = 78.0, top = 12.0, bottom = 28.0;
    final w = math.max(1.0, size.width - left - 12),
        h = size.height - top - bottom;
    final min = plot.min, max = plot.max;
    final scale = math.max(min.abs(), max.abs());
    double y(double v) => min == max
        ? top + h / 2
        : top +
            ((max / scale) - (v / scale)) / ((max / scale) - (min / scale)) * h;
    for (var tick = 0; tick <= 4; tick++) {
      final fraction = tick / 4;
      final v = min * (1 - fraction) + max * fraction;
      canvas.drawLine(Offset(left, y(v)), Offset(left + w, y(v)),
          Paint()..color = color.withValues(alpha: .12),);
      final label = TextPainter(
        text: TextSpan(
          text: v.toStringAsPrecision(5),
          style: TextStyle(color: color, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: left - 4);
      label.paint(canvas, Offset(0, y(v).clamp(top, top + h - 12)));
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (min <= 0 && max >= 0) {
      canvas.drawLine(
        Offset(left, y(0)),
        Offset(left + w, y(0)),
        Paint()..color = color.withValues(alpha: .2),
      );
    }
    Offset? previous;
    int? previousFrame;
    for (final b in plot.bins) {
      final x = left +
          ((b.firstFrame + b.lastFrame) / 2 - start) /
              math.max(1, end - start - 1) *
              w;
      canvas.drawLine(Offset(x, y(b.min)), Offset(x, y(b.max)), paint);
      if (b.firstFrame == b.lastFrame) {
        final point = Offset(x, y(b.min));
        if (previous != null && previousFrame == b.firstFrame - 1) {
          canvas.drawLine(previous, point, paint);
        }
        canvas.drawCircle(point, 2, paint);
        previous = point;
        previousFrame = b.lastFrame;
      }
    }
    for (var tick = 0; tick <= 4; tick++) {
      final fraction = tick / 4;
      final frame = start + (math.max(0, end - start - 1) * fraction).round();
      final x = left + fraction * w;
      canvas.drawLine(Offset(x, top), Offset(x, top + h),
          Paint()..color = color.withValues(alpha: .12),);
      final label = TextPainter(
          text: TextSpan(
              text: rate == null
                  ? '$frame'
                  : '${(frame / rate!).toStringAsFixed(3)} s',
              style: TextStyle(color: color, fontSize: 10),),
          textDirection: TextDirection.ltr,)
        ..layout();
      label.paint(
          canvas,
          Offset((x - label.width / 2).clamp(0, size.width - label.width),
              size.height - bottom + 6,),);
    }
    if (cursorFrame != null && cursorFrame! >= start && cursorFrame! < end) {
      final x =
          left + (cursorFrame! - start) / math.max(1, end - start - 1) * w;
      canvas.drawLine(
          Offset(x, top),
          Offset(x, top + h),
          Paint()
            ..color = color
            ..strokeWidth = 2,);
    }
  }

  @override
  bool shouldRepaint(covariant _EnvelopePainter old) =>
      old.plot != plot ||
      old.color != color ||
      old.start != start ||
      old.end != end ||
      old.rate != rate ||
      old.cursorFrame != cursorFrame;
}

OePlot _buildPlot((OeRecording, int, int, int, int) args) =>
    OePlot.build(args.$1, args.$1.sensors[args.$2]!, args.$3, args.$4, args.$5);
Uint8List _buildWav((OeRecording, int, int, int) args) =>
    args.$1.wav(args.$1.sensors[args.$2]!, args.$3, args.$4);

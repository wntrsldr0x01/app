import 'oe_playback_source.dart';
import 'oe_workspace.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_wearable/models/oe/oe_pairing.dart';
import 'package:open_wearable/models/oe/oe_metadata.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/models/oe/oe_timeline.dart';
import 'oe_spectrum_page.dart';

class OeComparisonLog {
  final String name;
  final OeRecording recording;
  late final OeTimelineBounds bounds =
      OeTimelineBounds.fromRecording(recording);
  OeComparisonLog(this.name, this.recording);
}

class OeLogComparisonPage extends StatefulWidget {
  final List<OeComparisonLog> logs;
  final bool leftRight;
  const OeLogComparisonPage({
    super.key,
    required this.logs,
    this.leftRight = false,
  });
  @override
  State<OeLogComparisonPage> createState() => _OeLogComparisonPageState();
}

class _OeLogComparisonPageState extends State<OeLogComparisonPage> {
  bool _clock = false, _busy = false, _sameScale = true;
  late List<Set<String>> _channels;
  late List<double> _offsets;
  late List<TextEditingController> _offsetFields;
  final _startField = TextEditingController(),
      _endField = TextEditingController();
  List<OeTimelinePlot>? _plots;
  double _start = 0, _end = 1;
  double? _cursor;
  String? _error;
  int _generation = 0;
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _audioSubscriptions = [];
  PlayerState _audioState = PlayerState.stopped;
  Duration _audioPosition = Duration.zero;
  String? _playingChannel;
  String? _audioError;
  int? _audioRate;
  int _audioGeneration = 0;
  bool _audioBusy = false;
  double _volume = 1, _audioDuration = 0;

  AudioPlayer _ensurePlayer() {
    if (_player != null) return _player!;
    final player = _player = AudioPlayer();
    _audioSubscriptions.add(
      player.onPositionChanged.listen((value) {
        if (mounted) setState(() => _audioPosition = value);
      }),
    );
    _audioSubscriptions.add(
      player.onPlayerStateChanged.listen((value) {
        if (mounted) setState(() => _audioState = value);
      }),
    );
    return player;
  }

  Future<void> _audioAction(Future<void> Function() action) async {
    setState(() {
      _audioBusy = true;
      _audioError = null;
    });
    try {
      await action().timeout(const Duration(seconds: 20));
    } catch (error) {
      if (mounted) setState(() => _audioError = 'Playback failed: $error');
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _stopAudio() async {
    ++_audioGeneration;
    await _player?.stop();
    if (mounted) {
      setState(() {
        _audioPosition = Duration.zero;
        _audioState = PlayerState.stopped;
        _playingChannel = null;
      });
    }
  }

  int get _origin => widget.logs.map((l) => l.bounds.originUs).reduce(math.min);
  double shift(int i) =>
      (_clock ? (widget.logs[i].bounds.originUs - _origin) / 1e6 : 0) +
      _offsets[i];
  @override
  void initState() {
    super.initState();
    _clock = widget.leftRight;
    _channels = [
      for (final log in widget.logs)
        {
          for (final s
              in log.recording.sensors.values.where((s) => s.frameCount > 0))
            for (var c = 0; c < s.components.length; c++) '${s.id}:$c',
        },
    ];
    _offsets = List.filled(widget.logs.length, 0);
    _offsetFields = List.generate(
      widget.logs.length,
      (_) => TextEditingController(text: '0'),
    );
    _fit();
  }

  @override
  void dispose() {
    ++_audioGeneration;
    for (final subscription in _audioSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player?.dispose());
    _startField.dispose();
    _endField.dispose();
    for (final c in _offsetFields) {
      c.dispose();
    }
    super.dispose();
  }

  void _fit() {
    _start = List.generate(widget.logs.length, shift).reduce(math.min);
    _end = List.generate(
      widget.logs.length,
      (i) => shift(i) + widget.logs[i].bounds.seconds,
    ).reduce(math.max);
    if (_end <= _start) _end = _start + .000001;
    _refresh();
  }

  Future<void> _refresh() async {
    unawaited(_audioAction(_stopAudio));
    final generation = ++_generation;
    _plots = null;
    _busy = true;
    _error = null;
    _cursor = null;
    _startField.text = '$_start';
    _endField.text = '$_end';
    try {
      final results = <OeTimelinePlot>[];
      // Sequential isolates bound peak working memory; no arbitrary log-count limit.
      for (var i = 0; i < widget.logs.length; i++) {
        final log = widget.logs[i];
        results.add(
          await compute(
            buildOeTimeline,
            OeTimelineRequest(
              log.recording,
              log.bounds,
              Set.of(_channels[i]),
              _start - shift(i),
              _end - shift(i),
              bins: 700,
            ),
          ),
        );
        if (!mounted || generation != _generation) return;
      }
      setState(() => _plots = results);
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _window(double a, double b) {
    if (!a.isFinite || !b.isFinite || b - a < .000001) {
      setState(() => _error = 'Enter finite start < end (at least 1 µs).');
      return;
    }
    setState(() {
      _start = a;
      _end = b;
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Compare ${widget.logs.length} logs')),
        body: OeWorkspace(
          child: ListView(
            children: [
              if (widget.leftRight)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      OePairing.assess(
                        widget.logs[0].recording,
                        widget.logs[1].recording,
                      ).description,
                    ),
                  ),
                ),
              const Text(
                'Shared time window · original values · separate panels for every channel. No resampling or automatic clock synchronization.',
              ),
              SwitchListTile(
                title: const Text('Align recorded device clocks'),
                subtitle: Text(
                  _clock
                      ? 'Subtract a common integer timestamp origin ($_origin µs). Matching clocks do NOT establish synchronization.'
                      : 'Elapsed alignment: each log starts at its earliest packet, independently. This compares event shapes, not simultaneous real-world time.',
                ),
                value: _clock,
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _clock = v;
                          _fit();
                        }),
              ),
              SwitchListTile(
                title: const Text(
                  'Use common Y scales for matching channel labels and units',
                ),
                subtitle: const Text(
                  'Matching labels do not prove matching calibration.',
                ),
                value: _sameScale,
                onChanged: (v) => setState(() => _sameScale = v),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _startField,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Shared start (s)',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _endField,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Shared end (s)',
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _window(
                              double.tryParse(_startField.text) ?? double.nan,
                              double.tryParse(_endField.text) ?? double.nan,
                            ),
                    child: const Text('Apply window'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(_fit),
                    child: const Text('Fit all logs'),
                  ),
                  for (final seconds in [10.0, 1.0, .1])
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _window(
                                _cursor ?? _start,
                                (_cursor ?? _start) + seconds,
                              ),
                      child: Text('$seconds s'),
                    ),
                  IconButton(
                    tooltip: 'Previous window',
                    onPressed: _busy
                        ? null
                        : () => _window(
                              _start - (_end - _start) / 2,
                              _end - (_end - _start) / 2,
                            ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next window',
                    onPressed: _busy
                        ? null
                        : () => _window(
                              _start + (_end - _start) / 2,
                              _end + (_end - _start) / 2,
                            ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Text(
                'Window ${_start.toStringAsFixed(6)}–${_end.toStringAsFixed(6)} s · duration ${(_end - _start).toStringAsFixed(6)} s · linked cursor ${_cursor?.toStringAsFixed(6) ?? "—"} s',
              ),
              const Text(
                'Overview bars retain the exact minimum and maximum of every finite sample in each time bin. Empty bins remain empty. PCM uses packet anchors; buffered sensors use the stored interval. Cursor values are bin ranges, not interpolated point values.',
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) SelectableText(_error!),
              for (var i = 0; i < widget.logs.length; i++) _log(i),
              if (_plots != null) _comparisonCharts(),
            ],
          ),
        ),
      );
  Widget _log(int i) {
    final log = widget.logs[i];
    return Card(
      child: ExpansionTile(
        title: Text(
          '${i + 1}. ${log.name}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${oeEarLabel(log.recording.side)} · ${log.bounds.seconds.toStringAsFixed(3)} s · ${_channels[i].length} channels selected · offset ${shift(i).toStringAsFixed(3)} s',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ${log.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SelectableText(
                  'SHA-256 ${log.recording.digest}\nDevice ${log.recording.deviceId} · ${oeEarLabel(log.recording.side)} · ${log.bounds.seconds.toStringAsFixed(6)} s timestamp extent · displayed origin shift ${shift(i).toStringAsFixed(6)} s',
                ),
                if (log.recording.incompleteReason != null)
                  Text(
                    'Source interpretation: ${log.recording.incompleteReason}',
                  ),
                ExpansionTile(
                  title: Text(
                    'Channels & alignment · ${_channels[i].length} selected',
                  ),
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        SizedBox(
                          width: 230,
                          child: TextField(
                            controller: _offsetFields[i],
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Manual display offset (s)',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  final value =
                                      double.tryParse(_offsetFields[i].text);
                                  if (value == null || !value.isFinite) {
                                    setState(
                                      () => _error =
                                          'Offset must be finite seconds.',
                                    );
                                    return;
                                  }
                                  setState(() {
                                    _offsets[i] = value;
                                    _fit();
                                  });
                                },
                          child: const Text('Apply offset'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _channels[i].clear();
                                    _refresh();
                                  }),
                          child: const Text('Clear channels'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _channels[i] = {
                                      for (final s in log
                                          .recording.sensors.values
                                          .where((s) => s.frameCount > 0))
                                        for (var c = 0;
                                            c < s.components.length;
                                            c++)
                                          '${s.id}:$c',
                                    };
                                    _refresh();
                                  }),
                          child: const Text('All channels'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final sensor in log.recording.sensors.values
                            .where((s) => s.frameCount > 0))
                          for (var c = 0; c < sensor.components.length; c++)
                            FilterChip(
                              label: Text(
                                '${sensor.name} · ${sensor.components[c].label}',
                              ),
                              selected:
                                  _channels[i].contains('${sensor.id}:$c'),
                              onSelected: _busy
                                  ? null
                                  : (v) => setState(() {
                                        if (v) {
                                          _channels[i].add('${sensor.id}:$c');
                                        } else {
                                          _channels[i]
                                              .remove('${sensor.id}:$c');
                                        }
                                        _refresh();
                                      }),
                            ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comparisonCharts() {
    final groups = <String, List<(int, OeTimeSeries)>>{};
    for (var i = 0; i < widget.logs.length; i++) {
      for (final series in _plots![i].series) {
        final sensor = widget.logs[i].recording.sensors[series.sensorId]!;
        final c = sensor.components[series.channel];
        groups
            .putIfAbsent(
          '${c.label} [${sensor.isPcm ? "signed PCM counts" : c.unit}]',
          () => [],
        )
            .add((i, series));
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final largestGroup = groups.values
            .fold<int>(1, (size, items) => math.max(size, items.length));
        final columns = math.min(
          largestGroup,
          math.max(1, (constraints.maxWidth / 550).floor()),
        );
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final group in groups.entries) ...[
              Text(group.key, style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final item in group.value)
                    SizedBox(
                      width: width,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.$1 + 1}. ${widget.logs[item.$1].name}',
                              ),
                              _chart(item.$1, item.$2),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _chart(int i, OeTimeSeries series) {
    final log = widget.logs[i],
        sensor = widget.logs[i].recording.sensors[series.sensorId]!;
    final component = sensor.components[series.channel];
    var low = series.min, high = series.max;
    if (_sameScale) {
      for (var j = 0; j < widget.logs.length; j++) {
        for (final other in _plots![j].series) {
          final os = widget.logs[j].recording.sensors[other.sensorId]!,
              oc = os.components[other.channel];
          if (oc.label == component.label &&
              oc.unit == component.unit &&
              os.isPcm == sensor.isPcm &&
              other.finiteCount > 0) {
            low = math.min(low, other.min);
            high = math.max(high, other.max);
          }
        }
      }
    }
    final binIndex = _cursor == null
        ? null
        : ((_cursor! - _start) / (_end - _start) * 700).floor().clamp(0, 699);
    final cursorBins = series.bins.where((b) => b.index == binIndex).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${sensor.name} · ${component.label} [${sensor.isPcm ? "signed PCM counts" : component.unit}]',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OeSpectrumPage(
                    recording: log.recording,
                    name: log.name,
                    sensorId: sensor.id,
                    channel: series.channel,
                    firstFrame: series.bins.isEmpty
                        ? 0
                        : series.bins.map((b) => b.firstFrame).reduce(math.min),
                  ),
                ),
              ),
              child: Text(sensor.isPcm ? 'FFT / mel' : 'FFT'),
            ),
          ],
        ),
        SizedBox(
          height: 190,
          child: LayoutBuilder(
            builder: (context, constraints) => MouseRegion(
              onHover: (event) => setState(
                () => _cursor = _start +
                    ((event.localPosition.dx - 80) /
                                math.max(1, constraints.maxWidth - 100))
                            .clamp(0, 1) *
                        (_end - _start),
              ),
              child: CustomPaint(
                size: Size(constraints.maxWidth, 190),
                painter: _ComparisonPainter(
                  series,
                  low,
                  high,
                  _start,
                  _end,
                  _cursor,
                  i,
                ),
              ),
            ),
          ),
        ),
        Text(
          '${series.finiteCount} finite samples · ${series.nonFiniteCount} non-finite excluded from display${binIndex == null ? "" : cursorBins.isEmpty ? " · cursor bin: no samples" : " · cursor bin: min ${cursorBins.first.min}, max ${cursorBins.first.max}, ${cursorBins.first.count} samples, frames ${cursorBins.first.firstFrame}–${cursorBins.first.lastFrame}"}',
        ),
        if (sensor.isPcm) _microphonePlayback(i, series),
        const Divider(),
      ],
    );
  }

  Widget _microphonePlayback(int i, OeTimeSeries series) {
    final key = '$i:${series.sensorId}:${series.channel}';
    final active = _playingChannel == key;
    final running = active &&
        (_audioState == PlayerState.playing ||
            _audioState == PlayerState.paused);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<int>(
                key: ValueKey('comparison-rate-$key-$_audioRate'),
                initialValue: _audioRate,
                decoration:
                    const InputDecoration(labelText: 'Playback rate (Hz)'),
                items: [
                  for (final rate in [
                    8000,
                    16000,
                    24000,
                    32000,
                    44100,
                    48000,
                    96000,
                  ])
                    DropdownMenuItem(value: rate, child: Text('$rate Hz')),
                ],
                onChanged: _audioBusy
                    ? null
                    : (rate) => _audioAction(() async {
                          await _stopAudio();
                          if (mounted) setState(() => _audioRate = rate);
                        }),
              ),
            ),
            FilledButton.icon(
              onPressed: _audioRate == null ||
                      _audioBusy ||
                      _busy ||
                      series.bins.isEmpty
                  ? null
                  : () => _audioAction(() async {
                        await _stopAudio();
                        final generation = _audioGeneration;
                        final first = series.bins
                            .map((b) => b.firstFrame)
                            .reduce(math.min);
                        final last = series.bins
                            .map((b) => b.lastFrame)
                            .reduce(math.max);
                        final bytes = await compute(
                          _comparisonWav,
                          (
                            widget.logs[i].recording,
                            series.sensorId,
                            series.channel,
                            _audioRate!,
                            first,
                            last - first + 1
                          ),
                        );
                        if (!mounted || generation != _audioGeneration) return;
                        final player = _ensurePlayer();
                        setState(() {
                          _playingChannel = key;
                          _audioDuration = (last - first + 1) / _audioRate!;
                        });
                        await player.setVolume(_volume);
                        await player.play(await oePlaybackSource(bytes));
                      }),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play visible microphone'),
            ),
            TextButton.icon(
              onPressed: !running || _audioBusy
                  ? null
                  : () => _audioAction(() async {
                        if (_audioState == PlayerState.playing) {
                          await _player?.pause();
                        } else {
                          await _player?.resume();
                        }
                      }),
              icon: Icon(
                active && _audioState == PlayerState.paused
                    ? Icons.play_arrow
                    : Icons.pause,
              ),
              label: Text(
                active && _audioState == PlayerState.paused
                    ? 'Resume'
                    : 'Pause',
              ),
            ),
            TextButton.icon(
              onPressed:
                  !active || _audioBusy ? null : () => _audioAction(_stopAudio),
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ],
        ),
        const Text(
          'Choose the known microphone rate. Plays the visible frame range in file order; packet gaps are omitted. One channel plays at a time.',
        ),
        if (_audioBusy) const LinearProgressIndicator(),
        if (_audioError != null)
          SelectableText(_audioError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),),
        if (active) ...[
          Text(
            'Playback: ${_audioState.name} · ${(_audioPosition.inMicroseconds / 1e6).toStringAsFixed(2)} / ${_audioDuration.toStringAsFixed(2)} s',
          ),
          Slider(
            value: (_audioPosition.inMicroseconds / 1e6)
                .clamp(0.0, _audioDuration),
            max: _audioDuration,
            onChanged: !running || _audioBusy
                ? null
                : (value) => _audioAction(() async {
                      await _player
                          ?.seek(Duration(microseconds: (value * 1e6).round()));
                    }),
          ),
          Row(
            children: [
              const Icon(Icons.volume_up),
              Expanded(
                child: Slider(
                  value: _volume,
                  onChanged: _audioBusy
                      ? null
                      : (value) {
                          setState(() => _volume = value);
                          unawaited(
                            _audioAction(() => _player!.setVolume(value)),
                          );
                        },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ComparisonPainter extends CustomPainter {
  final OeTimeSeries series;
  final double low, high, start, end;
  final double? cursor;
  final int index;
  _ComparisonPainter(
    this.series,
    this.low,
    this.high,
    this.start,
    this.end,
    this.cursor,
    this.index,
  );
  void label(Canvas c, String s, Offset p) {
    final t = TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(fontSize: 10, color: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    t.paint(c, p);
  }

  @override
  void paint(Canvas c, Size size) {
    final rect = Rect.fromLTWH(80, 10, math.max(1, size.width - 100), 150);
    final color = const [
      Color(0xFF0072B2),
      Color(0xFFD55E00),
      Color(0xFF009E73),
      Color(0xFFCC79A7),
    ][index % 4];
    c.drawRect(rect, Paint()..color = Colors.white);
    double y(double v) => high == low
        ? rect.center.dy
        : rect.bottom - (v - low) / (high - low) * rect.height;
    for (var t = 0; t <= 4; t++) {
      final f = t / 4;
      c.drawLine(
        Offset(rect.left, rect.top + f * rect.height),
        Offset(rect.right, rect.top + f * rect.height),
        Paint()..color = Colors.black12,
      );
      if (low.isFinite && high.isFinite) {
        label(
          c,
          (high * (1 - f) + low * f).toStringAsPrecision(4),
          Offset(0, rect.top + f * rect.height - 5),
        );
      }
      label(
        c,
        '${(start + f * (end - start)).toStringAsFixed(3)} s',
        Offset(rect.left + f * (rect.width - 50), 167),
      );
    }
    for (final b in series.bins) {
      final x = rect.left + (b.index + .5) / 700 * rect.width;
      c.drawLine(
        Offset(x, y(b.min)),
        Offset(x, y(b.max)),
        Paint()
          ..color = color
          ..strokeWidth = 1.3,
      );
      if (b.min == b.max) {
        c.drawCircle(Offset(x, y(b.min)), 1, Paint()..color = color);
      }
    }
    if (cursor != null) {
      final x = rect.left + (cursor! - start) / (end - start) * rect.width;
      c.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        Paint()..color = Colors.black54,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ComparisonPainter old) => true;
}

Uint8List _comparisonWav((OeRecording, int, int, int, int, int) args) =>
    args.$1.wav(
      args.$1.sensors[args.$2]!,
      args.$3,
      args.$4,
      firstFrame: args.$5,
      frameCount: args.$6,
    );

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/models/oe/oe_timeline.dart';

const _palette = [
  Color(0xFF0072B2),
  Color(0xFFD55E00),
  Color(0xFF009E73),
  Color(0xFFCC79A7),
  Color(0xFF7B61A8),
  Color(0xFF8A6500),
];
Color _channelColor(OeSensor sensor, int c) {
  return switch (sensor.components[c].name.toUpperCase()) {
    'X' => _palette[0],
    'Y' => _palette[1],
    'Z' => _palette[2],
    'OUTER' => _palette[0],
    'INNER' => _palette[3],
    _ => _palette[c % _palette.length],
  };
}

String _seconds(double value, double window) => value.toStringAsFixed((3 - math.log(window) / math.ln10).ceil().clamp(3, 9));
String _n(double value) => value == 0
    ? '0'
    : value.abs() >= 1e6 || value.abs() < .001
        ? value.toStringAsExponential(3)
        : value.toStringAsPrecision(5);

class OeTimelinePage extends StatefulWidget {
  final OeRecording recording;
  final String name;
  const OeTimelinePage(
      {super.key, required this.recording, required this.name,});
  @override
  State<OeTimelinePage> createState() => _OeTimelinePageState();
}

class _OeTimelinePageState extends State<OeTimelinePage> {
  late final OeTimelineBounds _bounds;
  late final Set<String> _channels;
  late double _start, _end;
  Future<OeTimelinePlot>? _future;
  OeTimelinePlot? _completed;
  double? _cursor, _dragStart, _dragEnd;
  bool _busy = false,
      _separateAxes = false,
      _twoColumns = false,
      _showJumps = true;
  final Map<String, (double, double)> _fixedY = {};
  final _startField = TextEditingController(),
      _endField = TextEditingController();
  String? _error;
  double get _extent => math.max(.000001, _bounds.seconds);
  List<OeSensor> get _sensors =>
      widget.recording.sensors.values.where((s) => s.frameCount > 0).toList();

  @override
  void initState() {
    super.initState();
    _bounds = OeTimelineBounds.fromRecording(widget.recording);
    _channels = {
      for (final sensor in _sensors)
        for (var c = 0; c < sensor.components.length; c++) '${sensor.id}:$c',
    };
    _start = 0;
    _end = _extent;
    _refresh();
  }

  @override
  void dispose() {
    _startField.dispose();
    _endField.dispose();
    super.dispose();
  }

  void _refresh() {
    _busy = true;
    _completed = null;
    _error = null;
    _startField.text = _start.toStringAsFixed(6);
    _endField.text = _end.toStringAsFixed(6);
    final future = compute(
        buildOeTimeline,
        OeTimelineRequest(
            widget.recording, _bounds, Set.of(_channels), _start, _end,),);
    _future = future;
    future.then((result) {
      if (!mounted || _future != future) return;
      setState(() {
        _completed = result;
        _busy = false;
      });
    }, onError: (Object error) {
      if (!mounted || _future != future) return;
      setState(() {
        _error = '$error';
        _busy = false;
      });
    },);
  }

  void _window(double start, double end) {
    if (_busy) return;
    final width = (end - start).clamp(.000001, _extent).toDouble();
    final left = start.clamp(0.0, math.max(0, _extent - width)).toDouble();
    setState(() {
      _cursor = null;
      _start = left;
      _end = left + width;
      _dragStart = null;
      _dragEnd = null;
      _refresh();
    });
  }

  void _preset(double? seconds) {
    if (seconds == null) _fixedY.clear();
    final width = seconds == null ? _extent : math.min(seconds, _extent);
    final center = _cursor ?? (_start + _end) / 2;
    _window(seconds == null ? 0 : center - width / 2,
        seconds == null ? _extent : center + width / 2,);
  }

  void _toggle(int id, int channel, bool selected) {
    setState(() {
      selected
          ? _channels.add('$id:$channel')
          : _channels.remove('$id:$channel');
      _refresh();
    });
  }

  List<_Panel> _panels(OeTimelinePlot plot) {
    final grouped = <String, List<OeTimeSeries>>{};
    for (final series in plot.series) {
      final component =
          widget.recording.sensors[series.sensorId]!.components[series.channel];
      final key =
          '${series.sensorId}:${component.group}:${component.unit}${_separateAxes ? ':${series.channel}' : ''}';
      grouped.putIfAbsent(key, () => []).add(series);
    }
    return [
      for (final entry in grouped.entries)
        _Panel(entry.key, widget.recording.sensors[entry.value.first.sensorId]!,
            entry.value,),
    ];
  }

  Future<void> _export() async {
    final plot = _completed;
    if (plot == null) return;
    final panels = _panels(plot);
    final width = 1200.0, rowHeight = 290.0;
    final svg = StringBuffer(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="${panels.length * rowHeight + 80}" viewBox="0 0 $width ${panels.length * rowHeight + 80}"><rect width="100%" height="100%" fill="white"/>',);
    String escape(String v) => const HtmlEscape().convert(v);
    svg.write(
        '<text x="20" y="24" font-size="16">${escape(widget.name)} · device timeline ${_start.toStringAsFixed(6)}–${_end.toStringAsFixed(6)} s</text>',);
    svg.write(
        '<text x="20" y="45" font-size="10">SHA-256 ${widget.recording.digest}; min/max bins; microphone packet anchors; buffered sensor times derived from stored delta</text>',);
    for (var i = 0; i < panels.length; i++) {
      final panel = panels[i], offset = 70 + i * rowHeight;
      final limits = _fixedY[panel.key] ?? panel.limits;
      final geometry =
          _Geometry(Size(width, 210), limits.$1, limits.$2, _start, _end);
      svg.write(
          '<g transform="translate(0,$offset)"><text x="20" y="15" font-size="14">${escape(panel.title)} [${escape(panel.unit)}]</text><g transform="translate(0,30)">',);
      for (var tick = 0; tick <= 4; tick++) {
        final fraction = tick / 4;
        final x = geometry.left + fraction * geometry.width;
        final y = geometry.top + fraction * geometry.height;
        svg.write(
            '<path d="M ${geometry.left} $y H ${geometry.left + geometry.width} M $x ${geometry.top} V ${geometry.top + geometry.height}" stroke="#dddddd" fill="none"/>',);
        svg.write(
            '<text x="$x" y="202" font-size="10" text-anchor="middle">${_seconds(_start + fraction * (_end - _start), _end - _start)} s</text>',);
        svg.write(
            '<text x="70" y="$y" font-size="10" text-anchor="end">${_n(limits.$2 * (1 - fraction) + limits.$1 * fraction)}</text>',);
      }
      svg.write('<defs><clipPath id="plot-$i"><rect x="${geometry.left}" y="${geometry.top}" width="${geometry.width}" height="${geometry.height}"/></clipPath></defs><g clip-path="url(#plot-$i)">');
      for (final series in panel.series) {
        final color =
            '#${_channelColor(panel.sensor, series.channel).toARGB32().toRadixString(16).substring(2)}';
        for (final bin in series.bins) {
          final x = geometry.x(bin.count == 1
              ? (bin.firstTimeUs - _bounds.originUs) / 1e6
              : _start + (bin.index + .5) / plot.binCount * (_end - _start),);
          final y1 = geometry.y(bin.min), y2 = geometry.y(bin.max);
          svg.write(
              '<path d="M $x $y1 V $y2" stroke="$color"/><circle cx="$x" cy="$y1" r="1" fill="$color"/>',);
        }
      }
      svg.write('</g>');
      svg.write(
          '</g><text x="80" y="273" font-size="11">${escape(panel.series.map((s) => s.finiteCount == 0 ? '${panel.sensor.components[s.channel].name}: no finite data' : '${panel.sensor.components[s.channel].name}: ${s.finiteCount} finite values, min ${_n(s.min)}, max ${_n(s.max)}').join(' | '))}</text></g>',);
    }
    svg.write('</svg>');
    final provenance = {
      'source_name': widget.name,
      'source_sha256': widget.recording.digest,
      'timestamp_origin_us': _bounds.originUs,
      'start_seconds': _start,
      'end_seconds': _end,
      'channels': _channels.toList(),
      'time_bins': plot.binCount,
      'y_limits': {for (final p in panels) p.key: [(_fixedY[p.key] ?? p.limits).$1, (_fixedY[p.key] ?? p.limits).$2]},
      'series_counts': {for (final s in plot.series) s.key: {'finite': s.finiteCount, 'non_finite_excluded': s.nonFiniteCount}},
      'timing':
          'Unbuffered: packet timestamp. Buffered non-PCM: packet timestamp + (frame index + 1) * stored delta. PCM: all frames at containing packet timestamp; within-packet sample timing unknown.',
      'plot':
          'All finite values contribute to min/max envelopes. No filtering, normalization, interpolation or source modification. Export shows envelopes, not interpolated lines.',
      'partial_reason': widget.recording.incompleteReason,
      'validated_bytes': widget.recording.validatedBytes,
    };
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(ShareParams(
          files: [
            XFile.fromData(Uint8List.fromList(utf8.encode(svg.toString())),
                mimeType: 'image/svg+xml', name: 'timeline.svg',),
            XFile.fromData(
                Uint8List.fromList(utf8.encode(
                    const JsonEncoder.withIndent('  ').convert(provenance),),),
                mimeType: 'application/json',
                name: 'timeline.provenance.json',),
          ],
          fileNameOverrides: [
            'timeline.svg',
            'timeline.provenance.json',
          ],
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,),);
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plot = _completed;
    return Scaffold(
      appBar: AppBar(title: const Text('Sensor comparison'), actions: [
        IconButton(
            tooltip: 'Export visible charts as SVG + provenance',
            onPressed: _busy || plot == null ? null : _export,
            icon: const Icon(Icons.ios_share),),
      ],),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                  'Device timeline · ${_bounds.seconds.toStringAsFixed(6)} s timestamp extent · ${_start.toStringAsFixed(6)}–${_end.toStringAsFixed(6)} s selected (${(_end - _start).toStringAsFixed(6)} s)',
                  style: Theme.of(context).textTheme.titleSmall,),
              if (widget.recording.incompleteReason != null)
                Text(
                    widget.recording.hasExactDuplicatedTail
                        ? 'Exact duplicated file tail retained, not counted twice.'
                        : 'Partial interpretation: all charts cover the parsed prefix only.',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),),
              RangeSlider(
                  values: RangeValues(
                      _start.clamp(0, _extent), _end.clamp(0, _extent),),
                  min: 0,
                  max: _extent,
                  onChanged: _busy
                      ? null
                      : (range) {
                          if (range.end - range.start >= .000001) {
                            setState(() {
                              _start = range.start;
                              _end = range.end;
                              _completed = null;
                            });
                          }
                        },
                  onChangeEnd: _busy ? null : (_) => setState(_refresh),),
              Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                        onPressed: _busy ? null : () => _preset(null),
                        child: const Text('Fit all'),),
                    for (final seconds in [10.0, 1.0, .1])
                      TextButton(
                          onPressed: _busy ? null : () => _preset(seconds),
                          child: Text(
                              '${seconds < 1 ? '100 ms' : '${seconds.toInt()} s'} window',),),
                    IconButton(
                        tooltip: 'Pan left half a window',
                        onPressed: _busy
                            ? null
                            : () => _window(_start - (_end - _start) / 2,
                                _end - (_end - _start) / 2,),
                        icon: const Icon(Icons.chevron_left),),
                    IconButton(
                        tooltip: 'Pan right half a window',
                        onPressed: _busy
                            ? null
                            : () => _window(_start + (_end - _start) / 2,
                                _end + (_end - _start) / 2,),
                        icon: const Icon(Icons.chevron_right),),
                    Text('Cursor: ${_cursor?.toStringAsFixed(6) ?? '—'} s'),
                  ],),
            ],),),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(8), child: SelectableText(_error!),),
        Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
          _controls(),
          if (_channels.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Choose one or more sensors or axes above.'),),
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Reading original values for this time window…'),),
          if (plot != null)
            LayoutBuilder(builder: (context, constraints) {
              final width = _twoColumns && constraints.maxWidth >= 900
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final panel in _panels(plot))
                  SizedBox(width: width, child: _panel(panel, plot)),
              ],);
            },),
        ],),),
      ],),
    );
  }

  Widget _controls() => Card(
          child: ExpansionTile(
              title: Text('Sensors & axes · ${_channels.length} selected'),
              subtitle: const Text(
                  'Choose any combination · shared time window · drag across a chart to zoom',),
              childrenPadding: const EdgeInsets.all(12),
              children: [
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _channels.addAll({
                              for (final s in _sensors)
                                for (var c = 0; c < s.components.length; c++)
                                  '${s.id}:$c',
                            });
                            _refresh();
                          }),
                  child: const Text('Select all'),),
              TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _channels.clear();
                            _refresh();
                          }),
                  child: const Text('Clear selection'),),
              FilterChip(
                  label: const Text('Separate axes'),
                  selected: _separateAxes,
                  onSelected: (v) => setState(() {
                        _separateAxes = v;
                        _fixedY.clear();
                      }),),
              FilterChip(
                  label: const Text('Two columns'),
                  selected: _twoColumns,
                  onSelected: (v) => setState(() => _twoColumns = v),),
              FilterChip(
                  label: const Text('Highlight time jumps'),
                  selected: _showJumps,
                  onSelected: (v) => setState(() => _showJumps = v),),
            ],),
            for (final sensor in _sensors)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sensor.name),
                    value: sensor.components
                        .asMap()
                        .keys
                        .any((c) => _channels.contains('${sensor.id}:$c')),
                    onChanged: _busy
                        ? null
                        : (selected) => setState(() {
                              for (var c = 0;
                                  c < sensor.components.length;
                                  c++) {
                                selected!
                                    ? _channels.add('${sensor.id}:$c')
                                    : _channels.remove('${sensor.id}:$c');
                              }
                              _refresh();
                            }),),
                Wrap(spacing: 6, children: [
                  for (var c = 0; c < sensor.components.length; c++)
                    FilterChip(
                        label: Text(sensor.components[c].label),
                        avatar: CircleAvatar(
                            backgroundColor: _channelColor(sensor, c),
                            radius: 5,),
                        selected: _channels.contains('${sensor.id}:$c'),
                        onSelected:
                            _busy ? null : (v) => _toggle(sensor.id, c, v),),
                ],),
              ],),
            const Divider(),
            Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                      width: 165,
                      child: TextField(
                          controller: _startField,
                          decoration: const InputDecoration(
                              labelText: 'Start (seconds)',),
                          keyboardType: TextInputType.number,),),
                  SizedBox(
                      width: 165,
                      child: TextField(
                          controller: _endField,
                          decoration:
                              const InputDecoration(labelText: 'End (seconds)'),
                          keyboardType: TextInputType.number,),),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              final a = double.tryParse(_startField.text),
                                  b = double.tryParse(_endField.text);
                              if (a == null ||
                                  b == null ||
                                  !a.isFinite ||
                                  !b.isFinite ||
                                  a < 0 ||
                                  b > _extent ||
                                  b <= a) {
                                setState(() => _error =
                                    'Enter 0 ≤ start < end ≤ ${_extent.toStringAsFixed(6)} seconds.',);
                                return;
                              }
                              _window(a, b);
                            },
                      child: const Text('Apply exact window'),),
                ],),
            Text('Time zero is the earliest recorded packet: ${_bounds.originUs} µs. Timestamp extent excludes the unknown duration after the final sample.'),
            const Text(
                'All panels share a device-clock origin and window. Buffered sensor sample times follow the official decoder: packet timestamp + (zero-based frame index + 1) × stored interval; microphone samples are grouped at packet timestamps. Cross-device synchronization is not implied. Different units are kept in separate panels.',),
            const Text(
                'Overview: exact min/max per time bin, including every finite value. Zoom: individual samples with connecting lines as visual guides only. Amber bands flag packet jumps >5× the median positive packet interval; these are not proof of missing data. Backward/repeated timestamps are reported, not repaired.',),
          ],),);

  Widget _panel(_Panel panel, OeTimelinePlot plot) {
    final timing = _bounds.sensors[panel.sensor.id]!;
    final limits = _fixedY[panel.key] ?? panel.limits;
    final cursorBin = _cursor == null || _cursor! < _start || _cursor! > _end
        ? null
        : (((_cursor! - _start) / (_end - _start)) * plot.binCount)
            .floor()
            .clamp(0, plot.binCount - 1);
    final jumpCount =
        plot.jumps.where((j) => j.sensorId == panel.sensor.id).length;
    return Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(panel.title,
                        style: Theme.of(context).textTheme.titleMedium,),),
                IconButton(
                    tooltip: _fixedY.containsKey(panel.key)
                        ? 'Unlock Y scale'
                        : 'Lock current Y scale',
                    icon: Icon(_fixedY.containsKey(panel.key)
                        ? Icons.lock
                        : Icons.lock_open,),
                    onPressed: () => setState(() {
                          _fixedY.containsKey(panel.key)
                              ? _fixedY.remove(panel.key)
                              : _fixedY[panel.key] = panel.limits;
                        }),),
              ],),
              Text(
                  '${panel.unit} · ${panel.sensor.isPcm ? 'Packet-timed audio envelope; no within-packet timing assumed' : timing.buffered ? 'Packet timestamp + stored per-sample Δ (derived)' : 'Original sample / packet timestamps'}',
                  style: Theme.of(context).textTheme.bodySmall,),
              Text(
                  'Sensor timestamp extent: ${((timing.lastUs - timing.firstUs) / 1e6).toStringAsFixed(6)} s · backward packets ${timing.backwards} · repeated ${timing.repeated} · visible large jumps $jumpCount',
                  style: Theme.of(context).textTheme.labelSmall,),
              Wrap(spacing: 6, children: [
                for (final series in panel.series)
                  Chip(
                      avatar: CircleAvatar(
                          radius: 5,
                          backgroundColor:
                              _channelColor(panel.sensor, series.channel),),
                      label: Text(panel.sensor.components[series.channel].name),
                      onDeleted: _busy
                          ? null
                          : () =>
                              _toggle(series.sensorId, series.channel, false),),
              ],),
              SizedBox(
                  height: 205,
                  width: double.infinity,
                  child: LayoutBuilder(builder: (context, constraints) {
                    double at(Offset position) =>
                        _start +
                        ((position.dx - 78) /
                                    math.max(1, constraints.maxWidth - 90))
                                .clamp(0, 1) *
                            (_end - _start);
                    return MouseRegion(
                        onHover: (event) =>
                            setState(() => _cursor = at(event.localPosition)),
                        child: GestureDetector(
                          onDoubleTap: _busy ? null : () => _preset(null),
                          onTapDown: (details) => setState(
                              () => _cursor = at(details.localPosition),),
                          onHorizontalDragStart: _busy
                              ? null
                              : (details) => setState(() {
                                    _dragStart = at(details.localPosition);
                                    _dragEnd = _dragStart;
                                  }),
                          onHorizontalDragUpdate: _busy
                              ? null
                              : (details) => setState(
                                  () => _dragEnd = at(details.localPosition),),
                          onHorizontalDragEnd: _busy
                              ? null
                              : (_) {
                                  if (_dragStart != null &&
                                      _dragEnd != null &&
                                      (_dragEnd! - _dragStart!).abs() >
                                          (_end - _start) / 900) {
                                    _window(math.min(_dragStart!, _dragEnd!),
                                        math.max(_dragStart!, _dragEnd!),);
                                  } else {
                                    setState(() {
                                      _dragStart = null;
                                      _dragEnd = null;
                                    });
                                  }
                                },
                          child: CustomPaint(
                              painter: _TimelinePainter(
                                  panel,
                                  plot,
                                  _bounds,
                                  limits,
                                  _cursor,
                                  _dragStart,
                                  _dragEnd,
                                  _showJumps,
                                  Theme.of(context).colorScheme,),),
                        ),);
                  },),),
              if (panel.series.every((s) => s.finiteCount == 0))
                const Text('No finite samples in this time window.'),
              for (final series in panel.series)
                Builder(builder: (context) {
                  OeTimeBin? bin;
                  if (cursorBin != null) {
                    for (final candidate in series.bins) {
                      if (candidate.index == cursorBin) {
                        bin = candidate;
                        break;
                      }
                    }
                  }
                  final label = panel.sensor.components[series.channel].name;
                  final cursor = bin == null
                      ? 'no sample in cursor bin'
                      : bin.count == 1
                          ? 'value ${bin.firstValue} at ${((bin.firstTimeUs - _bounds.originUs) / 1e6).toStringAsFixed(6)} s · frame ${bin.firstFrame}'
                          : '${bin.count} values in cursor bin · min ${_n(bin.min)}, max ${_n(bin.max)} · source frames ${bin.firstFrame}–${bin.lastFrame}';
                  return SelectableText(
                      '$label · ${series.finiteCount} finite / ${series.nonFiniteCount} non-finite · visible min ${series.finiteCount == 0 ? '—' : _n(series.min)}, max ${series.finiteCount == 0 ? '—' : _n(series.max)}${_cursor == null ? '' : '\n$cursor'}',
                      style: TextStyle(
                          fontSize: 11,
                          color: _channelColor(panel.sensor, series.channel),),);
                },),
              if (_fixedY.containsKey(panel.key))
                const Text(
                    'Y scale locked to the selected range; values outside it are clipped visually. Unlock to fit all visible values.',
                    style: TextStyle(fontSize: 11),),
            ],),),);
  }
}

class _Panel {
  final String key;
  final OeSensor sensor;
  final List<OeTimeSeries> series;
  _Panel(this.key, this.sensor, this.series);
  String get title =>
      '${sensor.name} · ${sensor.components[series.first.channel].group}';
  String get unit => sensor.isPcm
      ? 'signed PCM counts'
      : 'Header unit: ${sensor.components[series.first.channel].unit}';
  (double, double) get limits {
    var low = double.infinity, high = double.negativeInfinity;
    for (final s in series.where((s) => s.finiteCount > 0)) {
      low = math.min(low, s.min);
      high = math.max(high, s.max);
    }
    return low.isFinite ? (low, high) : (-1, 1);
  }
}

class _Geometry {
  final double low, high, start, end;
  final Size size;
  final double left = 78, top = 10;
  _Geometry(this.size, this.low, this.high, this.start, this.end);
  double get width => math.max(1, size.width - 90);
  double get height => math.max(1, size.height - 38);
  double x(double seconds) => left + (seconds - start) / (end - start) * width;
  double y(double value) {
    final scale = math.max(low.abs(), high.abs());
    if (low == high) {
      if (value > high) return top - height;
      if (value < low) return top + 2 * height;
      return top + height / 2;
    }
    final fraction = ((high / scale - value / scale) / (high / scale - low / scale)).clamp(-1.0, 2.0);
    return top + fraction * height;
  }
}

class _TimelinePainter extends CustomPainter {
  final _Panel panel;
  final OeTimelinePlot plot;
  final OeTimelineBounds bounds;
  final (double, double) limits;
  final double? cursor, dragStart, dragEnd;
  final bool showJumps;
  final ColorScheme colors;
  _TimelinePainter(this.panel, this.plot, this.bounds, this.limits, this.cursor,
      this.dragStart, this.dragEnd, this.showJumps, this.colors,);
  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(
        size, limits.$1, limits.$2, plot.startSeconds, plot.endSeconds,);
    void label(String text, Offset position, {bool right = false}) {
      final painter = TextPainter(
          text: TextSpan(
              text: text,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),),
          textDirection: TextDirection.ltr,)
        ..layout(maxWidth: 100);
      painter.paint(
          canvas,
          Offset(
              right ? position.dx - painter.width : position.dx, position.dy,),);
    }

    for (var tick = 0; tick <= 4; tick++) {
      final fraction = tick / 4,
          x = g.left + tick / 4 * g.width,
          y = g.top + tick / 4 * g.height;
      final grid = Paint()..color = colors.outline.withValues(alpha: .16);
      canvas.drawLine(Offset(g.left, y), Offset(g.left + g.width, y), grid);
      canvas.drawLine(Offset(x, g.top), Offset(x, g.top + g.height), grid);
      label(_n(limits.$2 * (1 - fraction) + limits.$1 * fraction),
          Offset(g.left - 6, y - 5),
          right: true,);
      label(
          '${_seconds(plot.startSeconds + fraction * (plot.endSeconds - plot.startSeconds), plot.endSeconds - plot.startSeconds)} s',
          Offset(x, size.height - 22),
          right: tick == 4,);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(g.left, g.top, g.width, g.height));
    if (showJumps) {
      for (final jump
          in plot.jumps.where((j) => j.sensorId == panel.sensor.id)) {
        canvas.drawRect(
            Rect.fromLTRB(g.x(jump.fromSeconds), g.top, g.x(jump.toSeconds),
                g.top + g.height,),
            Paint()..color = Colors.amber.withValues(alpha: .15),);
      }
    }
    for (final s in panel.series) {
      final paint = Paint()
        ..color = _channelColor(panel.sensor, s.channel)
        ..strokeWidth = 1.3;
      OeTimeBin? previous;
      Offset? previousPoint;
      final median = bounds.sensors[s.sensorId]?.medianPositivePacketIntervalUs;
      for (final b in s.bins) {
        final time = b.count == 1
            ? (b.firstTimeUs - bounds.originUs) / 1e6
            : plot.startSeconds +
                (b.index + .5) /
                    plot.binCount *
                    (plot.endSeconds - plot.startSeconds);
        final x = g.x(time);
        canvas.drawLine(Offset(x, g.y(b.min)), Offset(x, g.y(b.max)), paint);
        if (b.count == 1) {
          final point = Offset(x, g.y(b.min));
          if (previous != null &&
              previous.count == 1 &&
              b.firstFrame == previous.firstFrame + 1 &&
              b.firstTimeUs > previous.firstTimeUs &&
              median != null &&
              b.firstTimeUs - previous.firstTimeUs <= median * 5) {
            canvas.drawLine(previousPoint!, point, paint);
          }
          canvas.drawCircle(point, 1.8, paint);
          previousPoint = point;
        } else {
          if (b.min == b.max) {
            canvas.drawCircle(Offset(x, g.y(b.min)), 1.2, paint);
          }
          previousPoint = null;
        }
        previous = b;
      }
    }
    if (dragStart != null && dragEnd != null) {
      canvas.drawRect(
          Rect.fromLTRB(g.x(math.min(dragStart!, dragEnd!)), g.top,
              g.x(math.max(dragStart!, dragEnd!)), g.top + g.height,),
          Paint()..color = colors.primary.withValues(alpha: .16),);
    }
    if (cursor != null &&
        cursor! >= plot.startSeconds &&
        cursor! <= plot.endSeconds) {
      canvas.drawLine(
          Offset(g.x(cursor!), g.top),
          Offset(g.x(cursor!), g.top + g.height),
          Paint()
            ..color = colors.onSurface.withValues(alpha: .6)
            ..strokeWidth = 1,);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => true;
}

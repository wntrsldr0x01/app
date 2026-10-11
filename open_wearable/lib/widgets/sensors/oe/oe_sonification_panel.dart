import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/models/oe/oe_sonification.dart';

class OeSonificationPanel extends StatefulWidget {
  final OeRecording recording;
  final OeSensor sensor;
  final int channel;
  const OeSonificationPanel(
      {super.key,
      required this.recording,
      required this.sensor,
      required this.channel,});
  @override
  State<OeSonificationPanel> createState() => _OeSonificationPanelState();
}

class _OeSonificationPanelState extends State<OeSonificationPanel> {
  AudioPlayer? _player;
  int? _rate;
  double? _level;
  bool _busy = false;
  String? _status;
  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _player?.stop();
      final result = await compute(_render, (
        widget.recording,
        widget.sensor.id,
        widget.channel,
        _rate!,
        _level!
      ),);
      if (!mounted) return;
      setState(() => _status =
          'Source absolute peak: ${result.sourcePeak} ${widget.sensor.components[widget.channel].unit}. '
              '${result.frames} samples → ${result.frames} PCM frames; duration ${(result.frames / _rate!).toStringAsFixed(6)} s at $_rate Hz. '
              '${result.sourcePeak == 0 ? 'All-zero input produces silence.' : 'PCM = round((value / ${result.sourcePeak}) × $_level × 32767).'}',);
      await (_player ??= AudioPlayer())
          .play(BytesSource(result.wav, mimeType: 'audio/wav'));
    } catch (e) {
      if (mounted) setState(() => _status = 'Sonification failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Accelerometer sonification · synthetic audio',
              style: Theme.of(context).textTheme.titleMedium,),
          Text(
              'Selected axis: ${widget.sensor.components[widget.channel].label}',),
          const Text(
              'This is a sound representation of acceleration, not a microphone recording. The full selected axis is peak-scaled and rounded to signed 16-bit PCM. Original samples and the graph are unchanged. No DC removal, filtering or resampling. Packet gaps are omitted; original timing is not reproduced.',),
          const Text(
              'Choose an output rate explicitly. One recorded value becomes one audio frame. A higher output rate speeds up the data and raises its frequencies. The acquisition rate is not verified, so playback speed relative to real time is unknown. Low-rate motion may sound like clicks or remain inaudible.',),
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(
                labelText: 'Sonification output rate (not acquisition rate)',),
            items: [
              for (final rate in [8000, 16000, 24000, 48000, 96000])
                DropdownMenuItem(value: rate, child: Text('$rate Hz')),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    _player?.stop();
                    setState(() {
                      _rate = v;
                      _status = null;
                    });
                  },
          ),
          DropdownButtonFormField<double>(
            decoration: const InputDecoration(
                labelText: 'Explicit peak scaling for audio only',),
            items: const [
              DropdownMenuItem(
                  value: 0.25, child: Text('25% of PCM full scale'),),
              DropdownMenuItem(value: 0.5, child: Text('50% of PCM full scale')),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    _player?.stop();
                    setState(() {
                      _level = v;
                      _status = null;
                    });
                  },
          ),
          const Text(
              'Start with low speaker/headphone volume. Peak scaling does not preserve physical amplitude between recordings.',),
          if (_busy) const LinearProgressIndicator(),
          if (_status != null) SelectableText(_status!),
          Wrap(spacing: 8, children: [
            FilledButton.icon(
                onPressed:
                    _busy || _rate == null || _level == null ? null : _play,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play axis as synthetic audio'),),
            TextButton(
                onPressed: () => _player?.stop(),
                child: const Text('Stop sonification'),),
          ],),
        ],),
      ),);
}

OeSonification _render((OeRecording, int, int, int, double) args) {
  final r = args.$1, s = r.sensors[args.$2]!;
  final values = <double>[];
  for (final packet in s.packets) {
    for (var frame = 0; frame < packet.frames; frame++) {
      values.add(r.value(s, packet, frame, args.$3).toDouble());
    }
  }
  return OeSonification.build(values, args.$4, args.$5);
}

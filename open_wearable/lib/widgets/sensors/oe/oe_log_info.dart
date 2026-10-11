import 'package:flutter/material.dart';
import 'package:open_wearable/models/oe/oe_metadata.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'oe_library_storage.dart';

class OeLogInfo extends StatefulWidget {
  final OeRecording recording;
  final String filename;
  const OeLogInfo({super.key, required this.recording, required this.filename});
  @override
  State<OeLogInfo> createState() => _OeLogInfoState();
}

class _OeLogInfoState extends State<OeLogInfo> {
  Map<String, String> _notes = {};
  String? _error;
  int? _firstPacket, _lastPacket;
  @override
  void initState() {
    super.initState();
    for (final sensor in widget.recording.sensors.values) {
      for (final packet in sensor.packets) {
        if (_firstPacket == null || packet.timestampUs < _firstPacket!) {
          _firstPacket = packet.timestampUs;
        }
        if (_lastPacket == null || packet.timestampUs > _lastPacket!) {
          _lastPacket = packet.timestampUs;
        }
      }
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final notes = await readOeAnnotations(widget.recording.digest);
      if (mounted) setState(() => _notes = notes);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load your notes: $e');
    }
  }

  Future<void> _edit() async {
    final label = TextEditingController(text: _notes['label']);
    final place = TextEditingController(text: _notes['place']);
    final notes = TextEditingController(text: _notes['notes']);
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Label this recording'),
              content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'These are your annotations, stored separately from the original recording. No GPS location was recorded in this OE header.',),
                    TextField(
                        controller: label,
                        decoration:
                            const InputDecoration(labelText: 'Session name'),
                        maxLength: 120,),
                    TextField(
                        controller: place,
                        decoration: const InputDecoration(
                            labelText: 'Place (entered by you)',),
                        maxLength: 200,),
                    TextField(
                        controller: notes,
                        decoration: const InputDecoration(
                            labelText: 'Notes / activity / experiment',),
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 4000,),
                  ],),),),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),),
                FilledButton(
                    onPressed: () => Navigator.pop(context, {
                          'label': label.text.trim(),
                          'place': place.text.trim(),
                          'notes': notes.text.trim(),
                        }),
                    child: const Text('Save labels'),),
              ],
            ),);
    // The route may still be animating with its text fields; avoid disposing
    // their controllers before the dialog has left the widget tree.
    if (result == null) return;
    try {
      await saveOeAnnotations(widget.recording.digest, result);
      if (mounted) {
        setState(() {
          _notes = result;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save your notes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    final utc = oeCalendarTime(r.timestampUs);
    final first = _firstPacket, last = _lastPacket;
    final place = _notes['place'] ?? '';
    return Card(
        child: ExpansionTile(
            title: Text((_notes['label'] ?? '').isEmpty
                ? widget.filename
                : _notes['label']!,),
            subtitle: Text(
                'Recording details · expand for metadata and labels\n${oeEarLabel(r.side)} · ${oeDateLabel(r.timestampUs)}\n${place.isEmpty ? "Location not recorded" : "$place (user-entered)"}',),
            children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        (_notes['label'] ?? '').isEmpty
                            ? 'Recording summary'
                            : _notes['label']!,
                        style: Theme.of(context).textTheme.titleLarge,),
                    SelectableText(
                        'File: ${widget.filename}\n${oeEarLabel(r.side)} · Device ID: 0x${r.deviceId}\nFormat: OE v3 · ${(r.bytes.length / 1048576).toStringAsFixed(2)} MiB (${r.bytes.length} bytes)',),
                    const SizedBox(height: 12),
                    Text('Date and time',
                        style: Theme.of(context).textTheme.titleMedium,),
                    SelectableText(utc == null
                        ? 'Calendar date unavailable. The header clock is outside the supported calendar interpretation range (2000–2100); it may be device uptime.'
                        : 'Header time on this Mac: ${oeDateLabel(r.timestampUs)}\nHeader time in UTC: ${utc.toIso8601String()}',),
                    const Text(
                        'Calendar times interpret device microseconds as Unix time. The log does not record whether the clock was synchronized or which timezone you recorded in. These are not independently verified dates.',),
                    if (first != null && last != null)
                      SelectableText(
                          'Earliest packet: ${oeCalendarTime(first)?.toIso8601String() ?? "$first µs"}\nLatest packet: ${oeCalendarTime(last)?.toIso8601String() ?? "$last µs"}\nPacket timestamp range: ${((last - first) / 1e6).toStringAsFixed(6)} s (includes gaps; excludes unknown final-sample duration).',),
                    const SizedBox(height: 12),
                    Text('Place and session notes',
                        style: Theme.of(context).textTheme.titleMedium,),
                    SelectableText(place.isEmpty
                        ? 'Location: not recorded in the OE header; no place entered.'
                        : 'Place: $place (user-entered, not recorded GPS)',),
                    if ((_notes['notes'] ?? '').isNotEmpty)
                      SelectableText('Your notes: ${_notes['notes']}'),
                    TextButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.edit_outlined),
                        label:
                            const Text('Edit session name, place and notes'),),
                    if (!oePersistentStorage)
                      const Text(
                          'Browser annotations are temporary for this session.',),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,),),
                    const SizedBox(height: 12),
                    Text('What is actually recorded',
                        style: Theme.of(context).textTheme.titleMedium,),
                    for (final sensor in r.sensors.values)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SelectableText(
                            '${sensor.name} · SID ${sensor.id}: ${sensor.frameCount == 0 ? "declared in header, no recorded samples" : "${sensor.frameCount} frames per channel · ${sensor.packets.length} packets"}\n${sensor.components.map((c) => "${c.label} [${c.unit.isEmpty ? 'unit not supplied' : c.unit}]").join(' · ')}',
                          ),),
                    const SizedBox(height: 8),
                    const Text(
                        'Active sample rates, device firmware version, GPS coordinates and recording-time timezone are not stored in this header. Header default rates are configuration defaults, not proof of the rates used.',),
                    Text(
                        'Import status: ${r.incompleteReason == null ? "all packets parsed" : r.hasExactDuplicatedTail ? "exact duplicated tail retained; ${r.bytes.length - r.validatedBytes} bytes not counted twice" : "partial interpretation; ${r.bytes.length - r.validatedBytes} bytes remain unparsed"}.',),
                  ],),),
        ],),);
  }
}

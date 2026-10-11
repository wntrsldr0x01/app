import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'oe_library_entry.dart';
import 'package:open_wearable/models/oe/oe_metadata.dart';
import 'oe_library_storage.dart';
import 'oe_viewer_page.dart';

/// Import and reopen verified copies of original SD-card recordings.
class OeLibraryPage extends StatefulWidget {
  const OeLibraryPage({super.key});
  @override
  State<OeLibraryPage> createState() => _OeLibraryPageState();
}

class _OeLibraryPageState extends State<OeLibraryPage> {
  List<OeLibraryEntry> _entries = [];
  bool _busy = false;
  Map<String, Map<String, String>> _annotations = {};
  String? _error;
  Uint8List? _failedBytes;
  String? _failedName;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final entries = await listOeOriginals();
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (entry.timestampUs != null) continue;
        final bytes = await readOeOriginal(entry);
        final recording = await compute(OeRecording.parse, bytes);
        final enriched = OeLibraryEntry(entry.name, entry.digest, entry.size,
            timestampUs: recording.timestampUs,
            side: recording.side,
            deviceId: recording.deviceId,);
        await saveOeOriginal(enriched, bytes);
        entries[i] = enriched;
      }
      final annotations = <String, Map<String, String>>{};
      for (final entry in entries) {
        annotations[entry.digest] = await readOeAnnotations(entry.digest);
      }
      if (mounted) {
        setState(() {
          _entries = entries;
          _annotations = annotations;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open({OeLibraryEntry? entry}) async {
    setState(() {
      _busy = true;
      _error = null;
      _failedBytes = null;
      _failedName = null;
    });
    try {
      Uint8List bytes;
      String name;
      if (entry == null) {
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['oe'],
        );
        if (files.isEmpty) return;
        final file = files.first;
        final length = await file.length();
        if (length != null && length > OeRecording.maxFileBytes) {
          throw const FormatException(
            'Maximum supported file size is 128 MiB.',
          );
        }
        bytes = await file.readAsBytes();
        name = file.name;
      } else {
        bytes = await readOeOriginal(entry);
        name = entry.name;
      }
      OeRecording recording;
      try {
        recording = await compute(OeRecording.parse, bytes);
      } on FormatException {
        _failedBytes = bytes;
        _failedName = name;
        rethrow;
      }
      if (entry == null || entry.timestampUs == null) {
        await saveOeOriginal(
          OeLibraryEntry(name, recording.digest, bytes.length,
              timestampUs: recording.timestampUs,
              side: recording.side,
              deviceId: recording.deviceId,),
          bytes,
        );
        await _reload();
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OeViewerPage(name: name, recording: recording),
        ),
      );
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = 'Import/view blocked: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recorded OE logs')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Import a self-describing .oe v3 recording from Files or an SD card. No wearable connection is required.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _open,
              icon: const Icon(Icons.file_open),
              label: const Text('Import .oe file'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_failedBytes != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          final recording = await compute(
                            OeRecording.inspectPrefix,
                            _failedBytes!,
                          );
                          if (!context.mounted) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => OeViewerPage(
                                name: _failedName!,
                                recording: recording,
                              ),
                            ),
                          );
                        } catch (e) {
                          if (mounted) {
                            setState(
                              () => _error = 'Prefix inspection blocked: $e',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text(
                  'Inspect parsed prefix · unparsed tail',
                ),
              ),
            const SizedBox(height: 12),
            Text(
              oePersistentStorage
                  ? 'Original bytes are copied into the app and verified with SHA-256 on every reopen. The source file is never modified.'
                  : 'Browser imports are temporary. Re-import after closing this page; no persistent copy is stored.',
            ),
            const SizedBox(height: 24),
            for (final entry in _entries)
              Card(
                child: ListTile(
                  title: Text(
                      (_annotations[entry.digest]?['label'] ?? '').isEmpty
                          ? entry.name
                          : _annotations[entry.digest]!['label']!,),
                  subtitle: Text(
                    '${entry.name}\n${oeEarLabel(entry.side)} · ${oeDateLabel(entry.timestampUs)}\nPlace: ${(_annotations[entry.digest]?["place"] ?? "").isEmpty ? "not recorded / not entered" : "${_annotations[entry.digest]!["place"]} (user-entered)"}\n${entry.size} bytes · SHA-256 ${entry.digest.substring(0, 12)}…',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _open(entry: entry),
                ),
              ),
          ],
        ),
      );
}

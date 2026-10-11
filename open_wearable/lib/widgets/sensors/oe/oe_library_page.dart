import 'oe_workspace.dart';
import 'oe_log_comparison_page.dart';
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
  final Set<String> _selected = {};
  String _query = '';
  int? _ear;
  bool _newestFirst = true;
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<OeLibraryEntry> get _visibleEntries {
    final q = _query.trim().toLowerCase();
    final entries = _entries.where((e) {
      final notes = _annotations[e.digest] ?? {};
      return (_ear == null || e.side == _ear) &&
          '${e.name} ${e.digest} ${notes.values.join(' ')}'
              .toLowerCase()
              .contains(q);
    }).toList();
    entries.sort((a, b) {
      final order = (b.timestampUs ?? 0).compareTo(a.timestampUs ?? 0);
      return (_newestFirst ? order : -order);
    });
    return entries;
  }

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
        final enriched = OeLibraryEntry(
          entry.name,
          entry.digest,
          entry.size,
          timestampUs: recording.timestampUs,
          side: recording.side,
          deviceId: recording.deviceId,
        );
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
          OeLibraryEntry(
            name,
            recording.digest,
            bytes.length,
            timestampUs: recording.timestampUs,
            side: recording.side,
            deviceId: recording.deviceId,
          ),
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

  Future<void> _compare() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final logs = <OeComparisonLog>[];
      for (final entry in _entries.where((e) => _selected.contains(e.digest))) {
        final bytes = await readOeOriginal(entry);
        final recording = await compute(OeRecording.parse, bytes);
        logs.add(OeComparisonLog(entry.name, recording));
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OeLogComparisonPage(logs: logs),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Comparison blocked: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspectPrefix() async {
    setState(() => _busy = true);
    try {
      final recording = await compute(OeRecording.inspectPrefix, _failedBytes!);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              OeViewerPage(name: _failedName!, recording: recording),),);
    } catch (e) {
      if (mounted) setState(() => _error = 'Prefix inspection blocked: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries;
    return Scaffold(
      appBar: AppBar(title: const Text('Recorded OE logs')),
      body: OeWorkspace(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your recordings',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),),
                const SizedBox(height: 4),
                Text(
                    '${_entries.length} stored logs · inspect signals, listen, and compare',),
              ],),
              FilledButton.icon(
                  onPressed: _busy ? null : _open,
                  icon: const Icon(Icons.add),
                  label: const Text('Import .oe file'),),
            ],),
        const SizedBox(height: 20),
        OeWorkCard(
            padding: const EdgeInsets.all(14),
            child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                      width: 320,
                      child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                              hintText: 'Search name, label, place or hash',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () {
                                        _search.clear();
                                        setState(() => _query = '');
                                      },
                                      icon: const Icon(Icons.close),),),
                          onChanged: (v) => setState(() => _query = v),),),
                  for (final choice in <int?, String>{
                    null: 'All ears',
                    0: 'Left',
                    1: 'Right',
                  }.entries)
                    ChoiceChip(
                        label: Text(choice.value),
                        selected: _ear == choice.key,
                        onSelected: (_) => setState(() => _ear = choice.key),),
                  TextButton.icon(
                      onPressed: () =>
                          setState(() => _newestFirst = !_newestFirst),
                      icon: const Icon(Icons.sort),
                      label:
                          Text(_newestFirst ? 'Newest first' : 'Oldest first'),),
                ],),),
        const SizedBox(height: 12),
        Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${entries.length} shown · ${_selected.length} selected',
                  style: Theme.of(context).textTheme.titleSmall,),
              OutlinedButton.icon(
                  onPressed: _busy || _selected.length < 2 ? null : _compare,
                  icon: const Icon(Icons.compare_arrows),
                  label: Text('Compare selected logs (${_selected.length})'),),
              TextButton(
                  onPressed: _busy || entries.isEmpty
                      ? null
                      : () => setState(
                          () => _selected.addAll(entries.map((e) => e.digest)),),
                  child: const Text('Select shown'),),
              if (_selected.isNotEmpty)
                TextButton(
                    onPressed: _busy ? null : () => setState(_selected.clear),
                    child: const Text('Clear selection'),),
            ],),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),),),
        if (_failedBytes != null)
          TextButton(
              onPressed: _busy ? null : _inspectPrefix,
              child: const Text('Inspect parsed prefix · unparsed tail'),),
        const SizedBox(height: 12),
        Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        _entries.isEmpty ? Icons.folder_open : Icons.search_off,
                        size: 52,
                        color: Theme.of(context).colorScheme.primary,),
                    const SizedBox(height: 16),
                    Text(
                        _entries.isEmpty
                            ? 'Start with a recording'
                            : 'No matching recordings',
                        style: Theme.of(context).textTheme.titleLarge,),
                    const SizedBox(height: 8),
                    Text(_entries.isEmpty
                        ? 'Import an .oe file from your computer or SD card.'
                        : 'Try a different search or ear filter.',),
                  ],),)
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _entryCard(entries[i]),),),
        const SizedBox(height: 10),
        Text(
            oePersistentStorage
                ? 'Original files stay unchanged. SHA-256 is checked whenever you open or compare a log.'
                : 'Browser imports are temporary. Re-import after closing this page.',
            style: Theme.of(context).textTheme.bodySmall,),
      ],),),
    );
  }

  Widget _entryCard(OeLibraryEntry entry) {
    final annotation = _annotations[entry.digest] ?? {};
    final label = annotation['label'] ?? '', place = annotation['place'] ?? '';
    final selected = _selected.contains(entry.digest);
    return Material(
      color: selected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .28) : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .6))),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Checkbox(
            value: selected,
            semanticLabel: 'Select ${entry.name} for comparison',
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      if (v!) {
                        _selected.add(entry.digest);
                      } else {
                        _selected.remove(entry.digest);
                      }
                    }),),
        title: Text(label.isEmpty ? entry.name : label,
            style: const TextStyle(fontWeight: FontWeight.w600),),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (label.isNotEmpty) Text(entry.name),
              Wrap(spacing: 8, runSpacing: 6, children: [
                OeTag(oeEarLabel(entry.side), icon: Icons.hearing),
                OeTag(oeDateLabel(entry.timestampUs), icon: Icons.schedule),
                OeTag('${(entry.size / 1048576).toStringAsFixed(1)} MiB',
                    icon: Icons.description_outlined,),
              ],),
              const SizedBox(height: 8),
              Text(
                  place.isEmpty
                      ? 'Location not recorded / not entered'
                      : '$place · user-entered location',
                  style: Theme.of(context).textTheme.bodySmall,),
            ],),),
        trailing: Tooltip(
            message: 'Open recording',
            child: Icon(Icons.arrow_forward,
                color: Theme.of(context).colorScheme.primary,),),
        onTap: _busy ? null : () => _open(entry: entry),
      ),
    );
  }
}

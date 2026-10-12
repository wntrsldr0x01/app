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
  bool _archived = false;
  String _view = 'list';
  final _search = TextEditingController();
  final _listScroll = ScrollController();
  final _tableScroll = ScrollController();
  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    _tableScroll.dispose();
    super.dispose();
  }

  List<OeLibraryEntry> get _visibleEntries {
    final q = _query.trim().toLowerCase();
    final entries = _entries.where((e) {
      final notes = _annotations[e.digest] ?? {};
      return (notes['archived'] == 'true') == _archived &&
          (_ear == null || e.side == _ear) &&
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
  String? _importStatus;
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

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
      _importStatus = null;
      _failedBytes = null;
      _failedName = null;
    });
    try {
      // In file_picker v13, pickFiles is the multiple-selection API.
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Import OE recordings',
        type: FileType.custom,
        allowedExtensions: ['oe'],
      );
      if (files.isEmpty) return;
      final known = _entries.map((e) => e.digest).toSet();
      var imported = 0, duplicates = 0;
      final failures = <String>[];
      OeRecording? singleRecording;
      for (var i = 0; i < files.length; i++) {
        if (!mounted) return;
        final file = files[i];
        setState(
          () => _importStatus =
              'Importing ${i + 1}/${files.length}: ${file.name}',
        );
        try {
          final length = await file.length();
          if (length != null && length > OeRecording.maxFileBytes) {
            throw const FormatException(
              'Maximum supported file size is 128 MiB.',
            );
          }
          final bytes = await file.readAsBytes();
          OeRecording recording;
          try {
            recording = await compute(OeRecording.parse, bytes);
          } on FormatException {
            // Prefix inspection is available for the last malformed file.
            _failedBytes = bytes;
            _failedName = file.name;
            rethrow;
          }
          if (known.contains(recording.digest)) {
            duplicates++;
          } else {
            await saveOeOriginal(
              OeLibraryEntry(
                file.name,
                recording.digest,
                bytes.length,
                timestampUs: recording.timestampUs,
                side: recording.side,
                deviceId: recording.deviceId,
              ),
              bytes,
            );
            known.add(recording.digest);
            imported++;
          }
          if (files.length == 1) singleRecording = recording;
        } catch (error) {
          failures.add('${file.name}: $error');
        }
      }
      await _reload();
      if (!mounted) return;
      setState(() {
        _importStatus =
            '$imported imported · $duplicates already in library · ${failures.length} failed';
        if (failures.isNotEmpty) _error = failures.join('\n');
        // Newly imported originals belong to Active; clear restrictive filters.
        if (imported > 0) {
          _archived = false;
          _ear = null;
          _query = '';
          _search.clear();
        }
      });
      if (singleRecording != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OeViewerPage(
              name: files.single.name,
              recording: singleRecording!,
            ),
          ),
        );
        await _reload();
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Import blocked: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open({required OeLibraryEntry entry}) async {
    setState(() {
      _busy = true;
      _error = null;
      _failedBytes = null;
      _failedName = null;
    });
    try {
      final bytes = await readOeOriginal(entry);
      final name = entry.name;
      OeRecording recording;
      try {
        recording = await compute(OeRecording.parse, bytes);
      } on FormatException {
        _failedBytes = bytes;
        _failedName = name;
        rethrow;
      }
      if (entry.timestampUs == null) {
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

  Future<void> _compare({bool leftRight = false}) async {
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
      if (leftRight) {
        if (logs.length != 2 ||
            logs
                .map((l) => l.recording.side)
                .toSet()
                .difference({0, 1}).isNotEmpty ||
            logs.map((l) => l.recording.side).toSet().length != 2) {
          throw const FormatException(
            'Select exactly one left and one right log.',
          );
        }
        logs.sort((a, b) => a.recording.side.compareTo(b.recording.side));
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OeLogComparisonPage(logs: logs, leftRight: leftRight),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Comparison blocked: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveSelected() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final digest in _selected.toList()) {
        final notes = await readOeAnnotations(digest);
        await saveOeAnnotations(
          digest,
          {...notes, 'archived': (!_archived).toString()},
        );
      }
      _selected.clear();
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = 'Archive update failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspectPrefix() async {
    setState(() => _busy = true);
    try {
      final recording = await compute(OeRecording.inspectPrefix, _failedBytes!);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              OeViewerPage(name: _failedName!, recording: recording),
        ),
      );
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your recordings',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_entries.length} stored logs · inspect signals, listen, and compare',
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.add),
                  label: const Text('Import .oe files'),
                ),
              ],
            ),
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
                                icon: const Icon(Icons.close),
                              ),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Active'),
                    selected: !_archived,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                              _archived = false;
                              _selected.clear();
                            }),
                  ),
                  ChoiceChip(
                    label: const Text('Archived'),
                    selected: _archived,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                              _archived = true;
                              _selected.clear();
                            }),
                  ),
                  for (final choice in <int?, String>{
                    null: 'All ears',
                    0: 'Left',
                    1: 'Right',
                  }.entries)
                    ChoiceChip(
                      label: Text(choice.value),
                      selected: _ear == choice.key,
                      onSelected: (_) => setState(() => _ear = choice.key),
                    ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'list',
                        label: Text('List'),
                        icon: Icon(Icons.view_list_outlined),
                      ),
                      ButtonSegment(
                        value: 'tiles',
                        label: Text('Tiles'),
                        icon: Icon(Icons.grid_view),
                      ),
                      ButtonSegment(
                        value: 'table',
                        label: Text('Table'),
                        icon: Icon(Icons.table_rows_outlined),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (values) {
                      if (_listScroll.hasClients) _listScroll.jumpTo(0);
                      setState(() => _view = values.single);
                    },
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _newestFirst = !_newestFirst),
                    icon: const Icon(Icons.sort),
                    label: Text(_newestFirst ? 'Newest first' : 'Oldest first'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${entries.length} shown · ${_selected.length} selected',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _selected.length < 2 ? null : _compare,
                  icon: const Icon(Icons.compare_arrows),
                  label: Text('Compare selected logs (${_selected.length})'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _selected.length != 2
                      ? null
                      : () => _compare(leftRight: true),
                  icon: const Icon(Icons.hearing),
                  label: const Text('Compare left + right'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy || _selected.isEmpty ? null : _archiveSelected,
                  icon: Icon(
                    _archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  label:
                      Text(_archived ? 'Restore selected' : 'Archive selected'),
                ),
                TextButton(
                  onPressed: _busy || entries.isEmpty
                      ? null
                      : () => setState(
                            () =>
                                _selected.addAll(entries.map((e) => e.digest)),
                          ),
                  child: const Text('Select shown'),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: _busy ? null : () => setState(_selected.clear),
                    child: const Text('Clear selection'),
                  ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_importStatus != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_importStatus!),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_failedBytes != null)
              TextButton(
                onPressed: _busy ? null : _inspectPrefix,
                child: const Text('Inspect parsed prefix · unparsed tail'),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _entries.isEmpty
                                ? Icons.folder_open
                                : Icons.search_off,
                            size: 52,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _entries.isEmpty
                                ? 'Start with a recording'
                                : 'No matching recordings',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _entries.isEmpty
                                ? 'Import an .oe file from your computer or SD card.'
                                : 'Try a different search or ear filter.',
                          ),
                        ],
                      ),
                    )
                  : _recordingBrowser(entries),
            ),
            const SizedBox(height: 10),
            Text(
              oePersistentStorage
                  ? 'Original files stay unchanged. SHA-256 is checked whenever you open or compare a log.'
                  : 'Browser imports are temporary. Re-import after closing this page.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _select(OeLibraryEntry entry, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(entry.digest);
      } else {
        _selected.remove(entry.digest);
      }
    });
  }

  Widget _selection(OeLibraryEntry entry) => Checkbox(
        value: _selected.contains(entry.digest),
        semanticLabel: 'Select ${entry.name} for comparison',
        onChanged: _busy ? null : (value) => _select(entry, value ?? false),
      );

  Widget _verticalBrowser(Widget child) => Scrollbar(
        controller: _listScroll,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        thickness: 10,
        child: child,
      );

  Widget _recordingBrowser(List<OeLibraryEntry> entries) {
    if (_view == 'tiles') {
      return _verticalBrowser(
        GridView.builder(
          key: const PageStorageKey('oe-library-tiles'),
          controller: _listScroll,
          primary: false,
          padding: const EdgeInsets.only(right: 20, bottom: 20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 460,
            mainAxisExtent: 240,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: entries.length,
          itemBuilder: (_, i) => _entryTile(entries[i]),
        ),
      );
    }
    if (_view == 'table') {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth < 1050 ? 1050.0 : constraints.maxWidth;
          return Scrollbar(
            controller: _tableScroll,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _tableScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    _tableRow(null),
                    const Divider(height: 1),
                    Expanded(
                      child: _verticalBrowser(
                        ListView.builder(
                          key: const PageStorageKey('oe-library-table'),
                          controller: _listScroll,
                          primary: false,
                          padding: const EdgeInsets.only(right: 20, bottom: 20),
                          itemExtent: 64,
                          itemCount: entries.length,
                          itemBuilder: (_, i) => _tableRow(entries[i]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    return _verticalBrowser(
      ListView.separated(
        key: const PageStorageKey('oe-library-recordings'),
        controller: _listScroll,
        primary: false,
        padding: const EdgeInsets.only(right: 20, bottom: 20),
        itemCount: entries.length,
        separatorBuilder: (_, i) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _entryCard(entries[i]),
      ),
    );
  }

  Widget _entryTile(OeLibraryEntry entry) {
    final notes = _annotations[entry.digest] ?? {};
    final label = notes['label'] ?? '';
    return Card(
      margin: EdgeInsets.zero,
      color: _selected.contains(entry.digest)
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : () => _open(entry: entry),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _selection(entry),
                  Expanded(child: Text(oeEarLabel(entry.side))),
                  Text('${(entry.size / 1048576).toStringAsFixed(1)} MiB'),
                ],
              ),
              Tooltip(
                message: label.isEmpty ? entry.name : label,
                child: Text(
                  label.isEmpty ? entry.name : label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (label.isNotEmpty)
                Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Text(
                oeDateLabel(entry.timestampUs),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                (notes['place'] ?? '').isEmpty
                    ? 'Location not recorded / not entered'
                    : '${notes['place']} · user-entered',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              const Row(
                children: [
                  Text('Open recording'),
                  Spacer(),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableRow(OeLibraryEntry? entry) {
    final notes =
        entry == null ? <String, String>{} : _annotations[entry.digest] ?? {};
    final label = notes['label'] ?? '';
    Widget cell(String text) => Tooltip(
          message: text,
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: entry == null
                ? const Icon(Icons.check_box_outline_blank, size: 18)
                : _selection(entry),
          ),
          Expanded(
            flex: 4,
            child: entry == null
                ? cell('Recording / filename')
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cell(label.isEmpty ? entry.name : label),
                      if (label.isNotEmpty) cell(entry.name),
                    ],
                  ),
          ),
          SizedBox(
            width: 110,
            child: cell(entry == null ? 'Ear' : oeEarLabel(entry.side)),
          ),
          SizedBox(
            width: 330,
            child: cell(
              entry == null
                  ? 'Recorded time (clock interpretation)'
                  : oeDateLabel(entry.timestampUs),
            ),
          ),
          SizedBox(
            width: 85,
            child: cell(
              entry == null
                  ? 'Size'
                  : '${(entry.size / 1048576).toStringAsFixed(1)} MiB',
            ),
          ),
          Expanded(
            flex: 2,
            child: cell(
              entry == null ? 'Place (user-entered)' : (notes['place'] ?? '—'),
            ),
          ),
          const SizedBox(width: 36, child: Icon(Icons.arrow_forward, size: 18)),
        ],
      ),
    );
    if (entry == null) return SizedBox(height: 48, child: row);
    return Material(
      color: _selected.contains(entry.digest)
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      child:
          InkWell(onTap: _busy ? null : () => _open(entry: entry), child: row),
    );
  }

  Widget _entryCard(OeLibraryEntry entry) {
    final annotation = _annotations[entry.digest] ?? {};
    final label = annotation['label'] ?? '', place = annotation['place'] ?? '';
    final selected = _selected.contains(entry.digest);
    return Material(
      color: selected
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: .28)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: .6),
        ),
      ),
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
                  }),
        ),
        title: Text(
          label.isEmpty ? entry.name : label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty) Text(entry.name),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OeTag(oeEarLabel(entry.side), icon: Icons.hearing),
                  OeTag(oeDateLabel(entry.timestampUs), icon: Icons.schedule),
                  OeTag(
                    '${(entry.size / 1048576).toStringAsFixed(1)} MiB',
                    icon: Icons.description_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                place.isEmpty
                    ? 'Location not recorded / not entered'
                    : '$place · user-entered location',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        trailing: Tooltip(
          message: 'Open recording',
          child: Icon(
            Icons.arrow_forward,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        onTap: _busy ? null : () => _open(entry: entry),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'oe_library_entry.dart';

const oePersistentStorage = true;
Future<Directory> _directory() async {
  final root = await getApplicationSupportDirectory();
  return Directory('${root.path}/oe_originals').create(recursive: true);
}

/// Saves exact original bytes and verifies the on-disk copy before indexing it.
Future<void> saveOeOriginal(OeLibraryEntry entry, Uint8List bytes) async {
  final root = await _directory();
  if (sha256.convert(bytes).toString() != entry.digest) {
    throw StateError('Import checksum mismatch');
  }
  final file = File('${root.path}/${entry.digest}.oe');
  if (!await file.exists()) {
    final temp = File('${file.path}.pending');
    await temp.writeAsBytes(bytes, flush: true);
    if (sha256.convert(await temp.readAsBytes()).toString() != entry.digest) {
      throw StateError('Saved copy checksum mismatch');
    }
    await temp.rename(file.path);
  }
  await readOeOriginal(entry);
  final meta = File('${root.path}/${entry.digest}.json');
  final pending = File('${meta.path}.pending');
  await pending.writeAsString(
    jsonEncode(
      {
        'name': entry.name,
        'sha256': entry.digest,
        'size': bytes.length,
        'timestamp_us': entry.timestampUs,
        'side': entry.side,
        'device_id': entry.deviceId,
      },
    ),
    flush: true,
  );
  await pending.rename(meta.path);
}

Future<List<OeLibraryEntry>> listOeOriginals() async {
  final root = await _directory();
  final entries = <OeLibraryEntry>[];
  await for (final file in root.list()) {
    if (!file.path.endsWith('.json')) continue;
    final m = jsonDecode(await File(file.path).readAsString())
        as Map<String, dynamic>;
    final hash = m['sha256'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid stored OE digest');
    }
    entries.add(OeLibraryEntry(m['name'] as String, hash, m['size'] as int,
        timestampUs: m['timestamp_us'] as int?,
        side: m['side'] as int?,
        deviceId: m['device_id'] as String?,),);
  }
  entries.sort((a, b) => a.name.compareTo(b.name));
  return entries;
}

/// Every reopen verifies integrity. A mismatch blocks viewing, never repairs.
Future<Uint8List> readOeOriginal(OeLibraryEntry entry) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.digest)) {
    throw const FormatException('Invalid digest');
  }
  final root = await _directory();
  final file = File('${root.path}/${entry.digest}.oe');
  if (await file.length() != entry.size) {
    throw StateError('Stored original size changed');
  }
  final bytes = await file.readAsBytes();
  if (sha256.convert(bytes).toString() != entry.digest) {
    throw StateError('Stored original checksum changed. Viewing blocked.');
  }
  return bytes;
}

Future<File> _annotationFile(String digest) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
    throw const FormatException('Invalid digest');
  }
  final root = await _directory();
  final directory =
      await Directory('${root.path}/annotations').create(recursive: true);
  return File('${directory.path}/$digest.json');
}

Future<Map<String, String>> readOeAnnotations(String digest) async {
  final file = await _annotationFile(digest);
  if (!await file.exists()) return {};
  return Map<String, String>.from(jsonDecode(await file.readAsString()) as Map);
}

Future<void> saveOeAnnotations(
    String digest, Map<String, String> values,) async {
  final file = await _annotationFile(digest);
  final pending = File('${file.path}.pending');
  await pending.writeAsString(jsonEncode(values), flush: true);
  await pending.rename(file.path);
}

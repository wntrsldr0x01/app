import 'dart:typed_data';
import 'oe_library_entry.dart';

// Browser imports remain inspectable; do not imply durable browser storage.
const oePersistentStorage = false;
Future<List<OeLibraryEntry>> listOeOriginals() async => [];
Future<void> saveOeOriginal(OeLibraryEntry entry, Uint8List bytes) async {}
Future<Uint8List> readOeOriginal(OeLibraryEntry entry) => Future.error(
      UnsupportedError('Re-import the original file in the browser.'),
    );

final _annotations = <String, Map<String, String>>{};
Future<Map<String, String>> readOeAnnotations(String digest) async =>
    _annotations[digest] ?? {};
Future<void> saveOeAnnotations(
    String digest, Map<String, String> values,) async {
  _annotations[digest] = Map.of(values);
}

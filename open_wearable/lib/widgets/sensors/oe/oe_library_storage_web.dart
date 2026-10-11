import 'dart:typed_data';
import 'oe_library_entry.dart';

// Browser imports remain inspectable; do not imply durable browser storage.
const oePersistentStorage = false;
Future<List<OeLibraryEntry>> listOeOriginals() async => [];
Future<void> saveOeOriginal(OeLibraryEntry entry, Uint8List bytes) async {}
Future<Uint8List> readOeOriginal(OeLibraryEntry entry) => Future.error(
      UnsupportedError('Re-import the original file in the browser.'),
    );

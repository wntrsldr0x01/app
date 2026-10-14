import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Native players identify a derived WAV by its extension and file header.
Future<Source> oePlaybackSource(Uint8List bytes) async {
  final root = await getTemporaryDirectory();
  final directory =
      await Directory('${root.path}/oe_playback').create(recursive: true);
  final file = File('${directory.path}/${sha256.convert(bytes)}.wav');
  await file.writeAsBytes(bytes, flush: true);
  return DeviceFileSource(file.path);
}

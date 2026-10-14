import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

Future<Source> oePlaybackSource(Uint8List bytes) async =>
    BytesSource(bytes, mimeType: 'audio/wav');

import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_playback_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native playback uses distinct named WAV files with exact bytes',
      () async {
    final directory = Directory.systemTemp.createTempSync('oe_playback_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      directory.deleteSync(recursive: true);
    });
    final bytes = Uint8List.fromList([82, 73, 70, 70, 1, 2]);
    final source = await oePlaybackSource(bytes) as DeviceFileSource;
    expect(source.path.endsWith('.wav'), isTrue);
    expect(await File(source.path).readAsBytes(), orderedEquals(bytes));
    final second =
        await oePlaybackSource(Uint8List.fromList([82, 73, 70, 70, 3]))
            as DeviceFileSource;
    expect(second.path, isNot(source.path));
    expect(await File(source.path).readAsBytes(), orderedEquals(bytes));
  });
}

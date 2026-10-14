import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/log_file_manager.dart';
import 'package:open_wearable/models/recording_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'recording evidence persists as JSON and appears in exported log inventory',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('recording_diagnostics_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    final manager = await LogFileManager.create();
    try {
      RecordingDiagnostics.record('setting_failed', {
        'device_id': 'right',
        'sensor': 'Microphones',
        'error': 'No acknowledgement',
      });
      final file = File(
        '${manager.logDirectoryPath}/recording/recording-diagnostics.log',
      );
      for (var attempt = 0; attempt < 50; attempt++) {
        if (file.existsSync() &&
            file.readAsStringSync().contains('setting_failed')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final events = file
          .readAsLinesSync()
          .where((line) => line.startsWith('{'))
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(
        events.singleWhere(
          (event) => event['event'] == 'setting_failed',
        )['device_id'],
        'right',
      );
      expect(
        (await manager.logFiles).map((file) => file.path),
        contains(file.path),
      );
    } finally {
      manager.dispose();
      await manager.logger.close();
      await manager.libLogger.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      directory.deleteSync(recursive: true);
    }
  });
}

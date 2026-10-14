import 'dart:convert';

/// Low-volume control-plane evidence; never records sensor samples.
class RecordingDiagnostics {
  static void Function(String)? sink;
  static int _sequence = 0;
  static final String session = DateTime.now().toUtc().toIso8601String();

  static void record(String event, [Map<String, Object?> fields = const {}]) {
    final line = jsonEncode({
      ...fields,
      'event': event,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'session': session,
      'sequence': ++_sequence,
    });
    sink?.call('RECORDING_DIAGNOSTIC $line');
  }
}

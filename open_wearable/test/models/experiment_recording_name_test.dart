import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_wearable/models/experiment_recording_name.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('filename includes effort, paragraph, take and readable time', () {
    expect(
      ExperimentRecordingNames.prefix(
        'IMU 100Hz',
        'vocal',
        3,
        2,
        startedAt: DateTime(2026, 10, 13, 14, 35, 9),
      ),
      'IMU_100Hz_vocal_p003_t002_13-10-26_14-35-09_',
    );
  });
  test('condition labels fit firmware limit and baseline has no passage ID',
      () {
    final prefix = ExperimentRecordingNames.prefix(
      'Long profile name',
      'silent',
      120,
      999999,
      environment: 'ambient',
      posture: 'standing',
      startedAt: DateTime(2026, 10, 14),
    );
    expect(prefix, contains('_silent_p120_t999999_amb_sta_'));
    expect(prefix.length, lessThanOrEqualTo(63));
    final baseline = ExperimentRecordingNames.prefix(
      'Long profile name',
      'empty',
      120,
      999999,
      environment: 'silent',
      posture: 'sitting',
      startedAt: DateTime(2026, 10, 14),
    );
    expect(baseline, contains('_baseline_'));
    expect(baseline, isNot(contains('p120')));
    expect(baseline.length, lessThanOrEqualTo(63));
  });
  test('long names and maximum fields stay within the 63 ASCII character limit',
      () {
    final prefix = ExperimentRecordingNames.prefix(
      'Very long profile / with é and punctuation ' * 3,
      'silent',
      9999,
      999999,
      startedAt: DateTime(2026, 10, 13),
    );
    expect(prefix.length, lessThanOrEqualTo(63));
    expect(RegExp(r'[^\x20-\x7e]|[<>:"/\\|?*]').hasMatch(prefix), isFalse);
  });
  test(
      'take counts persist and are independent by paragraph, effort and device group',
      () async {
    expect(
      await ExperimentRecordingNames.reserve('pair', 'imu', 'vocal', 3),
      1,
    );
    expect(
      await ExperimentRecordingNames.reserve('pair', 'imu', 'vocal', 3),
      2,
    );
    expect(
      await ExperimentRecordingNames.reserve('pair', 'imu', 'silent', 3),
      1,
    );
    expect(
      await ExperimentRecordingNames.reserve('pair', 'imu', 'vocal', 4),
      1,
    );
    expect(
      await ExperimentRecordingNames.reserve('other', 'imu', 'vocal', 3),
      1,
    );
    expect(
      (await ExperimentRecordingNames.counters(
        'pair',
      ))[ExperimentRecordingNames.counterKey('imu', 'vocal', 3)],
      2,
    );
  });
}

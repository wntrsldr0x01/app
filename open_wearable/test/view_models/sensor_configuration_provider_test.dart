import 'dart:convert';
import 'package:open_wearable/models/recording_diagnostics.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

void main() {
  test('diagnostics distinguish write request, device report and confirmation',
      () async {
    final logs = <Map<String, dynamic>>[];
    RecordingDiagnostics.sink = (line) => logs.add(
          jsonDecode(line.substring('RECORDING_DIAGNOSTIC '.length))
              as Map<String, dynamic>,
        );
    addTearDown(() => RecordingDiagnostics.sink = null);
    final off = SensorConfigurationValue(key: 'off');
    final record = SensorConfigurationValue(key: 'record');
    final config =
        _FakeSensorConfiguration(name: 'Microphones', values: [off, record]);
    final manager = _FakeSensorConfigurationManager([config]);
    final provider = SensorConfigurationProvider(
      sensorConfigurationManager: manager,
      diagnosticDeviceId: 'right-id',
      diagnosticDeviceName: 'right',
    );
    manager.emit({config: off});
    await Future<void>.delayed(Duration.zero);
    final applying = provider.applyExperimentProfile({'Microphones': 'record'});
    await Future<void>.delayed(Duration.zero);
    expect(
      logs
          .where((e) => e['event'] == 'configuration_write_requested')
          .single['value'],
      'record',
    );
    expect(logs.any((e) => e['event'] == 'setting_confirmed'), isFalse);
    manager.emit({config: record});
    await applying;
    final confirmation =
        logs.singleWhere((e) => e['event'] == 'setting_confirmed');
    expect(confirmation['device_id'], 'right-id');
    expect(confirmation['value'], 'record');
    expect(confirmation['elapsed_ms'], isA<int>());
    expect(
      logs.singleWhere(
        (e) => e['event'] == 'profile_apply_confirmed',
      )['sd_write_verified'],
      false,
    );
    expect(
      logs.every(
        (e) => DateTime.tryParse(e['utc'] as String)?.isUtc ?? false,
      ),
      isTrue,
    );
    provider.dispose();
    await manager.dispose();
  });

  test(
      'a later report reverting an earlier sensor prevents profile confirmation',
      () async {
    final off = SensorConfigurationValue(key: 'off');
    final record = SensorConfigurationValue(key: 'record');
    final imu = _FakeSensorConfiguration(name: 'IMU', values: [off, record]);
    final mic =
        _FakeSensorConfiguration(name: 'Microphones', values: [off, record]);
    final manager = _FakeSensorConfigurationManager([imu, mic]);
    final provider =
        SensorConfigurationProvider(sensorConfigurationManager: manager);
    manager.emit({imu: off, mic: off});
    await Future<void>.delayed(Duration.zero);
    final applying = provider
        .applyExperimentProfile({'IMU': 'record', 'Microphones': 'record'});
    final expectation = expectLater(
        applying,
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            contains('Final profile did not confirm'),),),);
    await Future<void>.delayed(Duration.zero);
    manager.emit({imu: record, mic: off});
    await Future<void>.delayed(Duration.zero);
    manager.emit({imu: off, mic: record});
    await expectation;
    expect(
        () => provider
            .verifyReportedProfile({'IMU': 'record', 'Microphones': 'record'}),
        throwsStateError,);
    provider.dispose();
    await manager.dispose();
  });

  test('changed experiment settings wait for a fresh report', () async {
    final off = SensorConfigurationValue(key: 'off');
    final on = SensorConfigurationValue(key: 'on');
    final configuration =
        _FakeSensorConfiguration(name: 'Temperature', values: [off, on]);
    final manager = _FakeSensorConfigurationManager([configuration]);
    final provider =
        SensorConfigurationProvider(sensorConfigurationManager: manager);
    manager.emit({configuration: off});
    await Future<void>.delayed(Duration.zero);
    var completed = false;
    final applying = provider.applyExperimentProfile(
      {'Temperature': 'on'},
    ).then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(configuration.requests, [on]);
    expect(completed, isFalse);
    manager.emit({configuration: on});
    await applying;
    expect(completed, isTrue);
    provider.dispose();
    await manager.dispose();
  });

  test('experiment rejects unsupported settings before any hardware writes',
      () async {
    final off = SensorConfigurationValue(key: 'off');
    final configuration =
        _FakeSensorConfiguration(name: 'Temperature', values: [off]);
    final manager = _FakeSensorConfigurationManager([configuration]);
    final provider =
        SensorConfigurationProvider(sensorConfigurationManager: manager);
    await expectLater(
      provider.applyExperimentProfile({'Temperature': 'off', 'Unknown': 'on'}),
      throwsStateError,
    );
    expect(configuration.requests, isEmpty);
    provider.dispose();
    await manager.dispose();
  });

  test('experiment serializes writes and confirms partial reports per sensor',
      () async {
    final off = SensorConfigurationValue(key: 'off');
    final first = _FakeSensorConfiguration(name: 'IMU', values: [off]);
    final second = _FakeSensorConfiguration(name: 'Mic', values: [off]);
    final manager = _FakeSensorConfigurationManager([first, second]);
    final provider =
        SensorConfigurationProvider(sensorConfigurationManager: manager);
    final applying =
        provider.applyExperimentProfile({'IMU': 'off', 'Mic': 'off'});
    await Future<void>.delayed(Duration.zero);
    expect(first.requests, [off]);
    expect(second.requests, isEmpty);
    manager.emit({first: off});
    await Future<void>.delayed(Duration.zero);
    expect(second.requests, [off]);
    manager.emit({second: off});
    await applying;
    provider.dispose();
    await manager.dispose();
  });

  test('async SDK write failures are reported without unhandled future errors',
      () async {
    final off = SensorConfigurationValue(key: 'off');
    final config = _FakeSensorConfiguration(name: 'IMU', values: [off]);
    config.onRequest = () {
      Future<void>.error(StateError('BLE write failed'));
    };
    final manager = _FakeSensorConfigurationManager([config]);
    final provider =
        SensorConfigurationProvider(sensorConfigurationManager: manager);
    await expectLater(
      provider.applyExperimentProfile({'IMU': 'off'}),
      throwsStateError,
    );
    provider.dispose();
    await manager.dispose();
  });

  test('cancellation prevents later sensors from being enabled', () async {
    final on = SensorConfigurationValue(key: 'on');
    final first = _FakeSensorConfiguration(name: 'IMU', values: [on]);
    final second = _FakeSensorConfiguration(name: 'Mic', values: [on]);
    final manager = _FakeSensorConfigurationManager([first, second]);
    final provider =
        SensorConfigurationProvider(sensorConfigurationManager: manager);
    var cancelled = false;
    final applying = provider.applyExperimentProfile(
      {'IMU': 'on', 'Mic': 'on'},
      isCancelled: () => cancelled,
    );
    final expectation = expectLater(applying, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    cancelled = true;
    manager.emit({first: on});
    await expectation;
    expect(second.requests, isEmpty);
    provider.dispose();
    await manager.dispose();
  });

  test('shutdown attempts remaining sensors after one async write fails',
      () async {
    final off = SensorConfigurationValue(key: 'off');
    final first = _FakeSensorConfiguration(name: 'IMU', values: [off]);
    final second = _FakeSensorConfiguration(name: 'Mic', values: [off]);
    first.onRequest = () {
      Future<void>.error(StateError('BLE write failed'));
    };
    final manager = _FakeSensorConfigurationManager([first, second]);
    final provider =
        SensorConfigurationProvider(sensorConfigurationManager: manager);
    final applying = provider.applyExperimentProfile(
      {'IMU': 'off', 'Mic': 'off'},
      continueOnError: true,
    );
    final expectation = expectLater(applying, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(second.requests, [off]);
    manager.emit({second: off});
    await expectation;
    provider.dispose();
    await manager.dispose();
  });

  test(
      'already confirmed Off does not wait for a redundant firmware notification',
      () async {
    final off = SensorConfigurationValue(key: 'off');
    final config = _FakeSensorConfiguration(name: 'IMU', values: [off]);
    final manager = _FakeSensorConfigurationManager([config]);
    final provider =
        SensorConfigurationProvider(sensorConfigurationManager: manager);
    manager.emit({config: off});
    await Future<void>.delayed(Duration.zero);
    await provider
        .applyExperimentProfile({'IMU': 'off'}, continueOnError: true);
    expect(config.requests, isEmpty);
    provider.dispose();
    await manager.dispose();
  });

  test('accepts unchanged device state after a submitted request is rejected',
      () {
    final off = SensorConfigurationValue(key: 'off');
    final record = SensorConfigurationValue(key: '8 Hz record');
    final configuration = _FakeSensorConfiguration(
      name: 'Temperature',
      values: [off, record],
    );
    final manager = _FakeSensorConfigurationManager([configuration]);
    final provider = SensorConfigurationProvider(
      sensorConfigurationManager: manager,
    );
    addTearDown(() async {
      provider.dispose();
      await manager.dispose();
    });

    manager.emit({configuration: off});
    provider.addSensorConfiguration(configuration, record);
    provider.applyConfiguration(configuration, record);
    expect(configuration.requests, [record]);

    manager.emit({configuration: off});
    expect(provider.getSelectedConfigurationValue(configuration), off);
    expect(provider.isConfigurationPending(configuration), isFalse);
    expect(provider.isConfigurationApplied(configuration), isTrue);
  });

  test('reports for submitted settings preserve newer and unsubmitted edits',
      () {
    final off = SensorConfigurationValue(key: 'off');
    final stream = SensorConfigurationValue(key: '8 Hz stream');
    final record = SensorConfigurationValue(key: '8 Hz record');
    final first = _FakeSensorConfiguration(
      name: 'Temperature',
      values: [off, stream, record],
    );
    final second = _FakeSensorConfiguration(
      name: 'Pressure',
      values: [off, stream, record],
    );
    final manager = _FakeSensorConfigurationManager([first, second]);
    final provider = SensorConfigurationProvider(
      sensorConfigurationManager: manager,
    );
    addTearDown(() async {
      provider.dispose();
      await manager.dispose();
    });

    manager.emit({first: stream, second: off});
    provider.addSensorConfiguration(first, record);
    provider.addSensorConfiguration(second, stream);
    manager.emit({first: stream, second: off});
    expect(provider.getSelectedConfigurationValue(first), record);

    provider.applyConfiguration(first, record);
    manager.emit({first: stream, second: off});
    expect(provider.getSelectedConfigurationValue(first), stream);
    expect(provider.getSelectedConfigurationValue(second), stream);
    expect(provider.isConfigurationPending(second), isTrue);

    provider.applyConfiguration(first, record);
    provider.addSensorConfiguration(first, off);
    manager.emit({first: record, second: off});
    expect(provider.getSelectedConfigurationValue(first), off);
    expect(provider.isConfigurationPending(first), isTrue);
  });

  test('notifies when the first hardware report matches selected values', () {
    final value = SensorConfigurationValue(key: 'off');
    final configuration = _FakeSensorConfiguration(
      name: 'Example sensor',
      values: [value],
    );
    final manager = _FakeSensorConfigurationManager([configuration]);
    final provider = SensorConfigurationProvider(
      sensorConfigurationManager: manager,
    );
    addTearDown(() async {
      provider.dispose();
      await manager.dispose();
    });

    provider.addSensorConfiguration(
      configuration,
      value,
      markPending: false,
    );
    var notificationCount = 0;
    provider.addListener(() => notificationCount += 1);

    manager.emit({configuration: value});

    expect(provider.hasReceivedConfigurationReport, isTrue);
    expect(provider.isConfigurationApplied(configuration), isTrue);
    expect(notificationCount, 1);
  });
}

class _FakeSensorConfiguration extends SensorConfiguration {
  _FakeSensorConfiguration({
    required super.name,
    required super.values,
  });

  final List<SensorConfigurationValue> requests = [];
  void Function()? onRequest;

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    requests.add(configuration);
    onRequest?.call();
  }
}

class _FakeSensorConfigurationManager implements SensorConfigurationManager {
  _FakeSensorConfigurationManager(this.sensorConfigurations);

  final StreamController<Map<SensorConfiguration, SensorConfigurationValue>>
      _controller =
      StreamController<Map<SensorConfiguration, SensorConfigurationValue>>(
    sync: true,
  );

  @override
  final List<SensorConfiguration> sensorConfigurations;

  @override
  Stream<Map<SensorConfiguration, SensorConfigurationValue>>
      get sensorConfigurationStream => _controller.stream;

  void emit(Map<SensorConfiguration, SensorConfigurationValue> report) {
    _controller.add(report);
  }

  Future<void> dispose() => _controller.close();
}

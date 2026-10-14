import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration_specializations/sensor_configuration_open_earable_v2.dart'
    show SensorConfigurationOpenEarableV2Value;
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:open_wearable/view_models/sensor_profile_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'package:open_wearable/view_models/sensor_configuration_storage.dart';
import 'package:open_wearable/widgets/sensors/configuration/sensor_configuration_device_row.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Configuration extends SensorConfiguration {
  _Configuration()
      : super(
          name: 'Microphones',
          values: [
            SensorConfigurationValue(key: 'off'),
            SensorConfigurationValue(key: 'record'),
          ],
          offValue: SensorConfigurationValue(key: 'off'),
        );
  @override
  void setConfiguration(SensorConfigurationValue value) {}
}

class _RateConfiguration extends SensorConfiguration {
  _RateConfiguration(List<SensorConfigurationValue> values)
      : super(name: 'IMU', values: values);
  @override
  void setConfiguration(SensorConfigurationValue value) {}
}

class _Ear extends Wearable implements SensorConfigurationManager {
  _Ear(this.deviceId, {SensorConfiguration? configuration})
      : config = configuration ?? _Configuration(),
        super(
          name: 'Test ear',
          disconnectNotifier: WearableDisconnectNotifier(),
        );
  @override
  final String deviceId;
  final SensorConfiguration config;
  final reports = StreamController<
      Map<SensorConfiguration, SensorConfigurationValue>>.broadcast(sync: true);
  @override
  List<SensorConfiguration> get sensorConfigurations => [config];
  @override
  Stream<Map<SensorConfiguration, SensorConfigurationValue>>
      get sensorConfigurationStream => reports.stream;
  void emit(String key) => reports
      .add({config: config.values.firstWhere((value) => value.key == key)});
  @override
  Future<void> disconnect() async {}
}

Finder recordingText(String text) => find.descendant(
      of: find.ancestor(
        of: find.text('recording'),
        matching: find.byType(PlatformListTile),
      ),
      matching: find.text(text),
    );

void main() {
  test('experiments require the same rate and recording targets on the partner',
      () async {
    final requested = SensorConfigurationOpenEarableV2Value(
      frequencyHz: 200,
      frequencyIndex: 3,
      options: {const RecordSensorConfigOption()},
    );
    final lowerRate = SensorConfigurationOpenEarableV2Value(
      frequencyHz: 100,
      frequencyIndex: 2,
      options: {const RecordSensorConfigOption()},
    );
    final streamOnly = SensorConfigurationOpenEarableV2Value(
      frequencyHz: 200,
      frequencyIndex: 3,
      options: {const StreamSensorConfigOption()},
    );
    final source =
        _Ear('source', configuration: _RateConfiguration([requested]));
    final target = _Ear(
      'target',
      configuration: _RateConfiguration([lowerRate, streamOnly]),
    );
    expect(
      SensorProfileService.buildMirroredProfileConfig(
        sourceDevice: source,
        targetDevice: target,
        sourceProfileConfig: {'IMU': requested.key},
        requireExactValues: true,
      ),
      isNull,
    );
    final exact = _Ear('exact', configuration: _RateConfiguration([requested]));
    expect(
      SensorProfileService.buildMirroredProfileConfig(
        sourceDevice: source,
        targetDevice: exact,
        sourceProfileConfig: {'IMU': requested.key},
        requireExactValues: true,
      ),
      {'IMU': requested.key},
    );
    await source.reports.close();
    await target.reports.close();
    await exact.reports.close();
  });

  testWidgets(
      'profile badge updates when either ear confirms last and when either ear reverts',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final directory =
        Directory.systemTemp.createTempSync('paired_profile_status');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    final left = _Ear('left');
    final right = _Ear('right');
    final primary =
        SensorConfigurationProvider(sensorConfigurationManager: left);
    final secondary =
        SensorConfigurationProvider(sensorConfigurationManager: right);
    await tester.runAsync(
      () => SensorConfigurationStorage.saveConfiguration(
        'test__recording',
        {'Microphones': 'record'},
      ),
    );
    left.emit('record');
    right.emit('off');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: primary,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SensorConfigurationDeviceRow(
                device: left,
                pairedDevice: right,
                pairedProvider: secondary,
                storageScope: 'test',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index = 1;
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(recordingText('Mixed state across paired devices'), findsOneWidget);
    late Future<void> applying;
    await tester.runAsync(() async {
      applying = Future.wait([
        primary.applyExperimentProfile({'Microphones': 'record'}),
        secondary.applyExperimentProfile({'Microphones': 'record'}),
      ]);
      await Future<void>.delayed(Duration.zero);
    });
    right.emit('record'); // No primary event or manual selection follows.
    await tester.runAsync(() => applying);
    await tester.pumpAndSettle();
    expect(recordingText('Applied on both devices'), findsOneWidget);
    right.emit('off');
    await tester.pumpAndSettle();
    expect(recordingText('Mixed state across paired devices'), findsOneWidget);
    left.emit('off');
    right.emit('record');
    await tester.pumpAndSettle();
    expect(recordingText('Mixed state across paired devices'), findsOneWidget);
    left.emit('record');
    await tester.pumpAndSettle();
    expect(recordingText('Applied on both devices'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    primary.dispose();
    secondary.dispose();
    await left.reports.close();
    await right.reports.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });
}

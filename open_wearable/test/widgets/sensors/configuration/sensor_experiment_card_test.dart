import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_wearable/view_models/sensor_experiment_controller.dart';
import 'package:open_wearable/widgets/sensors/configuration/sensor_experiment_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'collection setup fits iPhone and retains environment and posture',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SensorExperimentController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorExperimentCard(
            controller: controller,
            storageKey: 'phone',
            supportsNaming: true,
            profiles: () async => [ExperimentProfile('audio', 'Audio')],
            start: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set up experiment'));
    await tester.pumpAndSettle();
    final fields = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(fields.at(0));
    await tester.tap(fields.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('noisy').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(fields.at(1));
    await tester.tap(fields.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('walking').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview passage'));
    await tester.pumpAndSettle();
    expect(find.text('Env: noisy'), findsOneWidget);
    expect(find.text('walking'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('experiment-environment:phone'), 'noisy');
    expect(prefs.getString('experiment-posture:phone'), 'walking');
    expect(tester.takeException(), isNull);
  });
  testWidgets('experiment dialog validates duration and builds ordered stages',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SensorExperimentController();
    addTearDown(controller.dispose);
    List<ExperimentStageSelection>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorExperimentCard(
            controller: controller,
            storageKey: 'test-device',
            profiles: () async => [
              ExperimentProfile('imu', 'IMU'),
              ExperimentProfile('audio', 'Audio'),
            ],
            start: (stages) async {
              selected = stages;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set up experiment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('Start experiment'));
    await tester.pump();
    expect(find.textContaining('Enter whole seconds'), findsOneWidget);
    expect(selected, isNull);
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('Add stage'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '3');
    await tester.tap(find.text('Start experiment'));
    await tester.pumpAndSettle();
    expect(selected!.map((s) => s.duration.inSeconds), [2, 3]);
    expect(selected!.map((s) => s.key), ['audio', 'audio']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorExperimentCard(
            controller: controller,
            storageKey: 'test-device',
            profiles: () async => [
              ExperimentProfile('imu', 'IMU'),
              ExperimentProfile('audio', 'Audio'),
            ],
            start: (stages) async {
              selected = stages;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set up experiment'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .map((f) => f.initialValue),
      ['audio', 'audio'],
    );
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller!.text),
      ['2', '3'],
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'missing remembered profile requires a choice instead of defaulting',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'sensor-experiment-v1:missing-device':
          '[{"key":"deleted-profile","seconds":"30"}]',
    });
    final controller = SensorExperimentController();
    addTearDown(controller.dispose);
    var started = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorExperimentCard(
            controller: controller,
            storageKey: 'missing-device',
            profiles: () async => [ExperimentProfile('default', 'Default')],
            start: (_) async {
              started = true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set up experiment'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      isNull,
    );
    await tester.tap(find.text('Start experiment'));
    await tester.pump();
    expect(started, isFalse);
    expect(find.text('Choose a profile for every stage.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  testWidgets('removing a middle stage preserves later profiles and durations',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SensorExperimentController();
    addTearDown(controller.dispose);
    List<ExperimentStageSelection>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorExperimentCard(
            controller: controller,
            storageKey: 'remove-test',
            profiles: () async => [
              ExperimentProfile('imu', 'IMU'),
              ExperimentProfile('audio', 'Audio'),
            ],
            start: (stages) async {
              selected = stages;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set up experiment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.tap(find.text('Add stage'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add stage'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '3');
    await tester.tap(find.byTooltip('Remove stage 2'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller!.text),
      ['1', '3'],
    );
    await tester.tap(find.text('Start experiment'));
    await tester.pumpAndSettle();
    expect(selected!.map((s) => s.key), ['imu', 'audio']);
    expect(selected!.map((s) => s.duration.inSeconds), [1, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'automatic names use chosen effort and paragraph without manual filename input',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SensorExperimentController();
    addTearDown(controller.dispose);
    List<ExperimentStageSelection>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorExperimentCard(
            controller: controller,
            storageKey: 'naming-test',
            supportsNaming: true,
            profiles: () async => [ExperimentProfile('imu', 'IMU')],
            start: (stages) async {
              selected = stages;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set up experiment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next paragraph'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('vocal').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('IMU_vocal_p002_t001_'), findsOneWidget);
    await tester.tap(find.text('Preview passage'));
    await tester.pumpAndSettle();
    expect(selected, isNull); // Preview must not start a recording.
    await tester.tap(find.text('Begin recording'));
    await tester.pumpAndSettle();
    expect(selected!.single.automaticName, isTrue);
    expect(selected!.single.effort, 'vocal');
    expect(selected!.single.paragraph, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('experiment-paragraph:naming-test'), 2);
    expect(
      prefs.getString('sensor-experiment-v1:naming-test'),
      contains('vocal'),
    );
    expect(tester.takeException(), isNull);
  });
}

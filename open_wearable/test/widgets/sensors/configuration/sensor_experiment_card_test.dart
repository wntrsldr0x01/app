import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/view_models/sensor_experiment_controller.dart';
import 'package:open_wearable/widgets/sensors/configuration/sensor_experiment_card.dart';

void main() {
  testWidgets('experiment dialog validates duration and builds ordered stages',
      (tester) async {
    final controller = SensorExperimentController();
    addTearDown(controller.dispose);
    List<ExperimentStageSelection>? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SensorExperimentCard(
        controller: controller,
        profiles: () async => [ExperimentProfile('imu', 'IMU')],
        start: (stages) async { selected = stages; },
      ),),
    ),);
    await tester.tap(find.text('Set up experiment'));
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
    expect(selected!.map((s) => s.key), ['imu', 'imu']);
    expect(tester.takeException(), isNull);
  });
}

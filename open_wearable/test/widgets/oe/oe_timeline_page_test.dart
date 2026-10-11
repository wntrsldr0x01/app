import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_timeline_page.dart';
import '../../models/oe/oe_timeline_fixture.dart';

void main() {
  testWidgets(
      'comparison exposes multiple axes, time extent and selection controls',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: OeTimelinePage(
            recording: OeRecording.parse(timelineFixture()),
            name: 'synthetic.oe',),),);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),);
    await tester.pump();
    expect(find.textContaining('0.004000 s timestamp extent'), findsOneWidget);
    expect(find.text('IMU · ACCELEROMETER'), findsOneWidget);
    expect(find.text('Bone · ACCELEROMETER'), findsOneWidget);
    expect(find.text('X'), findsNWidgets(2));
    await tester.tap(find.text('Sensors & axes · 6 selected'));
    await tester.pumpAndSettle();
    expect(find.text('Separate axes'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Apply exact window'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

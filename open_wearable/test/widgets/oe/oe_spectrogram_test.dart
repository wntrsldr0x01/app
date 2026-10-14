import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_spectrum_page.dart';
import '../../models/oe/oe_fixture.dart';

void main() {
  testWidgets('spectrogram computes and renders selected audio range',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: OeSpectrumPage(
          recording: OeRecording.parse(
            oeFixture(audio: List.generate(96, (i) => [i * 100, 0])),
          ),
          name: 'audio.oe',
          sensorId: 2,
          channel: 0,
          initialSpectrogram: true,
          initialRate: 24000,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spectrogram (linear Hz)'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await Scrollable.ensureVisible(
      tester.element(find.text('Compute spectrogram')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Compute spectrogram'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Frames 0–95'), findsOneWidget);
    expect(find.textContaining('Horizontal: time'), findsOneWidget);
    expect(find.text('Play analyzed range'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Play analyzed range'),)
            .onPressed,
        isNotNull,);
    expect(find.textContaining('Playback: stopped'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

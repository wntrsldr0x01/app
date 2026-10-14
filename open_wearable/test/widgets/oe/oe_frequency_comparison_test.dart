import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_spectrum_page.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_log_comparison_page.dart';
import '../../models/oe/oe_fixture.dart';

void main() {
  testWidgets(
      'frequency analysis requires explicit rate and uniform sampling consent',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final r = OeRecording.parse(
        oeFixture(audio: List.generate(2048, (i) => [i % 100, -i % 100])),);
    await tester.pumpWidget(MaterialApp(
        home: OeSpectrumPage(
            recording: r, name: 'test.oe', sensorId: 2, channel: 0,),),);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Compute FFT power spectrum'),)
            .onPressed,
        isNull,);
    await tester.enterText(
        find.widgetWithText(TextField, 'Assumed sample rate (Hz)'), '24000',);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('Compute FFT power spectrum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compute FFT power spectrum'));
    await tester.pump();
    for (var i = 0;
        i < 30 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('1024 samples'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
        find.widgetWithText(TextField, 'Assumed sample rate (Hz)'),);
    await tester.enterText(
        find.widgetWithText(TextField, 'Assumed sample rate (Hz)'), '25000',);
    await tester.pump();
    expect(find.textContaining('1024 samples'), findsNothing);
  });
  testWidgets(
      'multiple logs show matching channels with shared duration and alignment controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final a = OeRecording.parse(oeFixture());
    final b = OeRecording.parse(oeFixture(
        timestamps: [1791720544676608 + 2000000, 1791720544676608 + 2001000],),);
    await tester.pumpWidget(MaterialApp(
        home: OeLogComparisonPage(
            logs: [OeComparisonLog('a.oe', a), OeComparisonLog('b.oe', b)],),),);
    await tester.pump();
    for (var i = 0;
        i < 30 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Compare 2 logs'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Play visible microphone').first, 300,
        scrollable: find.byType(Scrollable).first,);
    expect(
        tester
            .widget<FilledButton>(find
                .widgetWithText(FilledButton, 'Play visible microphone')
                .first,)
            .onPressed,
        isNull,);
    await tester.tap(find.byKey(const ValueKey('comparison-rate-0:2:0-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24000 Hz').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find
                .widgetWithText(FilledButton, 'Play visible microphone')
                .first,)
            .onPressed,
        isNotNull,);
    await tester.scrollUntilVisible(
        find.text('Align recorded device clocks'), -300,
        scrollable: find.byType(Scrollable).first,);

    expect(find.textContaining('duration 0.001000 s'), findsOneWidget);
    await tester.tap(find.text('Align recorded device clocks'));
    await tester.pump();
    for (var i = 0;
        i < 30 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('duration 2.001000 s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/widgets/sensors/oe/oe_viewer_page.dart';
import '../../models/oe/oe_fixture.dart';

void main() {
  testWidgets('viewer labels original data and does not assume a playback rate',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OeViewerPage(
          name: 'synthetic.oe',
          recording: OeRecording.parse(oeFixture()),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.text('Original copy · SHA-256 checked'), findsOneWidget);
    expect(
      find.textContaining('NOT a recorded active-rate setting'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Play selected channel'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Play selected channel'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('unverified assumption'), findsOneWidget);
    await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('rate-2'))),
        alignment: 0.5,);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rate-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24000 Hz').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Play selected channel'),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('Playback: stopped'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Inspect 300 samples'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(
      find.text('Recorded waveform · assumed playback time'),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/models/speech_corpus.dart';
import 'package:open_wearable/view_models/sensor_experiment_controller.dart';
import 'package:open_wearable/widgets/sensors/configuration/corpus_reading_page.dart';
import 'package:open_wearable/widgets/sensors/configuration/sensor_experiment_card.dart';

void main() {
  test('frozen corpus has 120 IDs, exact word total and allocation', () {
    expect(speechCorpus.map((p) => p.number), List.generate(120, (i) => i + 1));
    expect(
      speechCorpus.fold<int>(
        0,
        (n, p) => n + p.text.split(RegExp(r'\s+')).length,
      ),
      12965,
    );
    expect(speechCorpus.where((p) => p.split == 'training').length, 84);
    expect(speechCorpus.where((p) => p.split == 'development').length, 18);
    expect(speechCorpus.where((p) => p.split == 'test').length, 18);
  });
  testWidgets('iPhone reader keeps complete prompt and waits for manual finish',
      (tester) async {
    final loader = FontLoader('ReaderTest')
      ..addFont(rootBundle.load('lib/assets/fonts/RobotoMono.ttf'));
    await loader.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SensorExperimentController();
    addTearDown(controller.dispose);
    var offCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'ReaderTest'),
        home: CorpusReadingPage(
          controller: controller,
          selections: [
            ExperimentStageSelection(
              'audio',
              const Duration(seconds: 60),
              effort: 'silent',
              automaticName: true,
              finishManually: true,
            ),
          ],
          onStart: () => controller.start([
            SensorExperimentStage(
              'Audio',
              const Duration(seconds: 60),
              () async {},
              finishManually: true,
            ),
          ], () async {
            offCalls++;
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/corpus_reader_iphone.png'),
    );
    expect(find.text(speechCorpus.first.text), findsOneWidget);
    await tester.tap(find.text('Begin recording'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 65));
    expect(controller.readyToRead, isTrue);
    expect(controller.running, isTrue);
    expect(offCalls, 0);
    expect(find.text(speechCorpus.first.text), findsOneWidget);
    await tester.tap(find.text('Finish paragraph'));
    await tester.pump();
    expect(offCalls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(offCalls, 1);
    expect(controller.running, isFalse);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/view_models/sensor_experiment_controller.dart';

void main() {
  test('times confirmed profiles, shifts profiles, then turns Off', () {
    fakeAsync((time) {
      final controller = SensorExperimentController();
      final confirmation = Completer<void>();
      final actions = <String>[];
      unawaited(
        controller.start(
          [
            SensorExperimentStage('first', const Duration(seconds: 2), () {
              actions.add('first');
              return confirmation.future;
            }),
            SensorExperimentStage('second', const Duration(seconds: 1),
                () async {
              actions.add('second');
            }),
          ],
          () async {
            actions.add('Off');
          },
        ),
      );
      time.elapse(const Duration(seconds: 5));
      expect(actions, ['first']);
      confirmation.complete();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 2));
      expect(actions, ['first', 'second']);
      time.elapse(const Duration(seconds: 1));
      expect(actions, ['first', 'second', 'Off']);
      expect(controller.running, isFalse);
      controller.dispose();
    });
  });
  test('stop during apply cannot restart a cancelled timer', () {
    fakeAsync((time) {
      final controller = SensorExperimentController();
      final confirmation = Completer<void>();
      var offCalls = 0;
      unawaited(
        controller.start(
          [
            SensorExperimentStage(
                'first', const Duration(seconds: 1), () => confirmation.future,),
          ],
          () async {
            offCalls++;
          },
        ),
      );
      unawaited(controller.stop());
      time.flushMicrotasks();
      confirmation.complete();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 5));
      expect(offCalls, 1);
      expect(controller.running, isFalse);
      controller.dispose();
    });
  });
  test('failed profiles attempt Off and report failure', () {
    fakeAsync((time) {
      final controller = SensorExperimentController();
      var offCalls = 0;
      unawaited(
        controller.start(
          [
            SensorExperimentStage('bad', const Duration(seconds: 1), () async {
              throw StateError('No hardware acknowledgement');
            }),
          ],
          () async {
            offCalls++;
          },
        ),
      );
      time.flushMicrotasks();
      expect(offCalls, 1);
      expect(controller.running, isFalse);
      expect(controller.events.join(), contains('No hardware acknowledgement'));
      controller.dispose();
    });
  });
}

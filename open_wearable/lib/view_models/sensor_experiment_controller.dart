import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

class SensorExperimentStage {
  final String name;
  final Duration duration;
  final Future<void> Function() apply;
  SensorExperimentStage(this.name, this.duration, this.apply);
}

/// App-side scheduling. Stage durations exclude configuration acknowledgement.
class SensorExperimentController extends ChangeNotifier {
  Timer? _timer;
  final Stopwatch _clock = clock.stopwatch();
  int _generation = 0;
  bool _disposed = false;
  bool running = false;
  bool _stopping = false;
  String status = 'Ready';
  Duration remaining = Duration.zero;
  final List<String> events = [];
  Future<void> Function()? _off;

  void _event(String message) {
    status = message;
    events.add('${DateTime.now().toUtc().toIso8601String()} · $message');
    if (!_disposed) notifyListeners();
  }

  Future<void> start(
    List<SensorExperimentStage> stages,
    Future<void> Function() off,
  ) async {
    if (running) throw StateError('An experiment is already running.');
    if (stages.isEmpty || stages.any((s) => s.duration <= Duration.zero)) {
      throw ArgumentError('Every stage needs a positive duration.');
    }
    final generation = ++_generation;
    _off = off;
    running = true;
    events.clear();
    await _stage(stages, 0, generation);
  }

  Future<void> _stage(
    List<SensorExperimentStage> stages,
    int index,
    int generation,
  ) async {
    try {
      if (index == stages.length) {
        await stop();
        return;
      }
      final stage = stages[index];
      remaining = Duration.zero;
      _event('Applying ${stage.name}');
      await stage.apply();
      if (_disposed || generation != _generation) return;
      remaining = stage.duration;
      _clock
        ..reset()
        ..start();
      _event('Running ${stage.name}');
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_disposed || generation != _generation) return;
        remaining = stage.duration - _clock.elapsed;
        if (remaining <= Duration.zero) {
          _timer?.cancel();
          _clock.stop();
          remaining = Duration.zero;
          _event('Timer ended: ${stage.name}');
          unawaited(_stage(stages, index + 1, generation));
        } else {
          notifyListeners();
        }
      });
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _event('Experiment failed: $error');
      await stop(failed: true);
    }
  }

  Future<void> stop({bool failed = false}) async {
    if (!running || _stopping) return;
    _stopping = true;
    ++_generation;
    _timer?.cancel();
    _clock.stop();
    remaining = Duration.zero;
    _event('Applying Off');
    try {
      await _off?.call();
      _event(
        failed ? 'Experiment failed; Off confirmed' : 'Finished; Off confirmed',
      );
    } catch (error) {
      _event('Off could not be confirmed: $error');
    } finally {
      running = false;
      _stopping = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _clock.stop();
    // The owning device is disconnecting; still attempt shutdown on its partner.
    if (running) {
      unawaited(_off?.call().catchError((Object _) {}) ?? Future<void>.value());
    }
    super.dispose();
  }
}

import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import '../models/recording_diagnostics.dart';

class SensorExperimentStage {
  final String name;
  final Duration duration;
  final Future<void> Function() apply;
  final bool finishManually;
  SensorExperimentStage(
    this.name,
    this.duration,
    this.apply, {
    this.finishManually = false,
  });
}

/// App-side scheduling. Stage durations exclude configuration acknowledgement.
class SensorExperimentController extends ChangeNotifier {
  Timer? _timer;
  final Stopwatch _clock = clock.stopwatch();
  int _generation = 0;
  String? _runId;
  bool _disposed = false;
  bool running = false;
  bool _stopping = false;
  List<SensorExperimentStage> _stages = [];
  int stageIndex = 0;
  bool readyToRead = false;
  Duration get elapsed => _clock.elapsed;
  String? recordingPrefix;
  int? take;
  int get runGeneration => _generation;
  void recordDetail(String detail) {
    RecordingDiagnostics.record(
      'experiment_detail',
      {'run_id': _runId, 'detail': detail},
    );
    events.add('${DateTime.now().toUtc().toIso8601String()} · $detail');
    if (!_disposed) notifyListeners();
  }

  String status = 'Ready';
  Duration remaining = Duration.zero;
  final List<String> events = [];
  Future<void> Function()? _off;

  void _event(String message) {
    RecordingDiagnostics.record(
      'experiment_state',
      {'run_id': _runId, 'state': message},
    );
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
    _runId = '${DateTime.now().microsecondsSinceEpoch}';
    RecordingDiagnostics.record('experiment_begin', {
      'run_id': _runId,
      'stages': [
        for (final stage in stages)
          {'profile': stage.name, 'duration_ms': stage.duration.inMilliseconds},
      ],
    });
    final generation = ++_generation;
    _stages = stages;
    recordingPrefix = null;
    take = null;
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
      stageIndex = index;
      readyToRead = false;
      remaining = Duration.zero;
      _event('Applying ${stage.name}');
      await stage.apply();
      if (_disposed || generation != _generation) return;
      remaining = stage.duration;
      _clock
        ..reset()
        ..start();
      _event('Running ${stage.name}');
      readyToRead = true;
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_disposed || generation != _generation) return;
        remaining = stage.duration - _clock.elapsed;
        if (remaining <= Duration.zero && !stage.finishManually) {
          _timer?.cancel();
          _clock.stop();
          remaining = Duration.zero;
          RecordingDiagnostics.record('stage_timer_ended', {
            'run_id': _runId,
            'profile': stage.name,
            'elapsed_ms': _clock.elapsedMilliseconds,
          });
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

  Future<void> finishParagraph() async {
    if (!running || !readyToRead || _stopping) return;
    readyToRead = false;
    _timer?.cancel();
    _clock.stop();
    RecordingDiagnostics.record('paragraph_finished', {
      'run_id': _runId,
      'stage_index': stageIndex,
      'elapsed_ms': _clock.elapsedMilliseconds,
      'prefix': recordingPrefix,
    });
    // Preserve a short tail after the final articulation and finish-button tap.
    // A concurrent explicit stop or disconnect cancels this continuation.
    final generation = _generation;
    _event('Finishing paragraph · keep still');
    await Future<void>.delayed(const Duration(seconds: 1));
    if (_disposed || !running || generation != _generation) return;
    await _stage(_stages, stageIndex + 1, _generation);
  }

  Future<void> stop({bool failed = false}) async {
    if (!running || _stopping) return;
    _stopping = true;
    readyToRead = false;
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
    RecordingDiagnostics.record(
      'experiment_owner_disposed',
      {'run_id': _runId, 'running': running},
    );
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _clock.stop();
    // The owning device is disconnecting; still attempt shutdown on its partner.
    // A pending stop already owns shutdown on both ears. Starting it again
    // here would overlap writes with the microphone stop still in flight.
    if (running && !_stopping) {
      unawaited(_off?.call().catchError((Object _) {}) ?? Future<void>.value());
    }
    super.dispose();
  }
}

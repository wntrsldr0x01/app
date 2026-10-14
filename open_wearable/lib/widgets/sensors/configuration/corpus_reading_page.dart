import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:open_wearable/models/speech_corpus.dart';
import 'package:open_wearable/view_models/sensor_experiment_controller.dart';
import 'sensor_experiment_card.dart';

/// The prompt remains mounted through hardware setup, recording and shutdown.
/// No automatic scrolling, sentence paging, audible cues or text replacement.
class CorpusReadingPage extends StatefulWidget {
  final SensorExperimentController controller;
  final List<ExperimentStageSelection> selections;
  final Future<void> Function() onStart;
  const CorpusReadingPage({
    super.key,
    required this.controller,
    required this.selections,
    required this.onStart,
  });
  @override
  State<CorpusReadingPage> createState() => _CorpusReadingPageState();
}

class _CorpusReadingPageState extends State<CorpusReadingPage> {
  final _scroll = ScrollController();
  bool _begun = false, _starting = false;
  bool? _previousWakelock;
  double _fontSize = 24;
  String? _error;
  static const _ink = Color(0xff183b38);
  static const _paper = Color(0xfff7f6f0);

  @override
  void initState() {
    super.initState();
    unawaited(_keepAwake());
  }

  Future<void> _keepAwake() async {
    try {
      final previous = await WakelockPlus.enabled;
      if (!mounted) return;
      _previousWakelock = previous;
      await WakelockPlus.enable();
      if (!mounted && !previous) await WakelockPlus.disable();
    } catch (_) {/* Unsupported on some test and web runtimes. */}
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_previousWakelock == false) unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() {
      _starting = true;
      _begun = true;
      _error = null;
    });
    try {
      await widget.onStart();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this take early?'),
        content: const Text(
          'The original recording is kept. Wait for Off confirmation before turning off either ear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep reading'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End take'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.stop(failed: true);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final selection = widget.selections[
              controller.stageIndex.clamp(0, widget.selections.length - 1)];
          final passage = speechCorpus[selection.paragraph - 1];
          final baseline = selection.effort == 'empty';
          final running = controller.running;
          final reading = running && controller.readyToRead;
          final busy = _starting || running;
          final finished = _begun && !busy;
          final elapsed = controller.elapsed;
          final time =
              '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
          final status = _error != null
              ? 'Setup failed'
              : !_begun
                  ? 'Preview · read at your own pace'
                  : reading
                      ? 'Recording · $time'
                      : busy
                          ? 'Please wait · ${controller.status}'
                          : controller.status;
          return PopScope(
            canPop: !busy,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && running) unawaited(_stop());
            },
            child: Scaffold(
              backgroundColor: _paper,
              appBar: AppBar(
                backgroundColor: _paper,
                foregroundColor: _ink,
                automaticallyImplyLeading: !busy,
                title: Text(
                  baseline ? 'Resting baseline' : '${passage.id} / P120',
                ),
                actions: [
                  IconButton(
                    tooltip: 'Smaller text',
                    onPressed: _fontSize <= 18
                        ? null
                        : () => setState(() => _fontSize -= 2),
                    icon: const Icon(Icons.text_decrease),
                  ),
                  IconButton(
                    tooltip: 'Larger text',
                    onPressed: _fontSize >= 36
                        ? null
                        : () => setState(() => _fontSize += 2),
                    icon: const Icon(Icons.text_increase),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      color: reading ? _ink : const Color(0xffe6ebe4),
                      child: Center(
                        child: Text(
                          status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: reading ? Colors.white : _ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scroll,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      for (final label in [
                                        'Mode: ${selection.effort}',
                                        'Env: ${selection.environment}',
                                        selection.posture,
                                        if (!baseline) passage.split,
                                        if (controller.take != null && _begun)
                                          'Take ${controller.take!.toString().padLeft(3, '0')}',
                                      ])
                                        Chip(
                                          label: Text(
                                            label,
                                            style: const TextStyle(color: _ink),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: Colors.white,
                                          side: BorderSide.none,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    baseline
                                        ? 'A moment of rest'
                                        : passage.title,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      height: 1.2,
                                      color: _ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    baseline
                                        ? 'No passage label is assigned to this baseline.'
                                        : 'Read only the text below. Natural sentence pauses are welcome.',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.5,
                                      color: Color(0xff61736e),
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  Text(
                                    baseline
                                        ? 'Stay relaxed and do not articulate any passage. Keep the selected posture and environment.'
                                        : passage.text,
                                    key: const ValueKey(
                                      'corpus-passage-body',
                                    ),
                                    style: TextStyle(
                                      fontSize: _fontSize,
                                      height: 1.65,
                                      letterSpacing: 0.15,
                                      color: _ink,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  const Text(
                                    'END OF PASSAGE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 2,
                                      color: Color(0xff61736e),
                                    ),
                                  ),
                                  if (finished) ...[
                                    const SizedBox(height: 24),
                                    Text(
                                      _error ??
                                          (controller.status ==
                                                  'Finished; Off confirmed'
                                              ? 'Device configuration shutdown confirmed. SD file integrity still needs verification.'
                                              : 'This take needs review. Off was not confirmed successfully on every device.'),
                                      style: TextStyle(
                                        color: controller.status ==
                                                'Finished; Off confirmed'
                                            ? _ink
                                            : Colors.deepOrange.shade800,
                                        height: 1.5,
                                      ),
                                    ),
                                    if (controller.recordingPrefix != null)
                                      SelectableText(
                                        controller.recordingPrefix!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      decoration: const BoxDecoration(
                        color: _paper,
                        border: Border(
                          top: BorderSide(color: Color(0xffdce2d9)),
                        ),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                reading
                                    ? (selection.finishManually
                                        ? 'No time limit. Finish after your last word, then stay still while saving.'
                                        : 'Timed recording · ${controller.remaining.inSeconds.clamp(0, 86400)} seconds left')
                                    : !_begun
                                        ? 'Preview first. Begin when comfortable; read when the bar says Recording.'
                                        : busy
                                            ? 'Keep both ears connected. Do not power off while saving.'
                                            : 'Keep originals, including interrupted takes.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _ink,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        16,
                                      ),
                                    ),
                                  ),
                                  onPressed: !busy
                                      ? _begin
                                      : reading && selection.finishManually
                                          ? controller.finishParagraph
                                          : null,
                                  icon: Icon(
                                    !busy
                                        ? Icons.fiber_manual_record
                                        : reading
                                            ? Icons.check_rounded
                                            : Icons.hourglass_top,
                                  ),
                                  label: Text(
                                    !busy
                                        ? finished
                                            ? 'Record another take'
                                            : 'Begin recording'
                                        : reading
                                            ? 'Finish paragraph'
                                            : 'Preparing / saving…',
                                  ),
                                ),
                              ),
                              if (running)
                                TextButton(
                                  onPressed: _stop,
                                  child: const Text('End take early'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

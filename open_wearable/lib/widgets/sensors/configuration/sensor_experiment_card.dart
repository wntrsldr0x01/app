import 'dart:convert';
import 'package:open_wearable/models/speech_corpus.dart';
import 'corpus_reading_page.dart';
import 'package:open_wearable/models/experiment_recording_name.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_wearable/view_models/sensor_experiment_controller.dart';

class ExperimentProfile {
  final String key, name;
  ExperimentProfile(this.key, this.name);
}

class ExperimentStageSelection {
  final String key;
  final Duration duration;
  final String effort;
  final int paragraph;
  final bool automaticName;
  final String environment, posture;
  final bool finishManually;
  ExperimentStageSelection(
    this.key,
    this.duration, {
    this.effort = 'empty',
    this.paragraph = 1,
    this.automaticName = false,
    this.environment = 'silent',
    this.posture = 'sitting',
    this.finishManually = false,
  });
}

class SensorExperimentCard extends StatelessWidget {
  final SensorExperimentController controller;
  final String storageKey;
  final bool supportsNaming;
  final Future<List<ExperimentProfile>> Function() profiles;
  final Future<void> Function(List<ExperimentStageSelection>) start;
  const SensorExperimentCard({
    super.key,
    required this.controller,
    required this.storageKey,
    this.supportsNaming = false,
    required this.profiles,
    required this.start,
  });

  Future<void> _configure(BuildContext context) async {
    try {
      final available = await profiles();
      if (!context.mounted) return;
      if (available.isEmpty) {
        throw StateError('Save a sensor profile first.');
      }
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString('sensor-experiment-v1:$storageKey');
      final draft =
          saved == null ? <dynamic>[] : jsonDecode(saved) as List<dynamic>;
      final availableKeys = available.map((p) => p.key).toSet();
      final keys = <String?>[
        if (saved == null) available.first.key,
        for (final stage in draft)
          availableKeys.contains(stage['key']) ? stage['key'] as String : null,
      ];
      final durations = [
        if (saved == null) TextEditingController(text: '60'),
        for (final stage in draft)
          TextEditingController(text: stage['seconds'] as String),
      ];
      final efforts = <String>[
        if (saved == null) 'empty',
        for (final stage in draft) (stage['effort'] as String?) ?? 'empty',
      ];
      var paragraph =
          preferences.getInt('experiment-paragraph:$storageKey') ?? 1;
      paragraph = paragraph.clamp(1, 120);
      var environment =
          preferences.getString('experiment-environment:$storageKey') ??
              'silent';
      var posture =
          preferences.getString('experiment-posture:$storageKey') ?? 'sitting';
      var finishManually =
          preferences.getBool('experiment-manual:$storageKey') ?? true;
      var automaticName = supportsNaming &&
          (preferences.getBool('experiment-auto-name:$storageKey') ?? true);
      final counts = await ExperimentRecordingNames.counters(storageKey);
      final retiredControllers = <TextEditingController>[];
      int nextTake(int index) {
        final counter = ExperimentRecordingNames.counterKey(
          keys[index] ?? '',
          efforts[index],
          efforts[index] == 'empty' ? 1 : paragraph,
        );
        var take = (counts[counter] ?? 0) + 1;
        for (var j = 0; j < index; j++) {
          if (keys[j] == keys[index] && efforts[j] == efforts[index]) take++;
        }
        return take;
      }

      String preview(int index) {
        final key = keys[index];
        if (key == null) return 'Choose a profile to preview the filename.';
        final name = available.firstWhere((p) => p.key == key).name;
        return '${ExperimentRecordingNames.prefix(name, efforts[index], paragraph, nextTake(index), environment: environment, posture: posture)}<device-time>.oe';
      }

      if (!context.mounted) {
        for (final controller in durations) {
          controller.dispose();
        }
        return;
      }
      String? error;
      final result = await showDialog<List<ExperimentStageSelection>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Timed experiment'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Run saved profiles in order, then apply Off. Duration starts after hardware confirmation. Keep the app running and devices connected. SD logging follows each profile’s recording targets. Configuration confirmation does not verify SD writes.',
                    ),
                    if (supportsNaming) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Name SD logs automatically'),
                        subtitle: const Text(
                          'Corpus ID · take · environment · posture',
                        ),
                        value: automaticName,
                        onChanged: (value) =>
                            update(() => automaticName = value),
                      ),
                      if (automaticName)
                        Row(
                          children: [
                            const Expanded(child: Text('Corpus passage')),
                            IconButton(
                              tooltip: 'Previous paragraph',
                              onPressed: paragraph <= 1
                                  ? null
                                  : () => update(() => paragraph--),
                              icon: const Icon(Icons.remove),
                            ),
                            Text(
                              '$paragraph',
                              key: const ValueKey('experiment-paragraph'),
                            ),
                            IconButton(
                              tooltip: 'Next paragraph',
                              onPressed: paragraph >= 120
                                  ? null
                                  : () => update(() => paragraph++),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                    ],
                    if (supportsNaming) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey(paragraph),
                        initialValue: paragraph,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Passage · corpus version 1',
                        ),
                        items: [
                          for (final p in speechCorpus)
                            DropdownMenuItem(
                              value: p.number,
                              child: Text(
                                '${p.id} · ${p.title}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => update(() => paragraph = value!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: environment,
                        decoration:
                            const InputDecoration(labelText: 'Environment'),
                        items: [
                          for (final value in ['silent', 'ambient', 'noisy'])
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) =>
                            update(() => environment = value!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: posture,
                        decoration: const InputDecoration(
                          labelText: 'Posture / movement',
                        ),
                        items: [
                          for (final value in [
                            'walking',
                            'standing',
                            'sitting',
                          ])
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) => update(() => posture = value!),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Finish each paragraph manually'),
                        subtitle: const Text(
                          'Read naturally. The timer is a guide and never cuts off a sentence.',
                        ),
                        value: finishManually,
                        onChanged: (value) =>
                            update(() => finishManually = value),
                      ),
                    ],
                    if (keys.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Add a stage to start an experiment.'),
                      ),
                    for (var i = 0; i < keys.length; i++)
                      Card(
                        key: ObjectKey(durations[i]),
                        margin: const EdgeInsets.only(top: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text('Stage ${i + 1}')),
                                  IconButton(
                                    tooltip: 'Remove stage ${i + 1}',
                                    onPressed: () => update(() {
                                      keys.removeAt(i);
                                      efforts.removeAt(i);
                                      retiredControllers
                                          .add(durations.removeAt(i));
                                    }),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: keys[i],
                                      isExpanded: true,
                                      hint: const Text('Choose a profile'),
                                      decoration: InputDecoration(
                                        labelText: 'Profile',
                                        helperText: keys[i] == null
                                            ? 'Previous profile unavailable; choose a profile.'
                                            : null,
                                      ),
                                      items: [
                                        for (final p in available)
                                          DropdownMenuItem(
                                            value: p.key,
                                            child: Text(
                                              p.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (value) =>
                                          update(() => keys[i] = value),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      controller: durations[i],
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Seconds',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (automaticName) ...[
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: efforts[i],
                                  decoration: const InputDecoration(
                                    labelText: 'Speaking mode',
                                    helperText:
                                        'empty = resting baseline; silent = unvoiced mouthing',
                                  ),
                                  items: [
                                    for (final effort in [
                                      'empty',
                                      'vocal',
                                      'silent',
                                    ])
                                      DropdownMenuItem(
                                        value: effort,
                                        child: Text(effort),
                                      ),
                                  ],
                                  onChanged: (value) =>
                                      update(() => efforts[i] = value!),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Next take ${nextTake(i)} · ${preview(i)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    const Text('Final step: Off'),
                    if (automaticName)
                      const Text(
                        'Readable time uses this computer’s local clock. The device also appends its raw timestamp.',
                        style: TextStyle(fontSize: 12),
                      ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => update(() {
                  keys.add(keys.isEmpty ? available.first.key : keys.last);
                  efforts.add(efforts.isEmpty ? 'empty' : efforts.last);
                  durations.add(TextEditingController(text: '60'));
                }),
                icon: const Icon(Icons.add),
                label: const Text('Add stage'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (keys.isEmpty) {
                    update(() => error = 'Add at least one stage.');
                    return;
                  }
                  final seconds =
                      durations.map((c) => int.tryParse(c.text)).toList();
                  if (keys.any((key) => key == null)) {
                    update(() => error = 'Choose a profile for every stage.');
                    return;
                  }
                  if (seconds.any((s) => s == null || s <= 0 || s > 86400)) {
                    update(
                      () => error =
                          'Enter whole seconds from 1 to 86400 for every stage.',
                    );
                    return;
                  }
                  Navigator.pop(context, [
                    for (var i = 0; i < keys.length; i++)
                      ExperimentStageSelection(
                        keys[i]!,
                        Duration(seconds: seconds[i]!),
                        effort: efforts[i],
                        paragraph: paragraph,
                        automaticName: automaticName,
                        environment: environment,
                        posture: posture,
                        finishManually: supportsNaming && finishManually,
                      ),
                  ]);
                },
                child: Text(
                  supportsNaming ? 'Preview passage' : 'Start experiment',
                ),
              ),
            ],
          ),
        ),
      );
      // Save the draft even when dismissed, so profile choices survive navigation
      // and app restarts. Missing profiles require an explicit replacement.
      await preferences.setString(
        'sensor-experiment-v1:$storageKey',
        jsonEncode([
          for (var i = 0; i < keys.length; i++)
            {
              'key': keys[i],
              'seconds': durations[i].text,
              'effort': efforts[i],
            },
        ]),
      );
      await preferences.setInt('experiment-paragraph:$storageKey', paragraph);
      await preferences.setString(
        'experiment-environment:$storageKey',
        environment,
      );
      await preferences.setString('experiment-posture:$storageKey', posture);
      await preferences.setBool(
        'experiment-manual:$storageKey',
        finishManually,
      );
      await preferences.setBool(
        'experiment-auto-name:$storageKey',
        automaticName,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final controller in [...durations, ...retiredControllers]) {
        controller.dispose();
      }
      if (result != null) {
        if (supportsNaming && context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CorpusReadingPage(
                controller: controller,
                selections: result,
                onStart: () => start(result),
              ),
            ),
          );
        } else {
          await start(result);
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Experiment could not start: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Experiment mode',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${controller.status}${controller.remaining > Duration.zero ? " · ${controller.remaining.inSeconds + 1} s remaining" : ""}',
              ),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed:
                        controller.running ? null : () => _configure(context),
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('Set up experiment'),
                  ),
                  if (controller.running)
                    OutlinedButton(
                      onPressed: controller.stop,
                      child: const Text('Stop and turn Off'),
                    ),
                ],
              ),
              if (controller.events.isNotEmpty)
                ExpansionTile(
                  title: const Text('Experiment timing history (UTC)'),
                  children: [SelectableText(controller.events.join('\n'))],
                ),
            ],
          ),
        ),
      );
}

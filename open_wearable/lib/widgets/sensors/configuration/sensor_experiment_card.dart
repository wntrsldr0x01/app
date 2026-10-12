import 'package:flutter/material.dart';
import 'package:open_wearable/view_models/sensor_experiment_controller.dart';

class ExperimentProfile {
  final String key, name;
  ExperimentProfile(this.key, this.name);
}

class ExperimentStageSelection {
  final String key;
  final Duration duration;
  ExperimentStageSelection(this.key, this.duration);
}

class SensorExperimentCard extends StatelessWidget {
  final SensorExperimentController controller;
  final Future<List<ExperimentProfile>> Function() profiles;
  final Future<void> Function(List<ExperimentStageSelection>) start;
  const SensorExperimentCard({
    super.key,
    required this.controller,
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
      final keys = [available.first.key];
      final durations = [TextEditingController(text: '60')];
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
                      'Run saved profiles in order, then apply Off. Duration starts after hardware confirmation. Keep the app running and devices connected. SD logging follows each profile’s recording targets.',
                    ),
                    for (var i = 0; i < keys.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: keys[i],
                                decoration: InputDecoration(
                                  labelText: 'Stage ${i + 1} profile',
                                ),
                                items: [
                                  for (final p in available)
                                    DropdownMenuItem(
                                      value: p.key,
                                      child: Text(p.name),
                                    ),
                                ],
                                onChanged: (value) =>
                                    update(() => keys[i] = value!),
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
                      ),
                    TextButton.icon(
                      onPressed: () => update(() {
                        keys.add(available.first.key);
                        durations.add(TextEditingController(text: '60'));
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add stage'),
                    ),
                    const Text('Final step: Off'),
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
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final seconds =
                      durations.map((c) => int.tryParse(c.text)).toList();
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
                        keys[i],
                        Duration(seconds: seconds[i]!),
                      ),
                  ]);
                },
                child: const Text('Start experiment'),
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final controller in durations) {
        controller.dispose();
      }
      if (result != null) await start(result);
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

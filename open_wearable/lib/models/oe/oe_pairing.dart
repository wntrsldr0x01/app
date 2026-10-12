import 'dart:math' as math;
import 'oe_metadata.dart';
import 'oe_recording.dart';
import 'oe_timeline.dart';

/// Evidence from the file itself, never a claim of clock synchronization.
class OePairing {
  final bool likelyConcurrent;
  final double overlapSeconds, overlapFraction, startDifferenceSeconds;
  final int matchingChannels;
  final String description;
  OePairing._(this.likelyConcurrent, this.overlapSeconds, this.overlapFraction,
      this.startDifferenceSeconds, this.matchingChannels, this.description,);

  factory OePairing.assess(OeRecording a, OeRecording b) {
    final left = OeTimelineBounds.fromRecording(a);
    final right = OeTimelineBounds.fromRecording(b);
    Set<String> channels(OeRecording r) => {
          for (final s in r.sensors.values.where((s) => s.frameCount > 0))
            for (final c in s.components)
              '${s.id}|${s.name}|${s.isPcm}|${c.type}|${c.group}|${c.name}|${c.unit}',
        };
    final matching = channels(a).intersection(channels(b)).length;
    final overlapUs = math.max(
        0,
        math.min(left.endUs, right.endUs) -
            math.max(left.originUs, right.originUs),);
    final duration =
        math.max(left.endUs - left.originUs, right.endUs - right.originUs);
    final fraction = duration > 0 ? overlapUs / duration : 0.0;
    final startDifference = (left.originUs - right.originUs).abs() / 1e6;
    final opposite = {a.side, b.side}.containsAll({0, 1});
    final calendar = oeCalendarTime(left.originUs) != null &&
        oeCalendarTime(right.originUs) != null;
    final backwards = [...left.sensors.values, ...right.sensors.values]
        .any((s) => s.backwards > 0);
    final likely = opposite &&
        a.deviceId != b.deviceId &&
        calendar &&
        matching > 0 &&
        fraction >= .8 &&
        startDifference <= 2 &&
        !backwards &&
        a.incompleteReason == null &&
        b.incompleteReason == null;
    final reasons = <String>[
      if (!opposite) 'Ear sides are not complementary.',
      if (a.deviceId == b.deviceId) 'Both files identify the same device.',
      if (!calendar) 'Packet clock origin is unavailable or uptime-like.',
      if (matching == 0) 'No matching recorded sensor/channel schema.',
      if (fraction < .8)
        'Less than 80% of the longer timestamp extent overlaps.',
      if (startDifference > 2) 'Packet starts differ by more than 2 seconds.',
      if (backwards) 'Packet timestamps move backwards.',
      if (a.incompleteReason != null || b.incompleteReason != null)
        'At least one file is only partially interpreted.',
    ];
    return OePairing._(
        likely,
        overlapUs / 1e6,
        fraction,
        startDifference,
        matching,
        '${likely ? "Likely concurrent left/right candidate" : "Concurrent collection not established"}\n'
        '$matching matching recorded channels · packet start difference ${startDifference.toStringAsFixed(6)} s\n'
        'Timestamp extent overlap ${(overlapUs / 1e6).toStringAsFixed(6)} s · ${(fraction * 100).toStringAsFixed(1)}% of the longer log\n'
        'Header start difference ${((a.timestampUs - b.timestampUs).abs() / 1e6).toStringAsFixed(6)} s\n'
        '${reasons.join(" ")}\n'
        'This is a heuristic, not verified synchronization. Extent overlap can include gaps. '
        'OE v3 has no shared session ID or clock synchronization evidence; independently set clocks can appear to overlap. '
        'Manual offsets and matching signal shapes do not verify simultaneous acquisition.');
  }
}

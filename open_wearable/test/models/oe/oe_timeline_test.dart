import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:open_wearable/models/oe/oe_recording.dart';
import 'package:open_wearable/models/oe/oe_timeline.dart';
import 'oe_fixture.dart';
import 'oe_timeline_fixture.dart';

void main() {
  final reference = Platform.environment['OE_TIMELINE_REFERENCE'];
  test('full recording timeline includes every source frame on every axis', () {
    final r = OeRecording.parse(File(reference!).readAsBytesSync());
    final bounds = OeTimelineBounds.fromRecording(r);
    final channels = {for (final s in r.sensors.values.where((s) => s.frameCount > 0)) for (var c = 0; c < s.components.length; c++) '${s.id}:$c'};
    final watch = Stopwatch()..start();
    final plot = buildOeTimeline(OeTimelineRequest(r, bounds, channels, 0, bounds.seconds));
    watch.stop();
    for (final series in plot.series) {
      expect(series.finiteCount + series.nonFiniteCount, r.sensors[series.sensorId]!.frameCount);
      expect(series.bins.fold<int>(0, (sum, bin) => sum + bin.count), series.finiteCount);
      expect(series.bins.length, lessThanOrEqualTo(900));
    }
    expect(plot.series.length, channels.length);
    // Diagnostic performance measurement; no machine-dependent pass threshold.
    // ignore: avoid_print
    print('Full timeline: ${plot.series.length} channels, ${watch.elapsedMilliseconds} ms, ${bounds.seconds} s extent');
  }, skip: reference == null ? 'Private reference not supplied' : false,);

  test(
      'buffered timestamps use packet plus stored delta without audio rate assumptions',
      () {
    final r = OeRecording.parse(timelineFixture()),
        bounds = OeTimelineBounds.fromRecording(r);
    final bone = r.sensors[7]!;
    expect(bounds.originUs, 1791720544000000);
    expect(bounds.seconds, .004);
    expect(oeFrameTime(bone, bone.packets.first, 2), bounds.originUs + 3000);
    final plot = buildOeTimeline(OeTimelineRequest(
        r, bounds, {'7:0', '7:1', '0:0'}, 0, .004,
        bins: 100,),);
    final x = plot.series.firstWhere((s) => s.key == '7:0');
    expect(x.bins.map((b) => b.firstValue), [10, 11, 12]);
    expect(x.bins.map((b) => b.firstTimeUs - bounds.originUs), [1000, 2000, 3000]);
    expect(
        plot.series
            .firstWhere((s) => s.key == '7:1')
            .bins
            .map((b) => b.firstValue),
        [20, 21, 22],);
  });
  test('time window endpoints and every finite extreme are preserved', () {
    final r = OeRecording.parse(timelineFixture()),
        bounds = OeTimelineBounds.fromRecording(r);
    final plot = buildOeTimeline(
        OeTimelineRequest(r, bounds, {'0:0'}, .002, .004, bins: 1),);
    expect(plot.series.single.finiteCount, 2);
    expect(plot.series.single.bins.single.min, 4);
    expect(plot.series.single.bins.single.max, 7);
    expect(plot.series.single.bins.single.firstFrame, 1);
    expect(plot.series.single.bins.single.lastFrame, 2);
  });
  test('microphone frames retain packet anchors and signed sample bits', () {
    final r = OeRecording.parse(oeFixture()),
        bounds = OeTimelineBounds.fromRecording(r);
    final plot = buildOeTimeline(OeTimelineRequest(
        r, bounds, {'2:0', '2:1'}, 0, bounds.seconds,
        bins: 100,),);
    final outer = plot.series.first;
    expect(outer.finiteCount, 4);
    expect(outer.bins.length, 2);
    expect(outer.bins.first.count, 2);
    expect(outer.bins.first.min, -32768);
    expect(outer.bins.first.max, -1);
    expect(oeFrameTime(r.sensors[2]!, r.sensors[2]!.packets.first, 1),
        r.sensors[2]!.packets.first.timestampUs,);
  });
  test('anomalies remain visible and do not fabricate data in gaps', () {
    final r = OeRecording.parse(timelineFixture(anomalies: true));
    final before = r.bytes.toList(), bounds = OeTimelineBounds.fromRecording(r);
    expect(bounds.sensors[0]!.backwards, 1);
    expect(bounds.sensors[0]!.repeated, 1);
    final plot = buildOeTimeline(
        OeTimelineRequest(r, bounds, {'0:2'}, 0, .1, bins: 100),);
    expect(plot.series.single.nonFiniteCount, 1);
    expect(plot.series.single.finiteCount, 5);
    expect(plot.jumps.length, 1);
    final empty =
        buildOeTimeline(OeTimelineRequest(r, bounds, {'0:2'}, .02, .03));
    expect(empty.series.single.bins, isEmpty);
    expect(r.bytes, before);
  });
}

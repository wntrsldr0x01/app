/// Calendar interpretation only: OE v3 does not store clock synchronization
/// status or a timezone. Uptime-like values must not look like recording dates.
DateTime? oeCalendarTime(int? timestampUs) {
  if (timestampUs == null ||
      timestampUs < 946684800000000 ||
      timestampUs >= 4133980800000000) {
    return null;
  }
  return DateTime.fromMicrosecondsSinceEpoch(timestampUs, isUtc: true);
}

String oeDateLabel(int? timestampUs) {
  final utc = oeCalendarTime(timestampUs);
  if (utc == null) return 'Calendar date unavailable · clock origin unverified';
  final local = utc.toLocal();
  return '${local.toIso8601String().split('.').first.replaceFirst('T', ' ')} ${local.timeZoneName} · clock interpretation';
}

String oeEarLabel(int? side) => side == 0
    ? 'Left ear'
    : side == 1
        ? 'Right ear'
        : 'Ear side unknown';

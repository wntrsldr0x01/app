/// A persistent original file, addressed by SHA-256 rather than its filename.
class OeLibraryEntry {
  final String name, digest;
  final int size;
  final int? timestampUs, side;
  final String? deviceId;
  final String? sessionId;
  final int? importedAtUs;
  const OeLibraryEntry(
    this.name,
    this.digest,
    this.size, {
    this.timestampUs,
    this.side,
    this.deviceId,
    this.sessionId,
    this.importedAtUs,
  });
}

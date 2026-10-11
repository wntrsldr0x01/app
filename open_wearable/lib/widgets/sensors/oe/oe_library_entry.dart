/// A persistent original file, addressed by SHA-256 rather than its filename.
class OeLibraryEntry {
  final String name, digest;
  final int size;
  const OeLibraryEntry(this.name, this.digest, this.size);
}

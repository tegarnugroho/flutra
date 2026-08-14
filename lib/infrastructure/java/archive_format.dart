import 'dart:io';

/// The archive kinds a JDK download can arrive as.
///
/// Both vendors serve a different container per OS — `.zip` for Windows,
/// `.tar.gz` for Linux and macOS — so nothing downstream may assume one.
enum ArchiveFormat {
  zip('a zip archive'),
  tarGz('a gzipped tar archive'),
  tar('a tar archive'),

  /// Neither recognised by its bytes nor by its name. Usually an HTML error
  /// page a CDN returned with a 200.
  unknown('not a recognised archive');

  const ArchiveFormat(this.label);

  /// How the format reads in an error message.
  final String label;
}

/// How many bytes [sniffArchiveFormat] needs.
///
/// A tar's `ustar` marker sits at offset 257, which is what sets this — the zip
/// and gzip signatures are in the first four.
const int kArchiveSniffLength = 512;

/// The format [header] actually is, from its signature bytes.
///
/// Content, not file name: the name is metadata a vendor or a CDN can get
/// wrong, and mis-reading a `.tar.gz` as a zip is the whole bug this exists to
/// prevent. [ArchiveFormat.tar] is included because an HTTP client that
/// transparently decodes `Content-Encoding: gzip` leaves a plain tar on disk
/// under a `.tar.gz` name.
ArchiveFormat sniffArchiveFormat(List<int> header) {
  // gzip: 0x1F 0x8B.
  if (header.length >= 2 && header[0] == 0x1F && header[1] == 0x8B) {
    return ArchiveFormat.tarGz;
  }
  // zip: "PK" plus one of the three record signatures.
  if (header.length >= 4 && header[0] == 0x50 && header[1] == 0x4B) {
    const seconds = {0x03: 0x04, 0x05: 0x06, 0x07: 0x08};
    if (seconds[header[2]] == header[3]) return ArchiveFormat.zip;
  }
  // tar: "ustar" at offset 257, in both the POSIX and GNU variants.
  const ustar = [0x75, 0x73, 0x74, 0x61, 0x72];
  if (header.length >= 262) {
    var matches = true;
    for (var i = 0; i < ustar.length; i++) {
      if (header[257 + i] != ustar[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return ArchiveFormat.tar;
  }
  return ArchiveFormat.unknown;
}

/// The format [fileName] claims to be.
///
/// The fallback for when the bytes say nothing — a short or empty file has no
/// signature to read, and the name at least says what was meant.
ArchiveFormat formatFromName(String fileName) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) {
    return ArchiveFormat.tarGz;
  }
  if (name.endsWith('.zip')) return ArchiveFormat.zip;
  if (name.endsWith('.tar')) return ArchiveFormat.tar;
  return ArchiveFormat.unknown;
}

/// What [file] is, reading its signature and falling back to its name.
Future<ArchiveFormat> detectArchiveFormat(File file) async {
  List<int> header;
  try {
    final handle = await file.open();
    try {
      header = await handle.read(kArchiveSniffLength);
    } finally {
      await handle.close();
    }
  } catch (_) {
    header = const [];
  }

  final sniffed = sniffArchiveFormat(header);
  if (sniffed != ArchiveFormat.unknown) return sniffed;
  return formatFromName(file.path);
}

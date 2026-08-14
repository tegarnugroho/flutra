import 'dart:io';

import 'package:flutra/infrastructure/java/archive_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A buffer long enough for the tar marker at offset 257 to be readable.
List<int> _block({Map<int, List<int>> at = const {}}) {
  final bytes = List<int>.filled(kArchiveSniffLength, 0);
  at.forEach((offset, value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value[i];
    }
  });
  return bytes;
}

const _gzip = [0x1F, 0x8B, 0x08, 0x00];
const _zip = [0x50, 0x4B, 0x03, 0x04];
const _ustar = [0x75, 0x73, 0x74, 0x61, 0x72];

void main() {
  group('sniffArchiveFormat', () {
    test('gzip is what Adoptium serves to Linux and macOS', () {
      expect(sniffArchiveFormat(_block(at: {0: _gzip})), ArchiveFormat.tarGz);
    });

    test('a zip local-file header is a zip', () {
      expect(sniffArchiveFormat(_block(at: {0: _zip})), ArchiveFormat.zip);
    });

    test('the empty and spanned zip signatures count too', () {
      expect(
        sniffArchiveFormat(_block(at: {0: const [0x50, 0x4B, 0x05, 0x06]})),
        ArchiveFormat.zip,
      );
      expect(
        sniffArchiveFormat(_block(at: {0: const [0x50, 0x4B, 0x07, 0x08]})),
        ArchiveFormat.zip,
      );
    });

    test('PK followed by anything else is not a zip', () {
      expect(
        sniffArchiveFormat(_block(at: {0: const [0x50, 0x4B, 0x03, 0x09]})),
        ArchiveFormat.unknown,
      );
    });

    test('a plain tar is recognised by ustar at offset 257', () {
      // What a client that transparently un-gzips leaves on disk under a
      // .tar.gz name.
      expect(sniffArchiveFormat(_block(at: {257: _ustar})), ArchiveFormat.tar);
    });

    test('an HTML error page served with a 200 is not an archive', () {
      expect(
        sniffArchiveFormat('<!DOCTYPE html><html>503</html>'.codeUnits),
        ArchiveFormat.unknown,
      );
    });

    test('too few bytes to hold a signature is unknown, never a crash', () {
      expect(sniffArchiveFormat(const []), ArchiveFormat.unknown);
      expect(sniffArchiveFormat(const [0x1F]), ArchiveFormat.unknown);
      expect(sniffArchiveFormat(const [0x50, 0x4B]), ArchiveFormat.unknown);
      // Long enough for zip/gzip, too short for the tar marker.
      expect(sniffArchiveFormat(List<int>.filled(100, 0)), ArchiveFormat.unknown);
    });
  });

  group('formatFromName', () {
    test('the extensions each vendor actually publishes', () {
      expect(
        formatFromName('OpenJDK17U-jdk_x64_linux_hotspot_17.0.12_7.tar.gz'),
        ArchiveFormat.tarGz,
      );
      expect(
        formatFromName('OpenJDK17U-jdk_x64_windows_hotspot_17.0.12_7.zip'),
        ArchiveFormat.zip,
      );
      expect(formatFromName('jdk.tgz'), ArchiveFormat.tarGz);
      expect(formatFromName('jdk.tar'), ArchiveFormat.tar);
    });

    test('case does not decide the format', () {
      expect(formatFromName('JDK.TAR.GZ'), ArchiveFormat.tarGz);
      expect(formatFromName('JDK.ZIP'), ArchiveFormat.zip);
    });

    test('an unfamiliar extension is unknown, not a guess', () {
      expect(formatFromName('jdk.msi'), ArchiveFormat.unknown);
      expect(formatFromName('jdk'), ArchiveFormat.unknown);
    });
  });

  group('detectArchiveFormat', () {
    late Directory root;

    setUp(
      () => root = Directory.systemTemp.createTempSync('flutra_archive_test'),
    );
    tearDown(() => root.deleteSync(recursive: true));

    File write(String name, List<int> bytes) {
      final file = File(p.join(root.path, name));
      file.writeAsBytesSync(bytes);
      return file;
    }

    test('the bytes decide, not the name — this is the Linux bug', () async {
      // Exactly what broke: a tar.gz that some part of the pipeline believed
      // was a zip because it was on the zip code path.
      final file = write('jdk_linux.zip', _block(at: {0: _gzip}));

      expect(await detectArchiveFormat(file), ArchiveFormat.tarGz);
    });

    test('a real Windows zip is still a zip', () async {
      final file = write('jdk_windows.zip', _block(at: {0: _zip}));

      expect(await detectArchiveFormat(file), ArchiveFormat.zip);
    });

    test('an unreadable signature falls back to the name', () async {
      // Nothing to sniff, but the name still says what was meant.
      final file = write('jdk.tar.gz', const []);

      expect(await detectArchiveFormat(file), ArchiveFormat.tarGz);
    });

    test('no signature and no known extension is unknown', () async {
      final file = write('jdk.bin', 'not an archive'.codeUnits);

      expect(await detectArchiveFormat(file), ArchiveFormat.unknown);
    });

    test('a file that is not there does not throw', () async {
      expect(
        await detectArchiveFormat(File(p.join(root.path, 'missing.tar.gz'))),
        ArchiveFormat.tarGz,
      );
    });
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/platform/platform_service.dart';
import '../../domain/entities/reclaimable_item.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../storage/storage_analysis_service.dart';
import 'sdk_locator.dart';

/// Finds installed SDK packages that a newer one has replaced.
///
/// The rule is the same everywhere: within a family, everything below the
/// highest installed version is a candidate. What differs is the consequence
/// of removing it, which is what the warnings and the AVD check are for.
@lazySingleton
class ReclaimScanner {
  ReclaimScanner(this._sdk, this._locator, this._platform);

  final SdkRepository _sdk;
  final SdkLocator _locator;
  final PlatformService _platform;

  /// Lists candidates without their sizes — measuring 8 GB of system images
  /// takes long enough that the list has to appear first. See [measure].
  Future<ReclaimableReport> scan() async {
    final root = _locator.sdkRoot;
    if (root == null) {
      return ReclaimableReport(items: const [], scannedAt: DateTime.now());
    }
    final packages = await _sdk.listPackages();
    return ReclaimableReport(
      items: supersededItems(
        packages: packages,
        sdkRoot: root,
        avdUsage: await readAvdImageUsage(),
      ),
      scannedAt: DateTime.now(),
    );
  }

  /// Measures each item in turn, reporting as each one lands.
  ///
  /// One isolate per folder rather than one for all of them: a system image
  /// can take seconds on its own, and the list should fill in as it goes
  /// rather than all at once at the end.
  Stream<(String id, int bytes)> measure(List<ReclaimableItem> items) async* {
    for (final item in items) {
      final path = item.folderPath;
      final bytes = await Isolate.run(() => directorySizeSync(path));
      yield (item.id, bytes);
    }
  }

  /// Which system image each AVD is built on, keyed by package id.
  Future<Map<String, String>> readAvdImageUsage() async {
    final home = _avdHome();
    if (home == null) return const {};
    final dir = Directory(home);
    if (!dir.existsSync()) return const {};

    final configs = <String, String>{};
    try {
      for (final entry in dir.listSync().whereType<Directory>()) {
        if (!entry.path.endsWith('.avd')) continue;
        final config = File(p.join(entry.path, 'config.ini'));
        if (!config.existsSync()) continue;
        configs[p.basenameWithoutExtension(entry.path)] =
            await config.readAsString();
      }
    } catch (_) {
      // An unreadable AVD folder means one less known user, which the caller
      // treats as "not in use" — see the note in [supersededItems].
    }
    return parseAvdImageUsage(configs);
  }

  /// The AVD folder, resolved by the platform layer.
  String? _avdHome() => _platform.avdHome;

  // ---- Pure core -----------------------------------------------------------

  /// Package ids that only exist to run the SDK, never superseded by a newer
  /// sibling the way a versioned package is.
  static const Set<String> neverListed = {
    'platform-tools',
    'emulator',
    'tools',
  };

  /// Maps `<avd name> → config.ini contents` onto `<package id> → avd name`.
  ///
  /// The config records the image as a path fragment
  /// (`system-images\android-34\google_apis\x86_64\`), which is the package id
  /// with separators instead of semicolons.
  static Map<String, String> parseAvdImageUsage(Map<String, String> configs) {
    final usage = <String, String>{};
    configs.forEach((avdName, contents) {
      for (final line in const LineSplitter().convert(contents)) {
        if (!line.trim().startsWith('image.sysdir')) continue;
        final value = line.split('=').last.trim().replaceAll(r'\', '/');
        final id = value.split('/').where((s) => s.isNotEmpty).join(';');
        if (id.isEmpty) continue;
        // First AVD wins: the message names one user, and naming any real one
        // makes the same point.
        usage.putIfAbsent(id, () => avdName);
      }
    });
    return usage;
  }

  /// Every installed package that a newer one in its family has replaced.
  ///
  /// [avdUsage] blocks the system images something is built on. An AVD folder
  /// that could not be read simply is not in the map — the item then shows as
  /// removable, and the uninstall itself fails loudly rather than this guessing
  /// at a dependency it cannot see.
  static List<ReclaimableItem> supersededItems({
    required List<SdkPackage> packages,
    required String sdkRoot,
    Map<String, String> avdUsage = const {},
  }) {
    final families = <String, List<_Versioned>>{};

    for (final package in packages) {
      if (!package.isInstalled) continue;
      if (neverListed.contains(package.path)) continue;
      final parsed = _parse(package);
      if (parsed == null) continue;
      families.putIfAbsent(parsed.familyKey, () => []).add(parsed);
    }

    final items = <ReclaimableItem>[];
    for (final family in families.values) {
      if (family.length < 2) continue;
      // Newest first; index 0 is the one that supersedes the rest and is never
      // listed, however old it looks next to what is downloadable.
      family.sort((a, b) => compareSdkVersions(b.version, a.version));
      final newest = family.first;

      for (final superseded in family.skip(1)) {
        items.add(ReclaimableItem(
          id: superseded.package.path,
          kind: superseded.kind,
          displayName: superseded.displayName,
          folderPath: _folderFor(superseded.package, sdkRoot),
          reason: 'Superseded by ${newest.displayName}',
          supersededBy: newest.package.path,
          warnings: _warningsFor(superseded),
          blockedReason: superseded.kind == ReclaimKind.systemImage
              ? _avdBlock(superseded.package.path, avdUsage)
              : null,
        ));
      }
    }

    items.sort((a, b) {
      final byKind = a.kind.index.compareTo(b.kind.index);
      return byKind != 0 ? byKind : a.id.compareTo(b.id);
    });
    return items;
  }

  static String? _avdBlock(String id, Map<String, String> avdUsage) {
    final avd = avdUsage[id];
    return avd == null ? null : 'In use by AVD "$avd"';
  }

  static List<String> _warningsFor(_Versioned item) => switch (item.kind) {
        ReclaimKind.buildTools => const [
            'Projects that pin this version will re-download it on the next '
                'Gradle build.',
          ],
        ReclaimKind.ndk => const [
            'Projects that pin ndkVersion to this release will re-download it '
                'on the next Gradle build.',
          ],
        ReclaimKind.platform => [
            'Only remove if no local project targets API '
                '${item.version.replaceFirst('android-', '')}.',
          ],
        ReclaimKind.systemImage => const [
            'Creating a new AVD on this image will download it again.',
          ],
        ReclaimKind.sources || ReclaimKind.emulatorCache => const [],
      };

  /// Where the package sits on disk.
  ///
  /// `sdkmanager --list` reports the install location for most packages;
  /// falling back to the id-as-path only matters for the ones it leaves blank,
  /// and that mapping is exactly how sdkmanager lays them out.
  static String _folderFor(SdkPackage package, String sdkRoot) {
    final location = package.location?.trim();
    if (location != null && location.isNotEmpty) {
      return p.isAbsolute(location) ? location : p.join(sdkRoot, location);
    }
    return p.join(sdkRoot, p.joinAll(package.path.split(';')));
  }

  /// Splits a package id into the family it competes in and its version.
  static _Versioned? _parse(SdkPackage package) {
    final parts = package.path.split(';');
    if (parts.length < 2) return null;

    return switch (parts.first) {
      'build-tools' => _Versioned(
          package: package,
          kind: ReclaimKind.buildTools,
          familyKey: 'build-tools',
          version: parts[1],
          displayName: 'build-tools ${parts[1]}',
        ),
      'platforms' => _Versioned(
          package: package,
          kind: ReclaimKind.platform,
          familyKey: 'platforms',
          version: parts[1],
          displayName: 'platform ${parts[1]}',
        ),
      'sources' => _Versioned(
          package: package,
          kind: ReclaimKind.sources,
          familyKey: 'sources',
          version: parts[1],
          displayName: 'sources ${parts[1]}',
        ),
      'ndk' => _Versioned(
          package: package,
          kind: ReclaimKind.ndk,
          familyKey: 'ndk',
          version: parts[1],
          displayName: 'NDK ${parts[1]}',
        ),
      // A system image only supersedes one with the same tag and ABI: an
      // x86_64 image is no replacement for the arm64 one next to it.
      'system-images' when parts.length >= 4 => _Versioned(
          package: package,
          kind: ReclaimKind.systemImage,
          familyKey: 'system-images;${parts[2]};${parts[3]}',
          version: parts[1],
          displayName: '${parts[1]} ${parts[2]} ${parts[3]}',
        ),
      _ => null,
    };
  }
}

/// A package with the two things the supersede rule needs.
class _Versioned {
  const _Versioned({
    required this.package,
    required this.kind,
    required this.familyKey,
    required this.version,
    required this.displayName,
  });

  final SdkPackage package;
  final ReclaimKind kind;

  /// Packages sharing this key compete; the highest version wins.
  final String familyKey;

  final String version;
  final String displayName;
}

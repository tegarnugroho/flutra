import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/doctor_report.dart';
import '../../domain/entities/flutter_sdk_info.dart';
import '../../domain/repositories/flutter_repository.dart';
import '../sdk/flutter_locator.dart';
import '../trash/trash_service.dart';

/// [FlutterRepository] backed by the `flutter` command-line tool.
@LazySingleton(as: FlutterRepository)
class FlutterRepositoryImpl implements FlutterRepository {
  FlutterRepositoryImpl(this._runner, this._locator, this._trash);

  final CommandRunner _runner;
  final FlutterLocator _locator;
  final TrashService _trash;

  String get _flutter => _locator.executable;

  @override
  Future<DoctorReport> runDoctor() async {
    final result = await _runner.run(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      ['doctor', '-v'],
      timeout: const Duration(minutes: 5),
    );
    final output = result.combinedOutput;
    if (output.trim().isEmpty && !result.isSuccess) {
      throw const ExecutableNotFoundFailure(
        'flutter',
        suggestion: 'Add the Flutter SDK "bin" folder to your PATH.',
      );
    }
    return DoctorReport(sections: parse(output), rawOutput: output);
  }

  @override
  Future<List<Device>> listDevices() async {
    final result = await _runner.run(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      ['devices', '--machine'],
      timeout: const Duration(minutes: 2),
    );
    return parseFlutterDevices(result.stdout);
  }

  /// Parses `flutter devices --machine` JSON into [Device]s. Static & pure.
  static List<Device> parseFlutterDevices(String output) {
    // Flutter may print warnings before the JSON; isolate the array.
    final start = output.indexOf('[');
    final end = output.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    final dynamic decoded;
    try {
      decoded = jsonDecode(output.substring(start, end + 1));
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];

    return decoded.whereType<Map<String, dynamic>>().map((json) {
      final target = json['targetPlatform'] as String?;
      final id = json['id'] as String? ?? '';
      final isAndroid = target?.startsWith('android') ?? false;
      return Device(
        serial: id,
        state: DeviceState.device,
        model: json['name'] as String?,
        sdkInt: null,
        platform: target,
        supportsAdb: isAndroid,
      );
    }).where((d) => d.serial.isNotEmpty).toList();
  }

  // ---- SDK version management ----------------------------------------------

  @override
  Future<FlutterSdkInfo> getSdkInfo() async {
    final result = await _runner.run(
      _flutter,
      ['--version', '--machine'],
      timeout: const Duration(minutes: 2),
    );
    // A non-zero exit means flutter is missing or its SDK is broken (e.g. a
    // half-deleted folder that lost its .git). Either way it isn't usable, so
    // treat it as "not installed" and let the UI offer a fresh install.
    if (!result.isSuccess) {
      throw const ExecutableNotFoundFailure(
        'flutter',
        suggestion: 'Install a Flutter SDK, or add its "bin" folder to PATH.',
      );
    }
    var info = parseSdkInfo(result.stdout);
    // Attach the git origin URL so the UI can offer to fix a non-standard one.
    final root = info.sdkPath;
    if (info.isGitRepo && root != null) {
      try {
        final remote = await _runner.run(
          'git',
          ['-C', root, 'remote', 'get-url', 'origin'],
          timeout: const Duration(seconds: 10),
        );
        if (remote.isSuccess) {
          info = info.copyWith(remoteUrl: remote.stdout.trim());
        }
      } catch (_) {}
    }
    return info;
  }

  @override
  Future<void> fixUpstreamRemote() async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) {
      throw const UnknownFailure('This SDK is not a git checkout.');
    }
    final result = await _runner.run(
      'git',
      [
        '-C', root, 'remote', 'set-url', 'origin',
        'https://github.com/flutter/flutter.git',
      ],
      timeout: const Duration(seconds: 15),
    );
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Failed to update the git remote.',
        exitCode: result.exitCode,
        output: result.combinedOutput,
      );
    }
  }

  /// Parses `flutter --version --machine` JSON. Static & pure for tests.
  static FlutterSdkInfo parseSdkInfo(String output) {
    final start = output.indexOf('{');
    final end = output.lastIndexOf('}');
    Map<String, dynamic> json = const {};
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(output.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        json = const {};
      }
    }
    final root = json['flutterRoot'] as String?;
    final isGit = root != null && Directory(p.join(root, '.git')).existsSync();
    return FlutterSdkInfo(
      version: json['frameworkVersion'] as String? ?? 'unknown',
      channel: json['channel'] as String? ?? 'unknown',
      dartVersion: json['dartSdkVersion'] as String?,
      frameworkRevision: (json['frameworkRevisionShort'] ??
          json['frameworkRevision']) as String?,
      engineRevision: (json['engineRevisionShort'] ?? json['engineRevision'])
          as String?,
      sdkPath: root,
      isGitRepo: isGit,
    );
  }

  @override
  Future<List<String>> listVersions(String channel) async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) return const [];

    // Restrict tags to those reachable from the channel's branch so each
    // channel shows its own versions.
    final ref = await _channelRef(root, channel);
    final result = await _runner.run(
      'git',
      [
        '-C', root, 'tag', '-l', '--sort=-v:refname',
        if (ref != null) ...['--merged', ref],
      ],
      timeout: const Duration(seconds: 30),
    );
    if (!result.isSuccess) return const [];
    // Stable exposes clean x.y.z releases; beta/master include pre-release tags.
    return parseVersionTags(result.stdout,
        includePreRelease: channel != 'stable');
  }

  /// Resolves a usable git ref for [channel] (remote first, then local).
  Future<String?> _channelRef(String root, String channel) async {
    for (final ref in ['origin/$channel', channel]) {
      final r = await _runner.run(
        'git',
        ['-C', root, 'rev-parse', '--verify', '--quiet', ref],
        timeout: const Duration(seconds: 10),
      );
      if (r.isSuccess && r.stdout.trim().isNotEmpty) return ref;
    }
    return null;
  }

  /// Keeps release tags, newest first. Stable-style "3.24.1" always; when
  /// [includePreRelease] also beta/dev tags like "3.45.0-1.2.pre".
  static List<String> parseVersionTags(String output,
      {bool includePreRelease = false}) {
    final stable = RegExp(r'^\d+\.\d+\.\d+$');
    final pre = RegExp(r'^\d+\.\d+\.\d+-\d+\.\d+\.pre$');
    return const LineSplitter()
        .convert(output)
        .map((l) => l.trim())
        .where((t) =>
            stable.hasMatch(t) || (includePreRelease && pre.hasMatch(t)))
        .toList();
  }

  @override
  Future<RunningCommand> switchChannel(String channel) =>
      _runner.start(_flutter, ['channel', channel]);

  @override
  Future<RunningCommand> upgrade() =>
      _runner.start(_flutter, ['upgrade']);

  @override
  Future<RunningCommand> resetToStable() async {
    // Switch back to the official stable branch (quick), then stream the
    // upgrade that actually re-syncs the SDK.
    await _runner.run(_flutter, ['channel', 'stable'],
        timeout: const Duration(minutes: 2));
    return _runner.start(_flutter, ['upgrade']);
  }

  @override
  Future<RunningCommand> switchVersion(String version) async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) {
      throw const UnknownFailure(
        'This Flutter SDK is not a git checkout, so versions cannot be '
        'switched. Use channels or reinstall Flutter via git.',
      );
    }
    // Check out the tag; the tool snapshot is rebuilt by the following command.
    final checkout = await _runner.run(
      'git',
      ['-C', root, 'checkout', version],
      timeout: const Duration(minutes: 2),
    );
    if (!checkout.isSuccess) {
      throw ProcessFailure(
        'Failed to check out Flutter $version.',
        exitCode: checkout.exitCode,
        output: checkout.combinedOutput,
        suggestion: 'Commit or stash local changes in the SDK first.',
      );
    }
    // Ensure the upstream remote stays official so Flutter Doctor doesn't warn
    // about a "non-standard remote" after the checkout. Best-effort.
    if (!info.isStandardRemote) {
      try {
        await _runner.run(
          'git',
          [
            '-C', root, 'remote', 'set-url', 'origin',
            'https://github.com/flutter/flutter.git',
          ],
          timeout: const Duration(seconds: 15),
        );
      } catch (_) {}
    }
    // Running any flutter command now regenerates the version snapshot.
    return _runner.start(_flutter, ['--version']);
  }

  @override
  Future<List<String>> changelog(
      String version, String? previousVersion) async {
    final info = await getSdkInfo();
    final root = info.sdkPath;
    if (root == null || !info.isGitRepo) return const [];

    final hasPrev = previousVersion != null && previousVersion.isNotEmpty;
    final args = [
      '-C', root, 'log',
      '--no-merges',
      '--pretty=format:%s',
      '-n', hasPrev ? '400' : '50',
      if (hasPrev) '$previousVersion..$version' else version,
    ];
    final result = await _runner.run('git', args,
        timeout: const Duration(seconds: 30));
    if (!result.isSuccess) return const [];
    return const LineSplitter()
        .convert(result.stdout)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Future<RunningCommand> installSdk(String directory, String ref) async {
    final dir = directory.trim();
    if (dir.isEmpty) {
      throw const UnknownFailure('Choose an install folder first.');
    }
    final target = Directory(dir);
    if (target.existsSync() && target.listSync().isNotEmpty) {
      // Never auto-delete a non-empty folder — it could be a working SDK. If it
      // already holds a Flutter, say so; otherwise ask for an empty folder.
      final isFlutter = File(p.join(dir, 'bin',
                  Platform.isWindows ? 'flutter.bat' : 'flutter'))
              .existsSync() ||
          Directory(p.join(dir, 'packages')).existsSync();
      throw FileSystemFailure(
        isFlutter
            ? 'A Flutter SDK already exists at "$dir". Press Refresh to use it, '
                'or uninstall it first.'
            : 'Folder "$dir" is not empty. Pick an empty/new folder, or clear '
                'it first.',
      );
    }
    // `-b` accepts a channel branch (stable/beta/master) or a version tag.
    return _runner.start('git', [
      'clone',
      '-b',
      ref,
      'https://github.com/flutter/flutter.git',
      dir,
    ]);
  }

  @override
  Future<List<String>> listInstallableVersions(String channel) async {
    try {
      final response = await Dio().get<dynamic>(
        'https://storage.googleapis.com/flutter_infra_release/releases/'
        'releases_windows.json',
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      final map = data is String
          ? jsonDecode(data) as Map<String, dynamic>
          : data as Map<String, dynamic>;
      final releases = (map['releases'] as List).cast<Map<String, dynamic>>();
      final versions = <String>[];
      final seen = <String>{};
      for (final r in releases) {
        if (r['channel'] != channel) continue;
        final v = r['version'] as String?;
        if (v == null || !seen.add(v)) continue;
        versions.add(v);
      }
      return versions;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> addSdkToPath(String sdkDir) async {
    if (!Platform.isWindows) return;
    final bin = p.join(sdkDir, 'bin');
    // Append to the *user* PATH only if not already present, via PowerShell so
    // the existing value is read and written safely (no setx truncation).
    final script = "\$b='$bin'; "
        "\$p=[Environment]::GetEnvironmentVariable('Path','User'); "
        "if(\$p -notlike \"*\$b*\"){"
        "[Environment]::SetEnvironmentVariable('Path', "
        "(\$p.TrimEnd(';') + ';' + \$b), 'User')}";
    final result = await _runner.run(
      'powershell',
      ['-NoProfile', '-Command', script],
      timeout: const Duration(seconds: 30),
    );
    if (!result.isSuccess) {
      throw ProcessFailure(
        'Could not update PATH automatically.',
        exitCode: result.exitCode,
        output: result.combinedOutput,
        suggestion: 'Add "$bin" to your PATH manually.',
      );
    }
  }

  @override
  Future<void> uninstallSdk(String sdkPath) async {
    final dir = Directory(sdkPath);
    if (!dir.existsSync()) {
      throw FileSystemFailure('Flutter SDK folder not found: $sdkPath');
    }
    // Safety: only delete something that looks like a Flutter SDK (a full one,
    // or leftovers from a previous partial uninstall).
    final looksLikeFlutter = File(p.join(sdkPath, 'bin',
                Platform.isWindows ? 'flutter.bat' : 'flutter'))
            .existsSync() ||
        Directory(p.join(sdkPath, 'bin')).existsSync() ||
        Directory(p.join(sdkPath, 'packages')).existsSync() ||
        p.basename(sdkPath).toLowerCase() == 'flutter';
    if (!looksLikeFlutter) {
      throw FileSystemFailure(
        '"$sdkPath" does not look like a Flutter SDK — refusing to delete it.',
      );
    }

    // Soft-delete: move to the trash (kept 24h) instead of erasing, so the user
    // can restore or cancel. This is also an instant move, not a slow delete.
    await _trash.trash(sdkPath, label: 'Flutter SDK');
  }

  @override
  Future<void> openReleasePage(String version) async {
    final url = 'https://github.com/flutter/flutter/releases/tag/$version';
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url],
          runInShell: true, mode: ProcessStartMode.detached);
    } else {
      final opener = Platform.isMacOS ? 'open' : 'xdg-open';
      await Process.start(opener, [url], mode: ProcessStartMode.detached);
    }
  }

  /// Parses `flutter doctor -v` output into sections. Static and pure for tests.
  ///
  /// Section headers look like `[✓] Flutter (…)`; subsequent indented lines are
  /// details for the current section.
  static List<DoctorSection> parse(String output) {
    final header = RegExp(r'^\[(.)\]\s?(.*)$');
    final sections = <DoctorSection>[];

    DoctorStatus? status;
    String? title;
    var details = <String>[];

    void flush() {
      final currentTitle = title;
      if (currentTitle != null) {
        sections.add(DoctorSection(
          status: status ?? DoctorStatus.info,
          title: currentTitle.trim(),
          details: List.of(details),
        ));
      }
    }

    for (final rawLine in const LineSplitter().convert(output)) {
      final match = header.firstMatch(rawLine.trimLeft());
      if (match != null && !rawLine.startsWith(' ')) {
        flush();
        status = _statusFromMarker(match.group(1)!);
        title = match.group(2);
        details = [];
      } else if (title != null) {
        final trimmed = rawLine.trim();
        if (trimmed.isNotEmpty) details.add(trimmed);
      }
    }
    flush();
    return sections;
  }

  static DoctorStatus _statusFromMarker(String marker) => switch (marker) {
        // Flutter doctor renders a check as "✓" on most terminals but "√"
        // (U+221A) on the Windows console.
        '✓' || '√' => DoctorStatus.ok,
        '!' => DoctorStatus.warning,
        '✗' || '✘' || 'x' || 'X' => DoctorStatus.error,
        _ => DoctorStatus.info,
      };
}

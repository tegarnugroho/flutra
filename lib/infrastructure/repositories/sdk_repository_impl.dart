import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../core/command/command_runner.dart';
import '../../core/command/sdk_operation_lock.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../sdk/android_tool_runner.dart';
import '../sdk/sdk_locator.dart';

/// [SdkRepository] backed by the real `sdkmanager` command-line tool.
@LazySingleton(as: SdkRepository)
class SdkRepositoryImpl implements SdkRepository {
  SdkRepositoryImpl(this._runner, this._locator, this._lock);

  /// Every spawn goes through here rather than [CommandRunner] directly, so
  /// sdkmanager is handed the JDK this app manages — see [AndroidToolRunner].
  final AndroidToolRunner _runner;
  final SdkLocator _locator;
  final SdkOperationLock _lock;

  static final RegExp _promptPattern =
      RegExp(r'\(y/N\)|Accept\? ', caseSensitive: false);

  String get _sdkManager {
    final path = _locator.sdkManager;
    if (path == null) {
      throw const ExecutableNotFoundFailure(
        'sdkmanager',
        suggestion: 'Install "cmdline-tools;latest" first, then set the SDK '
            'path in Environment Settings.',
      );
    }
    return path;
  }

  List<String> get _rootArg {
    final root = _locator.sdkRoot;
    return root == null ? const [] : ['--sdk_root=$root'];
  }

  @override
  Future<List<SdkPackage>> listPackages() async {
    final result = await _runner.run(
      _sdkManager,
      // --channel=0 is already the default, but saying so keeps the answer the
      // same whatever a previous run or an `sdkmanager.cfg` left behind.
      ['--list', '--channel=0', ..._rootArg],
      timeout: const Duration(minutes: 3),
    );
    final listing = parseListing(result.stdout);

    // Whether "no packages" is an answer or a failure is decided by the output,
    // not by the exit code alone.
    //
    // sdkmanager is a shell wrapper around a Java program, and when it cannot
    // find java it prints "ERROR: JAVA_HOME is not set…" — on *stdout*, with
    // stderr empty. A check for "failed and said nothing" therefore passes, and
    // the error text parses to zero packages: the page then reports an empty
    // catalogue for a query that never ran. A run that worked always prints at
    // least one section header, so that is what is tested here.
    //
    // The second clause covers a run that exits 0 having printed nothing usable.
    // "Available Packages" is the remote catalogue, so it is there even for an
    // SDK with nothing installed — but it is *not* there when the network was
    // unreachable and only the local section could be built, which is why an
    // empty catalogue is only suspicious when nothing parsed at all.
    if (!result.isSuccess ||
        !listing.hasSections ||
        (listing.packages.isEmpty && !listing.hasAvailableSection)) {
      throw ProcessFailure(
        'sdkmanager could not read the package list.',
        exitCode: result.exitCode,
        output: result.combinedOutput.isEmpty
            ? '(sdkmanager produced no output)'
            : result.combinedOutput,
        suggestion: 'Check your internet connection, the SDK path, and that a '
            'JDK is installed — sdkmanager needs Java to run.',
      );
    }
    return listing.packages;
  }

  @override
  Future<RunningCommand> install(String path) => _locked(
        'An install',
        () => _startWithAutoYes([path, ..._rootArg],
            fromCopy: _isCmdlineTools(path)),
      );

  @override
  Future<RunningCommand> uninstall(String path) => _locked(
        'An uninstall',
        () => _startWithAutoYes(['--uninstall', path, ..._rootArg],
            fromCopy: _isCmdlineTools(path)),
      );

  @override
  Future<RunningCommand> acceptAllLicenses() => _locked(
        'The licence prompt',
        () => _startWithAutoYes(['--licenses', ..._rootArg]),
      );

  @override
  Future<RunningCommand> updateAll({bool includesCmdlineTools = false}) =>
      _locked(
        'An update',
        () => _startWithAutoYes(['--update', ..._rootArg],
            fromCopy: includesCmdlineTools),
      );

  /// Runs [start] under the shared SDK lock, holding it until the process
  /// exits — sdkmanager locks its own repository, so two of these at once fail
  /// in ways that are hard to read.
  Future<RunningCommand> _locked(
    String operation,
    Future<RunningCommand> Function() start,
  ) async {
    if (!_lock.claim(operation)) {
      throw UnknownFailure(
        '${_lock.busyLabel} is already running on this SDK.',
        cause: null,
      );
    }
    try {
      final command = await start();
      command.result
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(_lock.release);
      return command;
    } catch (_) {
      _lock.release();
      rethrow;
    }
  }

  /// True for the packages that hold sdkmanager itself — the modern
  /// `cmdline-tools` and the legacy `tools`.
  static bool _isCmdlineTools(String path) =>
      path.startsWith('cmdline-tools') || path == 'tools';

  /// Starts sdkmanager and answers "y" to every interactive license prompt.
  ///
  /// With [fromCopy], sdkmanager is launched from a throwaway copy of the
  /// cmdline-tools folder: the tool loads its jars out of `<tool>/lib`, so on
  /// Windows it cannot overwrite its own files ("The process cannot access the
  /// file because it is being used by another process"). Running the copy
  /// leaves the real folder unlocked. The copy is deleted when the command
  /// exits.
  Future<RunningCommand> _startWithAutoYes(
    List<String> args, {
    bool fromCopy = false,
  }) async {
    final executable = fromCopy ? await _sdkManagerCopy() : _sdkManager;
    final command = await _runner.start(executable, args);
    if (fromCopy) {
      final temp = p.dirname(p.dirname(executable));
      unawaited(command.result.whenComplete(() => _deleteQuietly(temp)));
    }
    // Respond to each prompt as it appears.
    command.output.listen((line) {
      if (_promptPattern.hasMatch(line.text)) {
        command.writeLine('y');
      }
    });
    // Also seed a few up-front, in case prompts are emitted before we attach.
    for (var i = 0; i < 3; i++) {
      command.writeLine('y');
    }
    return command;
  }

  /// Copies the cmdline-tools installation to a temp folder and returns the
  /// sdkmanager inside it. `--sdk_root` still points at the real SDK, so the
  /// copy installs into the right place.
  Future<String> _sdkManagerCopy() async {
    final source = p.dirname(p.dirname(_sdkManager)); // <tool>/bin/sdkmanager
    final temp = await Directory.systemTemp.createTemp('sdkmgr_cmdline_');
    try {
      await _copyDirectory(Directory(source), temp);
    } catch (e) {
      await _deleteQuietly(temp.path);
      throw FileSystemFailure(
        'Could not stage a copy of cmdline-tools.',
        suggestion: 'Free up temp space and try again.',
        cause: e,
      );
    }
    return p.join(temp.path, 'bin', p.basename(_sdkManager));
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final target = p.join(to.path, p.relative(entity.path, from: from.path));
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
      }
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final dir = Directory(path);
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {
      // A leftover temp folder is harmless; the OS clears it eventually.
    }
  }

  // ---- Parsing -------------------------------------------------------------

  /// Parses the pipe-delimited, three-section output of `sdkmanager --list`.
  ///
  /// Sections: "Installed packages:", "Available Packages:", "Available
  /// Updates:". Static and pure so it can be unit-tested against captured
  /// fixtures.
  static List<SdkPackage> parseList(String output) =>
      parseListing(output).packages;

  /// [parseList] plus whether the output looked like a package listing at all.
  ///
  /// The distinction matters because zero packages is ambiguous on its own: a
  /// brand-new SDK legitimately has nothing installed, while a query that never
  /// reached the repository also parses to nothing. A run that worked always
  /// prints at least one section header, so [SdkListing.hasSections] is what
  /// separates "empty" from "did not happen" — see [listPackages].
  ///
  /// Deliberately forgiving about shape, because the shape moves between
  /// cmdline-tools releases and between platforms: `\r\n` and bare `\r`
  /// (sdkmanager redraws its progress bar with carriage returns), any amount of
  /// column padding, and either casing of the section headers.
  static SdkListing parseListing(String output) {
    final byPath = <String, SdkPackage>{};
    final sections = <_Section>{};
    _Section section = _Section.none;

    for (final rawLine in const LineSplitter().convert(output)) {
      // LineSplitter already treats a bare \r as a terminator, but output that
      // reached us some other way (a fixture read whole, a pasted log) has not
      // been through it.
      final line = rawLine.replaceAll('\r', '').trimRight();
      final lower = line.trim().toLowerCase();

      // Headers are matched loosely: "Installed packages:" and "Installed
      // Packages:" have both shipped, and the trailing colon is not guaranteed.
      if (lower.startsWith('installed packages')) {
        section = _Section.installed;
        sections.add(section);
        continue;
      }
      if (lower.startsWith('available packages')) {
        section = _Section.available;
        sections.add(section);
        continue;
      }
      if (lower.startsWith('available updates')) {
        section = _Section.updates;
        sections.add(section);
        continue;
      }
      if (section == _Section.none) continue;

      // Skip headers, separators and blank lines.
      if (!line.contains('|')) continue;
      final cells = line.split('|').map((c) => c.trim()).toList();
      final first = cells.first;
      if (first.isEmpty ||
          const {'path', 'id', 'package'}.contains(first.toLowerCase()) ||
          _separatorRow.hasMatch(first)) {
        continue;
      }

      switch (section) {
        case _Section.installed:
          if (cells.length < 2) break;
          byPath[first] = SdkPackage(
            path: first,
            description: cells.length > 2 ? cells[2] : first,
            state: PackageState.installed,
            installedVersion: cells[1].isEmpty ? null : cells[1],
            location: cells.length > 3 ? cells[3] : null,
          );
        case _Section.available:
          if (byPath.containsKey(first)) break; // installed takes precedence
          if (cells.length < 2) break;
          byPath[first] = SdkPackage(
            path: first,
            description: cells.length > 2 ? cells[2] : first,
            state: PackageState.available,
            availableVersion: cells[1].isEmpty ? null : cells[1],
          );
        case _Section.updates:
          // Columns: ID | Installed | Available
          final existing = byPath[first];
          byPath[first] = SdkPackage(
            path: first,
            description: existing?.description ?? first,
            state: PackageState.updatable,
            installedVersion:
                cells.length > 1 && cells[1].isNotEmpty ? cells[1] : existing?.installedVersion,
            availableVersion:
                cells.length > 2 && cells[2].isNotEmpty ? cells[2] : null,
            location: existing?.location,
          );
        case _Section.none:
          break;
      }
    }

    final list = byPath.values.toList();
    list.sort((a, b) {
      final byCat = a.category.index.compareTo(b.category.index);
      return byCat != 0 ? byCat : a.path.compareTo(b.path);
    });
    return SdkListing(
      packages: list,
      hasSections: sections.isNotEmpty,
      hasAvailableSection: sections.contains(_Section.available),
    );
  }

  /// The `-------` rule under a column header, however wide it was drawn.
  static final RegExp _separatorRow = RegExp(r'^[-\s]+$');
}

/// What `sdkmanager --list` said, including whether it said anything at all.
class SdkListing {
  const SdkListing({
    required this.packages,
    required this.hasSections,
    required this.hasAvailableSection,
  });

  final List<SdkPackage> packages;

  /// True when at least one "Installed packages" / "Available Packages" /
  /// "Available Updates" header was seen — that is, when the output was a
  /// package listing rather than an error message or a truncated run.
  final bool hasSections;

  /// True when the "Available Packages" section specifically was present.
  ///
  /// It is the section that is never legitimately absent: it lists the whole
  /// remote catalogue, so an SDK with nothing installed still has one.
  final bool hasAvailableSection;
}

enum _Section { none, installed, available, updates }

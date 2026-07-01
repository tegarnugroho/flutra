import 'dart:convert';

import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/sdk_package.dart';
import '../../domain/repositories/sdk_repository.dart';
import '../sdk/sdk_locator.dart';

/// [SdkRepository] backed by the real `sdkmanager` command-line tool.
@LazySingleton(as: SdkRepository)
class SdkRepositoryImpl implements SdkRepository {
  SdkRepositoryImpl(this._runner, this._locator);

  final CommandRunner _runner;
  final SdkLocator _locator;

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
      ['--list', ..._rootArg],
      timeout: const Duration(minutes: 3),
    );
    if (!result.isSuccess && result.stdout.isEmpty) {
      throw ProcessFailure(
        'sdkmanager --list failed.',
        exitCode: result.exitCode,
        output: result.combinedOutput,
        suggestion: 'Check your internet connection and SDK path.',
      );
    }
    return parseList(result.stdout);
  }

  @override
  Future<RunningCommand> install(String path) =>
      _startWithAutoYes([path, ..._rootArg]);

  @override
  Future<RunningCommand> uninstall(String path) =>
      _startWithAutoYes(['--uninstall', path, ..._rootArg]);

  @override
  Future<RunningCommand> acceptAllLicenses() =>
      _startWithAutoYes(['--licenses', ..._rootArg]);

  /// Starts sdkmanager and answers "y" to every interactive license prompt.
  Future<RunningCommand> _startWithAutoYes(List<String> args) async {
    final command = await _runner.start(_sdkManager, args);
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

  // ---- Parsing -------------------------------------------------------------

  /// Parses the pipe-delimited, three-section output of `sdkmanager --list`.
  ///
  /// Sections: "Installed packages:", "Available Packages:", "Available
  /// Updates:". Static and pure so it can be unit-tested against captured
  /// fixtures.
  static List<SdkPackage> parseList(String output) {
    final byPath = <String, SdkPackage>{};
    _Section section = _Section.none;

    for (final rawLine in const LineSplitter().convert(output)) {
      final line = rawLine.trimRight();
      final lower = line.trim().toLowerCase();

      if (lower.startsWith('installed packages')) {
        section = _Section.installed;
        continue;
      }
      if (lower.startsWith('available packages')) {
        section = _Section.available;
        continue;
      }
      if (lower.startsWith('available updates')) {
        section = _Section.updates;
        continue;
      }
      if (section == _Section.none) continue;

      // Skip headers, separators and blank lines.
      if (!line.contains('|')) continue;
      final cells = line.split('|').map((c) => c.trim()).toList();
      final first = cells.first;
      if (first.isEmpty ||
          first.toLowerCase() == 'path' ||
          first.toLowerCase() == 'id' ||
          RegExp(r'^-+$').hasMatch(first)) {
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
    return list;
  }
}

enum _Section { none, installed, available, updates }

import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';

import '../../core/command/command_runner.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/doctor_report.dart';
import '../../domain/repositories/flutter_repository.dart';

/// [FlutterRepository] backed by the `flutter` command-line tool.
@LazySingleton(as: FlutterRepository)
class FlutterRepositoryImpl implements FlutterRepository {
  FlutterRepositoryImpl(this._runner);

  final CommandRunner _runner;

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

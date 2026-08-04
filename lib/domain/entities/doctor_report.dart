import 'package:equatable/equatable.dart';

/// Status of a single `flutter doctor` check, from its `[✓] / [!] / [✗]` marker.
enum DoctorStatus { ok, warning, error, info }

/// One section of `flutter doctor -v` output.
class DoctorSection extends Equatable {
  const DoctorSection({
    required this.status,
    required this.title,
    this.details = const [],
    this.elapsed,
  });

  final DoctorStatus status;

  /// The heading text, e.g. "Flutter (Channel stable, 3.44.1, on ...)".
  final String title;

  /// Indented detail lines beneath the heading.
  final List<String> details;

  /// How long the check took, as reported by `flutter doctor -v` itself.
  final Duration? elapsed;

  @override
  List<Object?> get props => [status, title, details, elapsed];
}

/// The full result of running `flutter doctor -v`.
class DoctorReport extends Equatable {
  const DoctorReport({required this.sections, required this.rawOutput});

  final List<DoctorSection> sections;
  final String rawOutput;

  int count(DoctorStatus status) =>
      sections.where((s) => s.status == status).length;

  bool get hasProblems =>
      sections.any((s) => s.status != DoctorStatus.ok);

  @override
  List<Object?> get props => [sections, rawOutput];
}

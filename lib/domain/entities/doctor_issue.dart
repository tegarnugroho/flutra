import 'package:equatable/equatable.dart';

import 'doctor_report.dart';

/// How a doctor problem gets resolved.
enum FixKind {
  /// The app runs the commands itself; the user only confirms.
  auto,

  /// The app needs an answer first — which JDK, which browser, which folder.
  guided,

  /// Nothing to run: hand the user to an installer, a doc page, or another
  /// screen of this app.
  redirect,
}

/// A known `flutter doctor` problem and what to do about it.
///
/// Equatable rather than freezed to match every other entity here; the project
/// has no freezed model, and one would be the odd file out.
class DoctorIssue extends Equatable {
  const DoctorIssue({
    required this.id,
    required this.categoryMatch,
    required this.linePattern,
    required this.kind,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.url,
  });

  /// Stable identifier, also the key an executor registers under.
  final String id;

  /// The check name this applies to, as [DoctorStreamParser.checkName] reports
  /// it — "Android toolchain", not the whole heading.
  final String categoryMatch;

  /// Matched against the check's detail lines.
  final RegExp linePattern;

  final FixKind kind;

  /// Shown as the fix dialog's heading.
  final String title;

  /// What the fix will do, in one or two sentences.
  final String description;

  /// The button on the check row. "Fix" for most, something specific for
  /// redirects, where "Fix" would over-promise.
  final String actionLabel;

  /// Where a [FixKind.redirect] issue points, when it points outside the app.
  final String? url;

  @override
  List<Object?> get props => [id, categoryMatch, linePattern.pattern, kind];
}

/// The docs every unmatched failure falls back to.
const String kWindowsInstallDocs =
    'https://docs.flutter.dev/get-started/install/windows';

/// Every problem the app knows how to act on.
///
/// Order matters: the first pattern that hits a line wins within a category,
/// so the more specific entries come first.
final List<DoctorIssue> kDoctorIssues = [
  DoctorIssue(
    id: 'android_licenses',
    categoryMatch: 'Android toolchain',
    linePattern:
        RegExp(r'Android license(s)? (status unknown|not accepted)', caseSensitive: false),
    kind: FixKind.auto,
    title: 'Accept the Android SDK licences',
    description:
        'Runs the licence prompt and answers yes to each one. Nothing is '
        'installed or removed — this only records that you accepted the terms.',
    actionLabel: 'Fix',
  ),
  DoctorIssue(
    id: 'cmdline_tools_missing',
    categoryMatch: 'Android toolchain',
    linePattern: RegExp(r'cmdline-tools component is missing', caseSensitive: false),
    kind: FixKind.auto,
    title: 'Install the Android command-line tools',
    description:
        'Installs the "cmdline-tools;latest" package, which sdkmanager, '
        'avdmanager and this app all need.',
    actionLabel: 'Fix',
  ),
  DoctorIssue(
    id: 'android_sdk_missing',
    categoryMatch: 'Android toolchain',
    linePattern: RegExp(r'Unable to locate Android SDK', caseSensitive: false),
    kind: FixKind.guided,
    title: 'Point Flutter at an Android SDK',
    description:
        'Finds the SDKs already on this machine and tells Flutter which one to '
        'use.',
    actionLabel: 'Fix',
  ),
  DoctorIssue(
    id: 'jdk_missing_or_invalid',
    categoryMatch: 'Android toolchain',
    linePattern: RegExp(
      r'(No Java Development Kit|Cannot find Java|Could not find valid JDK)',
      caseSensitive: false,
    ),
    kind: FixKind.guided,
    title: 'Choose a JDK for Flutter',
    description:
        'Lists the JDKs installed here and points Flutter at the one you pick. '
        'Android builds need JDK 17 or newer.',
    actionLabel: 'Fix',
  ),
  DoctorIssue(
    id: 'chrome_missing',
    categoryMatch: 'Chrome',
    linePattern: RegExp(r'Cannot find Chrome executable', caseSensitive: false),
    kind: FixKind.guided,
    title: 'Choose a browser for web builds',
    description:
        'Any Chromium browser works. The one you pick is used for this app\'s '
        'own commands straight away, and saved for new terminals.',
    actionLabel: 'Fix',
  ),
  DoctorIssue(
    id: 'vs_incomplete',
    categoryMatch: 'Visual Studio',
    // Flutter says "is missing necessary components", not "missing
    // components" — the optional word is what makes this match the real
    // output rather than a paraphrase of it.
    linePattern: RegExp(
      r'(unable to find a suitable Visual Studio toolchain'
      r'|missing (necessary |required )?components'
      r'|Windows 10 SDK)',
      caseSensitive: false,
    ),
    kind: FixKind.guided,
    title: 'Add the C++ workload to Visual Studio',
    description:
        'Opens the Visual Studio Installer, elevated, and adds the "Desktop '
        'development with C++" workload that Windows builds need.',
    actionLabel: 'Fix',
  ),
  DoctorIssue(
    id: 'vs_missing',
    categoryMatch: 'Visual Studio',
    linePattern: RegExp(r'Visual Studio not installed', caseSensitive: false),
    kind: FixKind.redirect,
    title: 'Visual Studio is not installed',
    description:
        'Windows desktop builds need Visual Studio with the "Desktop '
        'development with C++" workload.',
    actionLabel: 'Download Visual Studio',
    url: 'https://visualstudio.microsoft.com/downloads/',
  ),
  DoctorIssue(
    id: 'no_devices',
    categoryMatch: 'Connected device',
    linePattern: RegExp(r'No devices available', caseSensitive: false),
    kind: FixKind.redirect,
    title: 'No devices are available',
    description: 'Start an emulator, or plug in a device with USB debugging on.',
    actionLabel: 'Launch emulator',
  ),
  DoctorIssue(
    id: 'flutter_not_on_path',
    categoryMatch: 'Flutter',
    linePattern:
        RegExp(r'Flutter binary is not on your PATH', caseSensitive: false),
    kind: FixKind.guided,
    title: 'Add Flutter to your PATH',
    description:
        'Appends the SDK\'s "bin" folder to your user PATH so "flutter" works '
        'in any terminal.',
    actionLabel: 'Fix',
  ),
];

/// The catch-all for a failing check nothing in the registry recognises.
final DoctorIssue kUnknownIssue = DoctorIssue(
  id: 'unknown',
  categoryMatch: '',
  linePattern: RegExp(r'$a^'), // never matches; this issue is only synthesised
  kind: FixKind.redirect,
  title: 'This one needs a look by hand',
  description:
      'The app has no automatic fix for this check. The Windows install guide '
      'covers every requirement Flutter checks for.',
  actionLabel: 'View docs',
  url: kWindowsInstallDocs,
);

/// The issues a check has, in registry order.
///
/// Several can match at once — an Android toolchain missing both its licences
/// and cmdline-tools is one check with two problems, and each gets its own
/// button. A passing check never has any.
List<DoctorIssue> issuesFor({
  required String category,
  required DoctorStatus? status,
  required List<String> detailLines,
}) {
  if (status == null || status == DoctorStatus.ok) return const [];

  final matched = [
    for (final issue in kDoctorIssues)
      if (issue.categoryMatch == category &&
          detailLines.any(issue.linePattern.hasMatch))
        issue,
  ];
  // A failure the registry has nothing for still deserves a way forward.
  return matched.isEmpty ? [kUnknownIssue] : matched;
}

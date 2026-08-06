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
    this.platforms = const {},
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

  /// The operating systems this problem can occur on — `windows`, `linux`,
  /// `macos`. Empty means every platform.
  ///
  /// Visual Studio is not a thing to be missing on Linux, and a doctor run
  /// there never mentions it; listing the issue anyway would only produce a
  /// button that cannot help.
  final Set<String> platforms;

  /// Whether this issue applies on [operatingSystem].
  bool appliesTo(String operatingSystem) =>
      platforms.isEmpty || platforms.contains(operatingSystem);

  @override
  List<Object?> get props =>
      [id, categoryMatch, linePattern.pattern, kind, platforms];
}

/// The install guide for [operatingSystem], which every unmatched failure
/// falls back to.
String installDocsFor(String operatingSystem) =>
    'https://docs.flutter.dev/get-started/install/$operatingSystem';

/// The Windows guide, kept for callers that predate the per-platform one.
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
    platforms: {'windows'},
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
    platforms: {'windows'},
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
    id: 'linux_deps_missing',
    categoryMatch: 'Linux toolchain',
    linePattern: RegExp(
      r'(clang\+{0,2} is required'
      r'|CMake is required'
      r'|ninja is required'
      r'|GTK 3\.0 development libraries are required'
      r'|pkg-config is required)',
      caseSensitive: false,
    ),
    kind: FixKind.guided,
    platforms: {'linux'},
    title: 'Install the Linux build dependencies',
    description:
        'Flutter needs clang, CMake, ninja, pkg-config and the GTK 3 headers '
        'to build a Linux desktop app. The install runs through pkexec, so the '
        'system asks for your password — this app never sees it.',
    actionLabel: 'Fix',
  ),
  DoctorIssue(
    id: 'xcode_missing',
    categoryMatch: 'Xcode',
    linePattern: RegExp(
      r'(Xcode installation is incomplete|Unable to locate Xcode'
      r'|Xcode not installed)',
      caseSensitive: false,
    ),
    kind: FixKind.redirect,
    platforms: {'macos'},
    title: 'Xcode is missing or incomplete',
    description:
        'macOS builds need the full Xcode, not only the command-line tools. '
        'Install it from the App Store, then run "xcode-select --install" for '
        'the command-line tools.',
    actionLabel: 'Open the App Store page',
    url: 'https://apps.apple.com/app/xcode/id497799835',
  ),
  DoctorIssue(
    id: 'xcode_license',
    categoryMatch: 'Xcode',
    linePattern: RegExp(
      r'Xcode end user license agreement not signed',
      caseSensitive: false,
    ),
    kind: FixKind.guided,
    platforms: {'macos'},
    title: 'Accept the Xcode licence',
    description:
        'Runs "xcodebuild -license accept" as an administrator. macOS shows '
        'its own authentication dialog; this app never sees your password.',
    actionLabel: 'Fix',
  ),
  DoctorIssue(
    id: 'cocoapods_missing',
    categoryMatch: 'Xcode',
    linePattern: RegExp(
      r'(CocoaPods not installed|CocoaPods installed but not working)',
      caseSensitive: false,
    ),
    kind: FixKind.auto,
    platforms: {'macos'},
    title: 'Install CocoaPods',
    description:
        'Installs CocoaPods with Homebrew when it is present, and falls back '
        'to "gem install" as an administrator otherwise.',
    actionLabel: 'Fix',
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
      'The app has no automatic fix for this check. The install guide covers '
      'every requirement Flutter checks for.',
  actionLabel: 'View docs',
  url: kWindowsInstallDocs,
);

/// The fallback issue, pointing at [operatingSystem]'s own install guide.
DoctorIssue unknownIssueFor(String operatingSystem) => DoctorIssue(
      id: kUnknownIssue.id,
      categoryMatch: kUnknownIssue.categoryMatch,
      linePattern: kUnknownIssue.linePattern,
      kind: kUnknownIssue.kind,
      title: kUnknownIssue.title,
      description: kUnknownIssue.description,
      actionLabel: kUnknownIssue.actionLabel,
      url: installDocsFor(operatingSystem),
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
  required String operatingSystem,
}) {
  if (status == null || status == DoctorStatus.ok) return const [];

  final matched = [
    for (final issue in kDoctorIssues)
      if (issue.appliesTo(operatingSystem) &&
          issue.categoryMatch == category &&
          detailLines.any(issue.linePattern.hasMatch))
        issue,
  ];
  // A failure the registry has nothing for still deserves a way forward.
  return matched.isEmpty ? [unknownIssueFor(operatingSystem)] : matched;
}

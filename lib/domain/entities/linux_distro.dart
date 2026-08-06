import 'package:equatable/equatable.dart';

/// The package manager families the Linux dependency fix knows how to talk to.
enum LinuxPackageFamily { debian, fedora, arch, unknown }

/// One distro's way of installing the Flutter Linux build dependencies.
class LinuxInstallCommand extends Equatable {
  const LinuxInstallCommand({required this.family, required this.command});

  final LinuxPackageFamily family;

  /// The full command, exactly as it will run or be copied.
  final String command;

  /// What to call this in the UI.
  String get label => switch (family) {
        LinuxPackageFamily.debian => 'Debian / Ubuntu',
        LinuxPackageFamily.fedora => 'Fedora / RHEL',
        LinuxPackageFamily.arch => 'Arch',
        LinuxPackageFamily.unknown => 'Unknown distribution',
      };

  @override
  List<Object?> get props => [family, command];
}

/// The dependencies `flutter doctor` asks for, per family.
const List<LinuxInstallCommand> kLinuxDependencyCommands = [
  LinuxInstallCommand(
    family: LinuxPackageFamily.debian,
    command:
        'apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev',
  ),
  LinuxInstallCommand(
    family: LinuxPackageFamily.fedora,
    command:
        'dnf install -y clang cmake ninja-build gtk3-devel pkgconf-pkg-config',
  ),
  LinuxInstallCommand(
    family: LinuxPackageFamily.arch,
    command: 'pacman -S --needed clang cmake ninja pkgconf gtk3',
  ),
];

/// Reads `/etc/os-release` and works out which package manager to offer.
///
/// `ID_LIKE` is what makes this work on the derivatives: Linux Mint is
/// `ID=linuxmint ID_LIKE=ubuntu debian`, Pop!_OS is `ID_LIKE=ubuntu debian`,
/// and neither would match on `ID` alone. An unrecognised distro returns
/// [LinuxPackageFamily.unknown], and the caller offers all three commands to
/// copy rather than running a guess as root.
LinuxPackageFamily parseLinuxFamily(String osRelease) {
  final values = <String, String>{};
  for (final line in osRelease.split('\n')) {
    final trimmed = line.trim();
    final eq = trimmed.indexOf('=');
    if (eq <= 0 || trimmed.startsWith('#')) continue;
    final key = trimmed.substring(0, eq).trim();
    // Values may or may not be quoted: ID=fedora, ID_LIKE="ubuntu debian".
    final value = trimmed
        .substring(eq + 1)
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '')
        .toLowerCase();
    values[key] = value;
  }

  final ids = <String>[
    if (values['ID'] != null) values['ID']!,
    ...?values['ID_LIKE']?.split(RegExp(r'\s+')),
  ].where((id) => id.isNotEmpty);

  for (final id in ids) {
    final family = switch (id) {
      'debian' || 'ubuntu' || 'linuxmint' || 'pop' || 'raspbian' =>
        LinuxPackageFamily.debian,
      'fedora' || 'rhel' || 'centos' || 'nobara' => LinuxPackageFamily.fedora,
      'arch' || 'archlinux' || 'manjaro' || 'endeavouros' =>
        LinuxPackageFamily.arch,
      _ => null,
    };
    if (family != null) return family;
  }
  return LinuxPackageFamily.unknown;
}

/// The commands to offer for [family]: one to run, or all three to copy when
/// the distro is not recognised.
List<LinuxInstallCommand> installCommandsFor(LinuxPackageFamily family) {
  if (family == LinuxPackageFamily.unknown) return kLinuxDependencyCommands;
  return [kLinuxDependencyCommands.firstWhere((c) => c.family == family)];
}

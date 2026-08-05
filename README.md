# android_sdk_manager

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Building

Use the build script, not `flutter build` directly:

```powershell
.\tool\build.ps1                  # release build + MSIX + .exe installer
.\tool\build.ps1 -SkipMsix        # installer only
.\tool\build.ps1 -SkipInstaller   # MSIX only
.\tool\build.ps1 -ExeOnly         # neither, just the exe
.\tool\build.ps1 -Bump            # bump the version first, don't ask
.\tool\build.ps1 -NoBump          # keep the current version, don't ask
```

Outputs:

| | Path |
|---|---|
| exe | `build\windows\x64\runner\Release\android_sdk_manager.exe` |
| MSIX | `build\windows\x64\runner\Release\FlutterSdkManager.msix` |
| installer | `build\installer\FlutterSdkManager-Setup-<version>.exe` |

On startup it asks whether to raise the version. Answering yes bumps the patch
number and the build number together and writes them to `pubspec.yaml`, to
`msix_config.msix_version` (its own field, and Windows refuses to upgrade a
package whose MSIX version did not rise) and to the fallback constants in
`lib/core/constants/app_info.dart`. Answering no builds what is already there.

Pass `-Bump` or `-NoBump` to answer in advance. A run with redirected input is
never asked and never bumps, so an unattended build cannot invent a release.

The script reads the version from `pubspec.yaml`, the toolchain from
`flutter --version --machine` and the commit from `git`, then passes them as
`--dart-define` values. Without them the About window has nothing to report and
shows `—` for the version, channel, toolchain and commit.

Packaging is the default because it is how this project ships, and it matters
for the same reason: `dart run msix:create` runs its own
`flutter build windows` and inherits nothing from a build you ran first, so
packaging by hand ships a binary with no metadata. The script routes the
defines through msix's `--windows-build-args` instead, so only one build runs
and the installer wraps that same output.

The installer is compiled by [Inno Setup](https://jrsoftware.org/isinfo.php)
from `tool/installer.iss`; the script finds `ISCC.exe` in the usual install
locations, or takes `-IsccPath`. It installs per-user, so no admin prompt, and
offers to close a running instance before upgrading over it.

A build made with uncommitted changes is tagged `<hash>-dirty`, so a bug report
from that binary can't be traced to the wrong source.

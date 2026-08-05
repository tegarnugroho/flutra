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
.\tool\build.ps1                     # release build + MSIX package
.\tool\build.ps1 -ExeOnly            # release exe only
.\tool\build.ps1 -Mode debug -ExeOnly
```

The script reads the version from `pubspec.yaml`, the toolchain from
`flutter --version --machine` and the commit from `git`, then passes them as
`--dart-define` values. Without them the About window has nothing to report and
shows `—` for the version, channel, toolchain and commit.

Packaging is the default because it is how this project ships, and it matters
for the same reason: `dart run msix:create` runs its own
`flutter build windows` and inherits nothing from a build you ran first, so
packaging by hand ships a binary with no metadata. The script routes the
defines through msix's `--windows-build-args` instead, so only one build runs.

A build made with uncommitted changes is tagged `<hash>-dirty`, so a bug report
from that binary can't be traced to the wrong source.

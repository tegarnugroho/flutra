# Flutra

A graphical frontend for the Android SDK command-line tools for Windows, Linux,
and macOS. It wraps `sdkmanager`, `avdmanager`, `adb`, and `emulator` in a UI,
so everyday jobs — installing a package, creating an AVD, reading a licence,
watching logcat — do not need a terminal.

Everything it reports is read from those tools. It does not bundle its own copy
of the SDK, and the Dashboard never deletes anything on its own: it surfaces
what it found and routes you to the page that can act on it.
## Screenshots

<p align="center">
  <img
    src="https://github.com/user-attachments/assets/36800d84-cae2-4cc5-a06f-b54ab2a2f2af"
    width="85%"
    alt="Flutra Virtual Devices"
  />
</p>

<p align="center">
  <sub><b>Virtual Devices</b> — Create, manage, and launch Android emulators.</sub>
</p>

<br>

<table>
  <tr>
    <td width="50%" align="center">
      <img
        src="https://github.com/user-attachments/assets/831c91b8-de63-4213-bd7f-d463c3f29c8f"
        width="100%"
        alt="Flutra Dashboard"
      />
    </td>
    <td width="50%" align="center">
      <img
        src="https://github.com/user-attachments/assets/9a56a2ef-08cb-4926-8b49-e0fbb98cb285"
        width="100%"
        alt="Flutra SDK Manager"
      />
    </td>
  </tr>
  <tr>
    <td align="center">
      <sub><b>Dashboard</b><br>SDK status, storage overview, and quick actions.</sub>
    </td>
    <td align="center">
      <sub><b>SDK Manager</b><br>Browse, install, update, and remove SDK packages.</sub>
    </td>
  </tr>
</table>

## Screens

| Screen | What it does |
| --- | --- |
| Dashboard | Install state, storage breakdown, and shortcuts into the pages below |
| SDK Manager | Browse, install and remove SDK packages |
| Virtual Devices | Create, launch and delete AVDs |
| Licenses | Review the licences `sdkmanager` asks for |
| Logcat | Live device log |
| Updates | Packages with a newer version available |
| Flutter SDK | Installed Flutter channel and released versions |
| Flutter Doctor | `flutter doctor` output, parsed |
| Devices | Attached devices and running emulators |
| Settings | SDK path override, theme, close-to-tray, run at startup |

The Create Emulator wizard, the emulator console, the developer log, and the
About box each open in their own window.

## Requirements

- Flutter on a Dart SDK matching `^3.12.1`, with desktop support for your
  platform
- The Android SDK command-line tools, for the app to drive
- Per platform:
  - **Windows 10+ (x64)** — Visual Studio with the "Desktop development with
    C++" workload. Flutter's Windows toolchain is required.
  - **Linux** — `clang cmake ninja-build pkg-config libgtk-3-dev`. These are
    the same packages the app's own Flutter Doctor fix offers to install. Plus
    `libayatana-appindicator3-dev`, which the tray icon needs and which the
    doctor fix does not cover — without it the build stops at CMake.
  - **macOS** — Xcode plus its command-line tools (`xcode-select --install`),
    and CocoaPods.

The SDK root is resolved in this order, first hit wins: the override in
Settings, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, then the platform's usual install
location — `%LOCALAPPDATA%\Android\Sdk` on Windows, `~/Android/Sdk` on Linux,
and `~/Library/Android/sdk` on macOS.

Nothing needs to be configured if Android Studio put the SDK where it normally
does.

The AVD folder follows the emulator's own precedence: `ANDROID_AVD_HOME`, then
`ANDROID_USER_HOME/avd`, then `~/.android/avd`.

### Platform status

| Platform | State |
| --- | --- |
| Windows | Developed and tested |
| Linux | Builds and packages in CI; not yet run by a maintainer |
| macOS | Builds and packages in CI and has been tested manually. The `.dmg` is currently unsigned and un-notarised; see **macOS Gatekeeper** below. |

### macOS Gatekeeper

The macOS `.dmg` is currently unsigned and un-notarised. Because of this,
macOS may block Flutra the first time it is opened with a message such as:

> Apple could not verify "Flutra" is free of malware that may harm your Mac or
> compromise your privacy.

After opening the `.dmg`, copy **Flutra.app** to the Applications folder.

If macOS blocks the app, open Terminal and run:

```bash
xattr -dr com.apple.quarantine /Applications/Flutra.app
```

Then open **Flutra** normally from Applications.

Alternatively, you can try right-clicking **Flutra.app** → **Open** and confirm
the Gatekeeper prompt.

> [!NOTE]
> This workaround is required because the current macOS build is not signed and
> notarised with an Apple Developer ID. It does not disable Gatekeeper globally;
> it only removes the quarantine attribute from `Flutra.app`.

The Mac App Store is currently not a suitable distribution target because
Flutra needs to spawn external processes and modify shell configuration files,
which conflicts with App Sandbox restrictions.

[Inno Setup 6](https://jrsoftware.org/isinfo.php) is needed only to build the
Windows `.exe` installer.

## Running from source

Install dependencies and generate the required source files:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Then run Flutra for the current desktop platform.

### Windows

```powershell
flutter run -d windows
```

### Linux

```bash
flutter run -d linux
```

### macOS

```bash
flutter run -d macos
```

`build_runner` generates the freezed models, the JSON serialisers, and the
get_it/injectable registrations. Run it again after touching an `@injectable`
class or a `@freezed` model.

Only one instance runs per session. Launching the app again surfaces the window
that is already open — including when it is minimised or hidden in the tray —
rather than starting a second copy that would fight the first over the same SDK
directory and settings file.

This applies to debug builds too, so close a running copy before `flutter run`.

## Building

CI (`.github/workflows/ci.yml`) analyzes and tests on every push, builds
Windows and a Linux **AppImage** on every push and pull request, and produces
an unsigned macOS `.dmg` on pushes to `main` and tags.

The Linux job runs on `ubuntu-22.04`, so the AppImage needs glibc 2.35 or newer
— old enough for current distributions, but not for 20.04-era ones.

> **After a rename or any change to `BINARY_NAME`, run `flutter clean` first.**
>
> CMake caches `CMAKE_INSTALL_PREFIX` as `$<TARGET_FILE_DIR:<old name>>`, and a
> stale build directory then fails to configure with "No target ...".

### Windows

On Windows, use the build script rather than `flutter build` directly:

```powershell
.\tool\build.ps1                  # release build + MSIX + .exe installer
.\tool\build.ps1 -SkipMsix        # installer only
.\tool\build.ps1 -SkipInstaller   # MSIX only
.\tool\build.ps1 -ExeOnly         # neither, just the exe
.\tool\build.ps1 -Bump            # bump the version first, don't ask
.\tool\build.ps1 -NoBump          # keep the current version, don't ask
```

Outputs:

| Artifact | Path |
| --- | --- |
| exe | `build\windows\x64\runner\Release\flutra.exe` |
| MSIX | `build\windows\x64\runner\Release\Flutra.msix` |
| installer | `build\installer\Flutra-Setup-<version>.exe` |

`-Mode profile` or `-Mode debug` build the other two modes; `-SkipPubGet` skips
`flutter pub get` on a repeat build.

### Versioning

On startup the script asks whether to raise the version. Answering yes bumps
the patch number and the build number together and writes them to three places:

| File | Field |
| --- | --- |
| `pubspec.yaml` | `version:` |
| `pubspec.yaml` | `msix_config.msix_version` — its own field, and Windows refuses to upgrade a package whose MSIX version did not rise |
| `lib/core/constants/app_info.dart` | The fallback constants a defineless run shows |

Answering no builds what is already there. `-Bump` and `-NoBump` answer in
advance.

A run with redirected input is never asked and never bumps, so an unattended
build cannot invent a release.

### Why the script

It reads the version from `pubspec.yaml`, the toolchain from
`flutter --version --machine`, and the commit from `git`, then passes them as
`--dart-define` values.

Without them the About window has nothing to report and shows `—` for the
version, channel, toolchain, and commit.

A build made with uncommitted changes is tagged `<hash>-dirty`, so a bug report
from that binary cannot be traced to the wrong source.

Packaging is the default because it is how this project ships, and it matters
for the same reason: `dart run msix:create` runs its own `flutter build windows`
and inherits nothing from a build you ran first, so packaging by hand ships a
binary with no metadata.

The script routes the defines through msix's `--windows-build-args` instead, so
only one build runs and the installer wraps that same output.

The installer is compiled from `tool/installer.iss`; the script finds
`ISCC.exe` in the usual install locations, or takes `-IsccPath`.

It installs per-user, so no admin prompt, and offers to close a running instance
before upgrading over it.

## Where it stores things

On Windows:

```text
%APPDATA%\com.androidsdkmanager\android_sdk_manager
```

| File | Contents |
| --- | --- |
| `settings.json` | SDK path override, theme, window bounds, preferences |
| `storage-report.json` | Cached disk scan, refreshed after 24 hours |
| `flutter_releases_windows.json` | Cached Flutter release index |
| `dev-log.log` | What the Developer Logs window reads |

Uninstalling leaves the folder alone, so a reinstall keeps your settings.

## Layout

```text
lib/
  application/     cubits and app-wide buses (ShellNavigator, EmulatorEvents)
  core/            constants, DI wiring, shared helpers
  domain/          models
  infrastructure/  the services that run the tools and parse their output
  presentation/    windows, pages, widgets, theme
windows/runner/    the native host: single instance, sub-window plugins
tool/              build.ps1 and installer.iss
test/
```

## Tests

Run static analysis:

```bash
flutter analyze
```

Run the test suite:

```bash
flutter test
```

The suite leans on widget tests for layout regressions — overflow at specific
window sizes and scale factors, skeleton alignment, rail-mode collapse — and on
parser tests for the tool output the app depends on.

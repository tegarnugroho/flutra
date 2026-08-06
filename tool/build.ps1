#Requires -Version 5.1
<#
.SYNOPSIS
    Builds Flutra for Windows, then packages it as an MSIX and an
    Inno Setup installer, with its build metadata baked in.

.DESCRIPTION
    The About window reads its version, channel, toolchain and commit from
    --dart-define values. `flutter build` on its own passes none of them, so a
    plain build reports "—" for everything a build alone can know.

    This script gathers those facts and hands them to the build:

      APP_VERSION           from pubspec.yaml
      APP_BUILD_NUMBER      from pubspec.yaml (the part after '+')
      APP_CHANNEL           from `flutter --version --machine`
      APP_FLUTTER_VERSION   from `flutter --version --machine`
      APP_DART_VERSION      from `flutter --version --machine`
      APP_COMMIT            from `git rev-parse --short HEAD`

    Dart's version is also readable at runtime, so it is the one value that
    survives a defineless build; it is passed anyway so a release reports the
    Dart it was compiled with rather than the one it happens to run on.

.PARAMETER Mode
    release (default), profile or debug.

.PARAMETER ExeOnly
    Build the exe and stop, skipping both packages.

    Packaging is the default because it is how this project ships. msix:create
    runs its own `flutter build windows` and inherits nothing from a build you
    ran beforehand, so a plain `dart run msix:create` would ship a binary whose
    About window reports "—" for everything. The defines are routed through
    msix's --windows-build-args instead, so only one build runs either way; the
    Inno Setup installer then wraps that same output.

.PARAMETER SkipMsix
    Skip the MSIX, keep the Inno Setup installer.

.PARAMETER SkipInstaller
    Skip the Inno Setup installer, keep the MSIX.

.PARAMETER IsccPath
    Path to Inno Setup's compiler. Found automatically in the usual install
    locations; pass it when Inno Setup lives somewhere else.

.PARAMETER Bump
    Raise the patch version and build number before building, without asking.

.PARAMETER NoBump
    Build the version already in pubspec.yaml, without asking.

    With neither switch the script asks. It only asks when a human is there to
    answer — a redirected or non-interactive run keeps the current version, so
    an unattended build can never invent a release.

.PARAMETER SkipPubGet
    Skip `flutter pub get`. Useful for repeat builds.

.EXAMPLE
    # Release: one build, then both an MSIX and an .exe installer.
    .\tool\build.ps1

.EXAMPLE
    # Just the exe, no packaging.
    .\tool\build.ps1 -ExeOnly

.EXAMPLE
    # Installer only.
    .\tool\build.ps1 -SkipMsix

.EXAMPLE
    .\tool\build.ps1 -Mode debug -ExeOnly -SkipPubGet
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'profile', 'debug')]
    [string]$Mode = 'release',

    [switch]$ExeOnly,

    [switch]$SkipMsix,

    [switch]$SkipInstaller,

    [string]$IsccPath,

    [switch]$Bump,

    [switch]$NoBump,

    [switch]$SkipPubGet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Run from the repository root whatever directory the caller is in.
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    function Assert-Tool([string]$Name, [string]$Hint) {
        if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
            throw "'$Name' is not on PATH. $Hint"
        }
    }

    # PowerShell 5.1's file cmdlets are not safe for a round-trip: reading
    # defaults to ANSI, so every non-ASCII character comes back mangled, and
    # writing as UTF8 prepends a BOM. Go through .NET instead. Its APIs resolve
    # relative paths against the process directory rather than PowerShell's, so
    # these take absolute paths.
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    function Read-TextFile([string]$Path) {
        return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    }

    function Write-TextFile([string]$Path, [string]$Text) {
        [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
    }

    # Patch + build number move together: the About window shows both, and a
    # build number that lags its version says nothing useful.
    function Get-NextVersion([string]$Version, [string]$Build) {
        $parts = $Version.Split('.')
        $parts[2] = [int]$parts[2] + 1
        return @{ Version = ($parts -join '.'); Build = [string]([int]$Build + 1) }
    }

    # Writes both `version:` and msix_config's `msix_version:`. They are
    # separate fields, and Windows refuses to upgrade a package whose MSIX
    # version did not rise.
    #
    # The line ending is matched by lookahead, never consumed: pubspec.yaml is
    # CRLF here and a replacement that ate the newline would collapse the blank
    # line after the field.
    function Set-PubspecVersion([string]$Text, [string]$Version, [string]$Build) {
        $Text = [regex]::Replace(
            $Text,
            '(?m)^version:[ \t]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[ \t]*(?=\r?$)',
            "version: $Version+$Build"
        )
        return [regex]::Replace(
            $Text,
            '(?m)^([ \t]+msix_version:[ \t]*)[0-9.]+[ \t]*(?=\r?$)',
            "`${1}$Version.$Build"
        )
    }

    # AppInfo's version/buildNumber defaults are what a defineless run shows —
    # `flutter run`, and any build that skips this script. Its TODO(version)
    # asks for them to track pubspec, so a bump that moved only pubspec would
    # leave every dev run reporting the previous release.
    function Set-AppInfoFallback([string]$Version, [string]$Build) {
        $path = Join-Path $repoRoot 'lib/core/constants/app_info.dart'
        if (-not (Test-Path $path)) {
            Write-Warning "$path not found; its version fallback still reads the old number."
            return
        }
        $text = Read-TextFile $path
        $text = [regex]::Replace(
            $text,
            "(?ms)('APP_VERSION',\s*defaultValue: ')[^']*(')",
            "`${1}$Version`${2}"
        )
        $text = [regex]::Replace(
            $text,
            "(?ms)('APP_BUILD_NUMBER',\s*defaultValue: ')[^']*(')",
            "`${1}$Build`${2}"
        )
        Write-TextFile $path $text
    }

    Assert-Tool 'flutter' 'Install the Flutter SDK and add its bin folder.'
    Assert-Tool 'git' 'Install Git, or build without APP_COMMIT.'

    # ---- version + build number, straight from pubspec --------------------
    $pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
    $pubspec = Read-TextFile $pubspecPath
    if ($pubspec -notmatch '(?m)^version:[ \t]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)[ \t]*\r?$') {
        throw 'Could not read "version: x.y.z+n" from pubspec.yaml.'
    }
    $appVersion = $Matches[1]
    $buildNumber = $Matches[2]

    # ---- optional version bump --------------------------------------------
    if ($Bump -and $NoBump) { throw 'Pass -Bump or -NoBump, not both.' }

    $doBump = $Bump
    if (-not $Bump -and -not $NoBump) {
        # Only ask a human. An unattended run must not decide to cut a release.
        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            $next = Get-NextVersion $appVersion $buildNumber
            $answer = Read-Host "Current version is $appVersion+$buildNumber. Bump to $($next.Version)+$($next.Build)? [y/N]"
            $doBump = $answer -match '^(y|yes)$'
        }
    }

    if ($doBump) {
        $next = Get-NextVersion $appVersion $buildNumber
        $pubspec = Set-PubspecVersion $pubspec $next.Version $next.Build
        Write-TextFile $pubspecPath $pubspec
        Set-AppInfoFallback $next.Version $next.Build
        $appVersion = $next.Version
        $buildNumber = $next.Build
        Write-Host "Bumped to $appVersion+$buildNumber (pubspec.yaml, msix_version, app_info.dart)." -ForegroundColor Green
    }

    # ---- toolchain, from Flutter's own machine-readable output ------------
    Write-Host 'Reading toolchain versions...' -ForegroundColor DarkGray
    $machine = flutter --version --machine | ConvertFrom-Json
    $flutterVersion = $machine.frameworkVersion
    $dartVersion = $machine.dartSdkVersion
    $channel = $machine.channel

    # dartSdkVersion is sometimes "3.12.2 (build 3.12.2 abcdef)"; keep the
    # leading semver so the About window shows one number.
    if ($dartVersion -match '^([0-9]+\.[0-9]+\.[0-9]+\S*)') {
        $dartVersion = $Matches[1]
    }

    # ---- source commit ----------------------------------------------------
    $commit = (git rev-parse --short HEAD).Trim()
    # A build made from uncommitted work is not that commit. Say so, so a bug
    # report from this binary cannot be traced back to the wrong source.
    if ((git status --porcelain | Measure-Object).Count -gt 0) {
        $commit = "$commit-dirty"
        Write-Warning 'Working tree is dirty; commit tagged "-dirty".'
    }

    Write-Host ''
    Write-Host "  Version   $appVersion (build $buildNumber)"
    Write-Host "  Channel   $channel"
    Write-Host "  Flutter   $flutterVersion"
    Write-Host "  Dart      $dartVersion"
    Write-Host "  Commit    $commit"
    Write-Host ''

    if (-not $SkipPubGet) {
        Write-Host 'flutter pub get' -ForegroundColor DarkGray
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    }

    $defines = @(
        "--dart-define=APP_VERSION=$appVersion",
        "--dart-define=APP_BUILD_NUMBER=$buildNumber",
        "--dart-define=APP_CHANNEL=$channel",
        "--dart-define=APP_FLUTTER_VERSION=$flutterVersion",
        "--dart-define=APP_DART_VERSION=$dartVersion",
        "--dart-define=APP_COMMIT=$commit"
    )

    if (-not $ExeOnly -and $Mode -ne 'release') {
        Write-Warning "Packaging a $Mode build; pass -ExeOnly if you only wanted the exe."
    }

    # By far the most common failure: the app is still running and MSBuild
    # cannot overwrite a locked exe.
    $lockHint = 'If the error mentions LNK1168 or "cannot open ... for writing", close the running app and try again.'

    $folder = (Get-Culture).TextInfo.ToTitleCase($Mode)
    $outDir = Join-Path $repoRoot "build\windows\x64\runner\$folder"

    # ---- one build, whoever asks for it ------------------------------------
    $wantMsix = -not $ExeOnly -and -not $SkipMsix
    if ($wantMsix) {
        # msix:create runs its own `flutter build windows`. Hand it the mode and
        # the defines so the build it runs is the one that ships, and no second
        # build is needed for the installer either.
        $buildArgs = (@("--$Mode") + $defines) -join ' '
        Write-Host "dart run msix:create --windows-build-args `"$buildArgs`"" -ForegroundColor DarkGray
        dart run msix:create --windows-build-args "$buildArgs"
        if ($LASTEXITCODE -ne 0) { throw "msix:create failed. $lockHint" }
        Write-Host 'Packaged MSIX.' -ForegroundColor Green

        # msix_version is its own field and does not follow `version:`. If they
        # drift apart, Windows refuses to upgrade an installed package.
        if ($pubspec -match '(?ms)msix_config:.*?^[ \t]+msix_version:[ \t]*([0-9.]+)[ \t]*\r?$') {
            $msixVersion = $Matches[1]
            $expected = "$appVersion.$buildNumber"
            if ($msixVersion -ne $expected) {
                Write-Warning "msix_version is $msixVersion but pubspec version is $expected. Update msix_config.msix_version before publishing."
            }
        }
    }
    else {
        Write-Host "flutter build windows --$Mode" -ForegroundColor DarkGray
        flutter build windows "--$Mode" @defines
        if ($LASTEXITCODE -ne 0) { throw "Build failed. $lockHint" }
        Write-Host "Built $outDir\flutra.exe" -ForegroundColor Green
    }

    # ---- Inno Setup installer, over whatever was just built ----------------
    if (-not $ExeOnly -and -not $SkipInstaller) {
        if (-not $IsccPath) {
            $candidates = @(
                # Braces are required: PowerShell would otherwise read the
                # variable as $env:ProgramFiles followed by a literal "(x86)".
                "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
                "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
            )
            $IsccPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $IsccPath) {
                $onPath = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
                if ($onPath) { $IsccPath = $onPath.Source }
            }
        }
        if (-not $IsccPath) {
            throw 'Inno Setup not found. Install it, pass -IsccPath, or run with -SkipInstaller.'
        }

        $installerDir = Join-Path $repoRoot 'build\installer'
        $iss = Join-Path $PSScriptRoot 'installer.iss'

        Write-Host ''
        Write-Host "ISCC installer.iss" -ForegroundColor DarkGray
        # /Q keeps the compiler quiet; its errors still reach stderr.
        & $IsccPath /Q "/DMyAppVersion=$appVersion" "/DSourceDir=$outDir" "/DOutputDir=$installerDir" $iss
        if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }

        $setup = Join-Path $installerDir "Flutra-Setup-$appVersion.exe"
        Write-Host "Built $setup" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

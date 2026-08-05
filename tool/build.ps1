#Requires -Version 5.1
<#
.SYNOPSIS
    Builds Flutter SDK Manager for Windows with its build metadata baked in.

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
    Build the exe and stop, skipping the MSIX package.

    Packaging is the default because it is how this project ships. msix:create
    runs its own `flutter build windows` and inherits nothing from a build you
    ran beforehand, so a plain `dart run msix:create` would ship a binary whose
    About window reports "—" for everything. The defines are routed through
    msix's --windows-build-args instead, so only one build runs either way.

.PARAMETER SkipPubGet
    Skip `flutter pub get`. Useful for repeat builds.

.EXAMPLE
    # Release: builds and packages the MSIX in one pass.
    .\tool\build.ps1

.EXAMPLE
    # Just the exe, no packaging.
    .\tool\build.ps1 -ExeOnly

.EXAMPLE
    .\tool\build.ps1 -Mode debug -ExeOnly -SkipPubGet
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'profile', 'debug')]
    [string]$Mode = 'release',

    [switch]$ExeOnly,

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

    Assert-Tool 'flutter' 'Install the Flutter SDK and add its bin folder.'
    Assert-Tool 'git' 'Install Git, or build without APP_COMMIT.'

    # ---- version + build number, straight from pubspec --------------------
    $pubspec = Get-Content 'pubspec.yaml' -Raw
    if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
        throw 'Could not read "version: x.y.z+n" from pubspec.yaml.'
    }
    $appVersion = $Matches[1]
    $buildNumber = $Matches[2]

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

    if (-not $ExeOnly) {
        # msix:create runs its own `flutter build windows`. Hand it the mode and
        # the defines so the build it runs is the one that ships.
        $buildArgs = (@("--$Mode") + $defines) -join ' '
        Write-Host "dart run msix:create --windows-build-args `"$buildArgs`"" -ForegroundColor DarkGray
        dart run msix:create --windows-build-args "$buildArgs"
        if ($LASTEXITCODE -ne 0) { throw "msix:create failed. $lockHint" }

        Write-Host ''
        Write-Host 'Packaged MSIX.' -ForegroundColor Green

        # msix_version is its own field and does not follow `version:`. If they
        # drift apart, Windows refuses to upgrade an installed package.
        if ($pubspec -match '(?m)^\s*msix_version:\s*([0-9.]+)\s*$') {
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

        $folder = (Get-Culture).TextInfo.ToTitleCase($Mode)
        $exe = Join-Path $repoRoot "build\windows\x64\runner\$folder\android_sdk_manager.exe"
        Write-Host ''
        Write-Host "Built $exe" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

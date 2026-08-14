#!/usr/bin/env bash
#
# Writes one version into every place that carries it.
#
#   ./tool/set_version.sh 1.0.7 7
#
# The POSIX sibling of `Set-PubspecVersion` / `Set-AppInfoFallback` in
# build.ps1 — CI runs on Linux and macOS too, and re-deriving the same three
# substitutions in a workflow file would put a fourth copy of them somewhere
# nobody looks. If the set of places a version lives changes, it changes in
# both this and build.ps1.
#
# The three places, and why each one:
#   pubspec.yaml `version:`        what Flutter builds and what build.ps1 reads
#   pubspec.yaml `msix_version:`   a separate field, and Windows refuses to
#                                  upgrade a package whose MSIX version did not
#                                  rise
#   app_info.dart defaults         what a build with no --dart-define reports,
#                                  which is every `flutter run`
#
# perl rather than sed: pubspec.yaml is CRLF in this repo, and the line ending
# is matched by lookahead so a replacement never eats the newline.

set -euo pipefail

VERSION="${1:?usage: set_version.sh <x.y.z> <build>}"
BUILD="${2:?usage: set_version.sh <x.y.z> <build>}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Not a version: '$VERSION' (want x.y.z)" >&2
  exit 1
fi
if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "Not a build number: '$BUILD'" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pubspec="$root/pubspec.yaml"
app_info="$root/lib/core/constants/app_info.dart"

perl -0pi -e \
  "s/^version:[ \\t]*[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+[ \\t]*(?=\\r?\$)/version: $VERSION+$BUILD/m" \
  "$pubspec"

perl -0pi -e \
  "s/^([ \\t]+msix_version:[ \\t]*)[0-9.]+[ \\t]*(?=\\r?\$)/\${1}$VERSION.$BUILD/m" \
  "$pubspec"

if [[ -f "$app_info" ]]; then
  perl -0pi -e \
    "s/('APP_VERSION',\\s*defaultValue: ')[^']*(')/\${1}$VERSION\${2}/s" \
    "$app_info"
  perl -0pi -e \
    "s/('APP_BUILD_NUMBER',\\s*defaultValue: ')[^']*(')/\${1}$BUILD\${2}/s" \
    "$app_info"
else
  echo "warning: $app_info not found; its version fallback still reads the old number." >&2
fi

# Proving it landed is cheap, and a silent no-op here would ship the previous
# version under this tag's name.
if ! grep -q "^version: $VERSION+$BUILD" "$pubspec"; then
  echo "Failed to write 'version: $VERSION+$BUILD' into $pubspec" >&2
  exit 1
fi

echo "version: $VERSION+$BUILD"

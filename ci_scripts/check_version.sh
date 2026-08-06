#!/bin/bash

set -euo pipefail

# Verifies that release-please is actually able to bump the app version, and
# that the bumped value is what Xcode ends up building with.
#
# release-please's `generic` updater only rewrites lines carrying an
# `x-release-please-version` marker. Pointing it at a file with no marker
# silently does nothing, which is how MARKETING_VERSION sat at 0.3.0 for four
# releases. The version lives in Version.xcconfig rather than project.pbxproj
# because Xcode regenerates the latter from its object graph when it saves and
# drops hand-written comments along with it.
#
# Runs locally via `just check-version` or in CI.

cd "$(dirname "${BASH_SOURCE[0]}")/.."

XCCONFIG="Version.xcconfig"
PBXPROJ="SSHadow.xcodeproj/project.pbxproj"
CONFIG="release-please-config.json"
MANIFEST=".release-please-manifest.json"
MARKER="x-release-please-version"

# Targets that ship inside the DMG. The appex is rejected at install time if
# its version disagrees with the host app's, so check both resolve the same.
TARGETS=(SSHadow Extension)

fail() {
  echo "error: $*" >&2
  exit 1
}

# The marker only matters if release-please is pointed at the file to begin with.
jq -e --arg path "$XCCONFIG" \
  'any(."extra-files"[]; .path == $path and .type == "generic")' \
  "$CONFIG" >/dev/null ||
  fail "$CONFIG does not list $XCCONFIG as a generic extra-file, so the version is never bumped"

# A build setting in project.pbxproj outranks the same setting in a base
# xcconfig, so one reappearing here would silently pin the version forever.
if grep -q 'MARKETING_VERSION' "$PBXPROJ"; then
  fail "$PBXPROJ sets MARKETING_VERSION, which overrides $XCCONFIG. Remove it:
$(grep -n 'MARKETING_VERSION' "$PBXPROJ")"
fi

version_lines="$(grep -n 'MARKETING_VERSION' "$XCCONFIG" || true)"
[[ "$(grep -c . <<<"$version_lines")" -eq 1 ]] ||
  fail "expected exactly one MARKETING_VERSION assignment in $XCCONFIG, found:
${version_lines:-<none>}"

grep -q "$MARKER" <<<"$version_lines" ||
  fail "MARKETING_VERSION in $XCCONFIG has no '$MARKER' marker, so release-please will not bump it:
$version_lines

Append '// $MARKER' to that line."

expected="$(jq -r '."."' "$MANIFEST")"

declared="$(sed -E 's/^[^=]*= *([^ /]+).*/\1/' <<<"${version_lines#*:}")"
[[ "$declared" == "$expected" ]] ||
  fail "$XCCONFIG declares MARKETING_VERSION $declared but $MANIFEST says $expected; they drift apart when a release lands without updating $XCCONFIG"

# The checks above are structural. This is the one that proves the wiring
# actually holds: a config missing its baseConfigurationReference would pass
# everything so far and still build with the wrong version.
for target in "${TARGETS[@]}"; do
  resolved="$(xcodebuild -project SSHadow.xcodeproj -target "$target" -configuration Release -showBuildSettings 2>/dev/null |
    awk -F' = ' '/^ *MARKETING_VERSION = /{print $2; exit}')"
  [[ -n "$resolved" ]] ||
    fail "target $target resolves no MARKETING_VERSION at all; is $XCCONFIG wired up as its baseConfigurationReference?"
  [[ "$resolved" == "$expected" ]] ||
    fail "target $target builds as $resolved but $MANIFEST says $expected; $XCCONFIG is probably not its base configuration"
done

echo "✅ MARKETING_VERSION is $expected — annotated for release-please, in sync with $MANIFEST, and resolved by ${TARGETS[*]}"

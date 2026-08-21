#!/bin/bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

XCCONFIG="Config.xcconfig"
PBXPROJ="SSHadow.xcodeproj/project.pbxproj"
CONFIG="release-please-config.json"
MANIFEST=".release-please-manifest.json"
MARKER="x-release-please-version"

TARGETS=(SSHadow Extension)

fail() {
  echo "error: $*" >&2
  exit 1
}

jq -e --arg path "$XCCONFIG" \
  'any(."extra-files"[]; .path == $path and .type == "generic")' \
  "$CONFIG" >/dev/null ||
  fail "$CONFIG does not list $XCCONFIG as a generic extra-file, so the version is never bumped"

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

for target in "${TARGETS[@]}"; do
  resolved="$(xcodebuild -project SSHadow.xcodeproj -target "$target" -configuration Release -showBuildSettings 2>/dev/null |
    awk -F' = ' '/^ *MARKETING_VERSION = /{print $2; exit}')"
  [[ -n "$resolved" ]] ||
    fail "target $target resolves no MARKETING_VERSION at all; is $XCCONFIG wired up as its baseConfigurationReference?"
  [[ "$resolved" == "$expected" ]] ||
    fail "target $target builds as $resolved but $MANIFEST says $expected; $XCCONFIG is probably not its base configuration"
done

echo "✅ MARKETING_VERSION is $expected — annotated for release-please, in sync with $MANIFEST, and resolved by ${TARGETS[*]}"

if grep -q 'MACOSX_DEPLOYMENT_TARGET' "$PBXPROJ"; then
  fail "$PBXPROJ sets MACOSX_DEPLOYMENT_TARGET, which overrides $XCCONFIG. Remove it:
$(grep -n 'MACOSX_DEPLOYMENT_TARGET' "$PBXPROJ")"
fi

deployment_lines="$(grep -n 'MACOSX_DEPLOYMENT_TARGET' "$XCCONFIG" || true)"
[[ "$(grep -c . <<<"$deployment_lines")" -eq 1 ]] ||
  fail "expected exactly one MACOSX_DEPLOYMENT_TARGET assignment in $XCCONFIG, found:
${deployment_lines:-<none>}"

deployment="$(sed -E 's/^[^=]*= *([^ /]+).*/\1/' <<<"${deployment_lines#*:}")"

for target in "${TARGETS[@]}"; do
  resolved="$(xcodebuild -project SSHadow.xcodeproj -target "$target" -configuration Release -showBuildSettings 2>/dev/null |
    awk -F' = ' '/^ *MACOSX_DEPLOYMENT_TARGET = /{print $2; exit}')"
  [[ -n "$resolved" ]] ||
    fail "target $target resolves no MACOSX_DEPLOYMENT_TARGET at all; is $XCCONFIG wired up as its baseConfigurationReference?"
  [[ "$resolved" == "$deployment" ]] ||
    fail "target $target builds as $resolved but $XCCONFIG declares $deployment; $XCCONFIG is probably not its base configuration"
done

echo "✅ MACOSX_DEPLOYMENT_TARGET is $deployment — set only in $XCCONFIG and resolved by ${TARGETS[*]}"

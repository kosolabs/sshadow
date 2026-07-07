#!/bin/zsh

set -e

cd "${CI_PRIMARY_REPOSITORY_PATH:-${0:a:h}/..}"

git fetch --unshallow 2>/dev/null || true

BUILD_NUMBER="$(git rev-list --count HEAD)"
PBXPROJ="SSHadow.xcodeproj/project.pbxproj"

sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PBXPROJ"

echo "✅ Set build number to $BUILD_NUMBER"

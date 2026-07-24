set dotenv-load

start-test-server: stop-test-server
    ./ci_scripts/start_test_server.sh

stop-test-server:
    ./ci_scripts/stop_test_server.sh

test: start-test-server
    xcodebuild test -scheme SSHadow -testPlan UnitTests -destination 'platform=macOS' -retry-tests-on-failure -test-iterations 3

log:
    log stream --predicate 'subsystem beginswith "com.kosolabs.SSHadow"' --style ndjson --level debug | jq -R -r --unbuffered -f logfilter.jq

unregister:
    #!/bin/bash
    BUNDLE=com.kosolabs.SSHadow
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister

    pkill -f 'SSHadow.app/Contents/MacOS/SSHadow' || true
    pkill -f 'SSHadow.app/Contents/PlugIns/Extension.appex/Contents/MacOS/Extension' || true

    $LSREGISTER -dump \
        | awk -F'path: *' '/^[[:space:]]*path:.*SSHadow\.app/{p=$2; sub(/ \([0-9a-fx]+\)$/,"",p); print p}' \
        | sort -u \
        | while IFS= read -r app; do
            [ -n "$app" ] || continue
            $LSREGISTER -u "$app" 2>/dev/null || true
            echo "  Unregistered: $app"
        done

dmg:
    ./ci_scripts/dmg.sh

# Print the current marketing version.
version:
    @xcodebuild -showBuildSettings -scheme SSHadow -configuration Release 2>/dev/null | awk -F' = ' '/MARKETING_VERSION/ {print $2}'

# Set the marketing version for all targets. Run with Xcode closed.
set-version version:
    #!/bin/bash
    set -euo pipefail
    if [[ ! "{{version}}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "error: version must look like 1.2, got '{{version}}'" >&2
        exit 1
    fi
    sed -i '' 's/MARKETING_VERSION = .*;/MARKETING_VERSION = {{version}};/' SSHadow.xcodeproj/project.pbxproj
    echo "MARKETING_VERSION set to {{version}}"

# Bump the minor version on a fresh branch and push it. Run with Xcode closed.
bump:
    #!/bin/bash
    set -euo pipefail

    if [[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]]; then
        echo "error: must be on main to bump the version" >&2
        exit 1
    fi

    if [[ -n "$(git status --porcelain)" ]]; then
        echo "error: main is not clean, commit or stash your changes first" >&2
        exit 1
    fi

    git fetch origin main
    if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
        echo "error: local main is not up to date with origin/main" >&2
        exit 1
    fi

    current="$(just version)"
    IFS='.' read -r major minor <<< "$current"
    new_version="${major}.$((minor + 1))"

    git checkout -b "bump-version-${new_version}"
    just set-version "${new_version}"
    git add SSHadow.xcodeproj/project.pbxproj
    git commit -m "chore: bump marketing version to ${new_version}"
    git push -u origin "bump-version-${new_version}"

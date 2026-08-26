set dotenv-load

start-test-server:
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

# Verify release-please can still bump the marketing version.
check-version:
    ./ci_scripts/check_version.sh

set dotenv-load

start-test-server:
    ./ci_scripts/start_test_server.sh

stop-test-server:
    ./ci_scripts/stop_test_server.sh

test: start-test-server
    xcodebuild test -scheme SSHadow -testPlan UnitTests -destination 'platform=macOS'

build:
    xcodebuild build -scheme SSHadow -configuration Debug -destination 'platform=macOS' -quiet

[positional-arguments]
e2e *ARGS: build start-test-server
    uv run --directory e2e pytest -v "$@"

# Walk through a manual test of the whole app.
manual: build start-test-server
    uv run --directory e2e python manual.py

log: (_log-stream 'subsystem beginswith "com.kosolabs.SSHadow"')

full-log: (_log-stream 'subsystem == "com.apple.FileProvider" OR subsystem beginswith "com.kosolabs.SSHadow"')

_log-stream $PREDICATE:
    #!/bin/bash
    mkdir -p logs
    LOGFILE="logs/sshadow-$(date +%Y%m%d-%H%M%S).log"
    echo "Logging to $LOGFILE"
    trap 'echo; echo "Logged to $LOGFILE"' EXIT
    log stream --predicate "$PREDICATE" --style ndjson --level debug \
        | tee "$LOGFILE" \
        | jq -R -r --unbuffered -f logfilter.jq

lsregister := "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister"

# List the copies of SSHadow registered with LaunchServices and PlugInKit.
registered:
    #!/bin/bash
    echo "LaunchServices:"
    {{just_executable()}} _registered-apps | while IFS= read -r app; do
        [ -e "$app" ] && echo "  $app" || echo "  $app (missing)"
    done

    echo "PlugInKit:"
    pluginkit -mAv -i com.kosolabs.SSHadow.Extension \
        | awk -F'\t' 'NF >= 4 {print "  " $4 " (" $3 ")"}'

unregister:
    #!/bin/bash
    pkill -f 'SSHadow.app/Contents/MacOS/SSHadow' || true
    pkill -f 'SSHadow.app/Contents/PlugIns/Extension.appex/Contents/MacOS/Extension' || true

    {{just_executable()}} _registered-apps | while IFS= read -r app; do
        pluginkit -r "$app/Contents/PlugIns/Extension.appex" 2>/dev/null || true
        {{lsregister}} -u "$app" 2>/dev/null || true
        echo "  Unregistered: $app"
    done

_registered-apps:
    @{{lsregister}} -dump \
        | awk -F'path: *' '/^[[:space:]]*path:/{p=$2; sub(/ \([0-9a-fx]+\)$/,"",p); if (p ~ /\/SSHadow\.app$/) print p}' \
        | sort -u

dmg:
    ./ci_scripts/dmg.sh

# Print the current marketing version.
version:
    @xcodebuild -showBuildSettings -scheme SSHadow -configuration Release 2>/dev/null | awk -F' = ' '/MARKETING_VERSION/ {print $2}'

# Verify release-please can still bump the marketing version.
check-version:
    ./ci_scripts/check_version.sh

set dotenv-load

start-test-server: stop-test-server
    ./ci_scripts/start_test_server.sh

stop-test-server:
    ./ci_scripts/stop_test_server.sh

test: start-test-server
    xcodebuild test -scheme SSHadow -testPlan UnitTests -destination 'platform=macOS'

log:
    log stream --predicate 'subsystem beginswith "com.kosolabs.SSHadow"' --style ndjson --level debug | jq -R -r --unbuffered -f logfilter.jq

archive:
    xcodebuild archive -scheme SSHadow -destination 'generic/platform=macOS' -archivePath build/SSHadow.xcarchive

notarize: archive
    CI_XCODEBUILD_ACTION=archive CI_ARCHIVE_PATH=build/SSHadow.xcarchive CI_PRODUCT=SSHadow CI_ARTIFACTS_DIR=artifacts ./ci_scripts/notarize.sh

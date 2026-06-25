start-test-server: stop-test-server
    ./ci_scripts/ci_pre_xcodebuild.sh

stop-test-server:
    ./ci_scripts/ci_post_xcodebuild.sh

test: start-test-server
    xcodebuild test -scheme SSHadow -testPlan UnitTests -destination 'platform=macOS'

log:
    log stream --predicate 'subsystem beginswith "com.kosolabs.SSHadow"' --style ndjson --level debug | jq -R -r --unbuffered -f logfilter.jq

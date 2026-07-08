set dotenv-load

start-test-server: stop-test-server
    ./ci_scripts/start_test_server.sh

stop-test-server:
    ./ci_scripts/stop_test_server.sh

test: start-test-server
    xcodebuild test -scheme SSHadow -testPlan UnitTests -destination 'platform=macOS'

log:
    log stream --predicate 'subsystem beginswith "com.kosolabs.SSHadow"' --style ndjson --level debug | jq -R -r --unbuffered -f logfilter.jq

dmg:
    ./ci_scripts/dmg.sh

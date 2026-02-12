start-test-server: stop-test-server
    ./ci_scripts/ci_pre_xcodebuild.sh

stop-test-server:
    ./ci_scripts/ci_post_xcodebuild.sh

test: start-test-server
    xcodebuild test -scheme SSHadow -destination 'platform=macOS'

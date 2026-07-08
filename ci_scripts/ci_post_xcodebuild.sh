#!/bin/zsh

set -e

"${0:a:h}/stop_test_server.sh"
"${0:a:h}/notarize.sh"

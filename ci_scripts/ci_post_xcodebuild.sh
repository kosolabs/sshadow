#!/bin/zsh

set -e

SERVER_DIR="${0:a:h}/test_server"
PID_FILE="$SERVER_DIR/sshd.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    kill $PID
    echo "✅ SSH Server with PID $PID stopped"
fi

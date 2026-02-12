#!/bin/zsh

set -e

PORT="${PORT:-2248}"
SERVER_DIR="${0:a:h}/test_server"
CONFIG_FILE="$SERVER_DIR/sshd_config"
HOST_KEY="$SERVER_DIR/host_key_ed25519"

chmod 600 "$HOST_KEY"
cp "$SERVER_DIR/id_ed25519" /tmp/id_ed25519

/usr/sbin/sshd \
    -f "$SERVER_DIR/sshd_config" \
    -E "$SERVER_DIR/sshd.log" \
    -h "$HOST_KEY" \
    -p "$PORT" \
    -o "PidFile $SERVER_DIR/sshd.pid" \
    -o "AuthorizedKeysFile $SERVER_DIR/id_ed25519.pub" \
    -o "Subsystem sftp internal-sftp -d $SERVER_DIR/mount" \
    -o "ForceCommand internal-sftp -d $SERVER_DIR/mount"

retries=50
while [[ ! -f "$SERVER_DIR/sshd.pid" ]]; do
    if (( retries-- == 0 )); then
        echo "❌ Failed to start SSH server: PID file not found after waiting."
        cat "$SERVER_DIR/sshd.log"
        exit 1
    fi
    sleep 0.1
done

PID=$(cat "$SERVER_DIR/sshd.pid")

echo "✅ SSH Server started on port $PORT with PID $PID"

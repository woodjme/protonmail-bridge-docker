#!/bin/bash
set -e

INIT_MARKER="/root/.initialized"

# Clean stale GPG sockets from previous runs
rm -f /root/.gnupg/S.gpg-agent* 2>/dev/null || true

# Auto-init GPG/pass on first run
if [ ! -f "$INIT_MARKER" ]; then
    echo "First run — initializing GPG keyring and pass store..."
    gpg --generate-key --batch /protonmail/gpgparams
    pass init pass-key
    touch "$INIT_MARKER"
fi

# Port forwarding (bridge listens on 1025/1143, expose on 25/143)
socat TCP-LISTEN:25,fork TCP:127.0.0.1:1025 &
socat TCP-LISTEN:143,fork TCP:127.0.0.1:1143 &

# Keep stdin open so bridge CLI doesn't exit on EOF
rm -f /tmp/faketty
mkfifo /tmp/faketty
sleep infinity > /tmp/faketty &

# Clean exit on SIGTERM (k8s pod termination)
trap 'kill $(cat /tmp/bridge.pid) 2>/dev/null; exit 0' SIGTERM SIGINT

# Restart loop — survives pkill so users can exec in and run bridge-cli
while true; do
    /protonmail/proton-bridge --cli < /tmp/faketty &
    echo $! > /tmp/bridge.pid
    wait $! || true
    echo "Bridge exited, restarting in 2s..."
    sleep 2
done

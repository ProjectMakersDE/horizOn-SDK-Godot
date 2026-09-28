#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --headless --editor --path . --quit

ready_file="$(mktemp)"
MOCK_SERVER_READY_FILE="$ready_file" python3 tests/mock_leaderboard_server.py &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$ready_file"' EXIT

# Start Godot only after the mock server listens, otherwise the single request races the bind.
for _ in $(seq 1 100); do
	if [ -s "$ready_file" ]; then
		break
	fi
	if ! kill -0 "$server_pid" 2>/dev/null; then
		echo "mock server exited before it was ready" >&2
		exit 1
	fi
	sleep 0.1
done
if [ ! -s "$ready_file" ]; then
	echo "mock server did not become ready within 10 seconds" >&2
	exit 1
fi

"$GODOT_BIN" --headless --path . --script tests/leaderboard_transport_test.gd
wait "$server_pid"
trap - EXIT
rm -f "$ready_file"

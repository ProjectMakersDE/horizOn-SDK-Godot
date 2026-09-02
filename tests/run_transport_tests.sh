#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
python3 tests/mock_leaderboard_server.py &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

"$GODOT_BIN" --headless --path . --script tests/leaderboard_transport_test.gd
wait "$server_pid"
trap - EXIT

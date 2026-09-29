#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --headless --editor --path . --quit

# Runs one Godot contract script against its mock server.
# $1: mock server script, $2: Godot test script
run_contract() {
	local mock_server="$1"
	local test_script="$2"
	# Globals on purpose: the EXIT trap must still see them if the script aborts.
	ready_file="$(mktemp)"
	MOCK_SERVER_READY_FILE="$ready_file" python3 "$mock_server" &
	server_pid=$!
	trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$ready_file"' EXIT

	# Start Godot only after the mock server listens, otherwise the single request races the bind.
	for _ in $(seq 1 100); do
		if [ -s "$ready_file" ]; then
			break
		fi
		if ! kill -0 "$server_pid" 2>/dev/null; then
			echo "mock server $mock_server exited before it was ready" >&2
			exit 1
		fi
		sleep 0.1
	done
	if [ ! -s "$ready_file" ]; then
		echo "mock server $mock_server did not become ready within 10 seconds" >&2
		exit 1
	fi

	"$GODOT_BIN" --headless --path . --script "$test_script"
	wait "$server_pid"
	trap - EXIT
	rm -f "$ready_file"
}

run_contract tests/mock_leaderboard_server.py tests/leaderboard_transport_test.gd
run_contract tests/mock_gift_code_server.py tests/gift_code_transport_test.gd
run_contract tests/mock_player_profile_server.py tests/player_profile_transport_test.gd

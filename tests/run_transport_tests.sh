#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
# A separate project name isolates user:// caches from the developer's SDK project.
source_dir="$(pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/horizon-godot-tests.XXXXXX")"
test_name="$(basename "$test_dir")"
server_pid=""
ready_file=""
user_data_dir=""
cleanup() {
	if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
	if [ -n "$ready_file" ]; then rm -f "$ready_file"; fi
	if [[ "$user_data_dir" == */"$test_name" ]]; then rm -rf "$user_data_dir"; fi
	rm -rf "$test_dir"
}
trap cleanup EXIT
cp -R "$source_dir/addons" "$source_dir/tests" "$test_dir/"
printf 'config_version=5\n[application]\nconfig/name="%s"\n' "$test_name" > "$test_dir/project.godot"
printf 'extends SceneTree\nfunc _initialize():\n\tprint(OS.get_user_data_dir())\n\tquit()\n' > "$test_dir/user_data_dir.gd"
user_data_dir="$("$GODOT_BIN" --headless --path "$test_dir" --script "$test_dir/user_data_dir.gd" | tail -n 1)"
cd "$test_dir"
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
	server_pid=""
	rm -f "$ready_file"
	ready_file=""
}

run_contract tests/mock_cloud_save_server.py tests/cloud_save_transport_test.gd
run_contract tests/mock_leaderboard_server.py tests/leaderboard_transport_test.gd
run_contract tests/mock_gift_code_server.py tests/gift_code_transport_test.gd
run_contract tests/mock_player_profile_server.py tests/player_profile_transport_test.gd
run_contract tests/mock_validated_actions_server.py tests/validated_actions_transport_test.gd
run_contract tests/mock_auth_server.py tests/auth_transport_test.gd

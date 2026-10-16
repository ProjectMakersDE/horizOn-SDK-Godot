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
"$GODOT_BIN" --headless --path . --check-only --script addons/horizon_sdk/examples/features/statistics_example.gd
"$GODOT_BIN" --headless --path . --check-only --script addons/horizon_sdk/examples/features/player_values_example.gd
"$GODOT_BIN" --headless --path . --check-only --script addons/horizon_sdk/examples/features/inbox_example.gd
"$GODOT_BIN" --headless --path . --check-only --script addons/horizon_sdk/examples/features/gift_codes_example.gd
"$GODOT_BIN" --headless --path . --check-only --script addons/horizon_sdk/examples/features/achievements_example.gd
"$GODOT_BIN" --headless --path . --check-only --script addons/horizon_sdk/examples/features/friends_example.gd
"$GODOT_BIN" --headless --path . --check-only --script addons/horizon_sdk/examples/features/groups_example.gd
"$GODOT_BIN" --headless --path . --script tests/pending_purchase_test.gd
"$GODOT_BIN" --headless --path . --script tests/pending_statistics_test.gd
"$GODOT_BIN" --headless --path . --script tests/pending_gift_code_test.gd
"$GODOT_BIN" --headless --path . --script tests/pending_inbox_claim_test.gd
"$GODOT_BIN" --headless --path . --script tests/auth_identity_policy_test.gd
"$GODOT_BIN" --headless --path . --script tests/achievements_example_test.gd

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
run_contract tests/mock_gift_values_server.py tests/gift_values_transport_test.gd
run_contract tests/mock_signup_once_server.py tests/signup_once_transport_test.gd
run_contract tests/mock_rate_limit_server.py tests/rate_limit_transport_test.gd
run_contract tests/mock_player_profile_server.py tests/player_profile_transport_test.gd
run_contract tests/mock_player_values_server.py tests/player_values_transport_test.gd
run_contract tests/mock_validated_actions_server.py tests/validated_actions_transport_test.gd
run_contract tests/mock_auth_server.py tests/auth_transport_test.gd
run_contract tests/mock_statistics_server.py tests/statistics_transport_test.gd
run_contract tests/mock_inbox_server.py tests/inbox_transport_test.gd
run_contract tests/mock_achievements_server.py tests/achievements_transport_test.gd
run_contract tests/mock_friends_server.py tests/friends_transport_test.gd
run_contract tests/mock_groups_server.py tests/groups_transport_test.gd

"$GODOT_BIN" --headless --path . --script tests/inbox_policy_test.gd
"$GODOT_BIN" --headless --path . --script tests/achievements_policy_test.gd
"$GODOT_BIN" --headless --path . --script tests/friends_policy_test.gd
"$GODOT_BIN" --headless --path . --script tests/groups_policy_test.gd

"$GODOT_BIN" --headless --path . --script tests/realtime_policy_test.gd
if [ -n "${HORIZON_REALTIME_FIXTURE_URL:-}" ]; then
    "$GODOT_BIN" --headless --path . --script tests/realtime_transport_test.gd
fi

# The release workflow invokes this runner; keep public health in the same gate.
(cd "$source_dir" && GODOT_BIN="$GODOT_BIN" bash tests/run_health_tests.sh)

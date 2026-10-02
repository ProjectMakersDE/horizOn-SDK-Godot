#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
source_dir="$(pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/horizon-health-tests.XXXXXX")"
ready_file="$test_dir/health-fixture.json"
server_pid=""
cleanup() {
	if [ -n "$server_pid" ]; then
		kill "$server_pid" 2>/dev/null || true
		wait "$server_pid" 2>/dev/null || true
	fi
	rm -rf "$test_dir"
}
trap cleanup EXIT
cp -R "$source_dir/addons" "$source_dir/tests" "$test_dir/"
printf 'config_version=5\n[application]\nconfig/name="HorizonHealthFixture"\n' > "$test_dir/project.godot"
cd "$test_dir"
"$GODOT_BIN" --headless --editor --path . --quit >/dev/null
HEALTH_FIXTURE_READY_FILE="$ready_file" python3 tests/mock_health_server.py &
server_pid=$!
for _ in $(seq 1 100); do
	if [ -s "$ready_file" ]; then break; fi
	if ! kill -0 "$server_pid" 2>/dev/null; then
		echo "local health fixture exited before ready" >&2
		exit 1
	fi
	sleep 0.1
done
if [ ! -s "$ready_file" ]; then
	echo "local health fixture did not become ready" >&2
	exit 1
fi
HEALTH_FIXTURE_READY_FILE="$ready_file" "$GODOT_BIN" --headless --path . --script tests/health_transport_test.gd

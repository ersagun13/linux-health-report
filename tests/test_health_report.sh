#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
BASH_BIN=$(command -v bash)
PYTHON_BIN=$(command -v python3)
TEST_DIR=$(mktemp -d)
MOCK_BIN="$TEST_DIR/mock-bin"
NO_SYSTEMCTL_BIN="$TEST_DIR/no-systemctl-bin"
RUN_LOG="$TEST_DIR/calls.log"
mkdir -p "$MOCK_BIN" "$NO_SYSTEMCTL_BIN"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected output to contain: $2" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "expected output not to contain: $2" ;;
    *) ;;
  esac
}

assert_status() {
  [ "$RUN_STATUS" -eq "$1" ] || fail "expected exit $1, got $RUN_STATUS: $RUN_OUTPUT"
}

run_report() {
  local mock_path=$1
  shift
  : > "$RUN_LOG"
  if RUN_OUTPUT=$(PATH="$mock_path" MOCK_CALL_LOG="$RUN_LOG" \
    MOCK_FAIL_DF="${RUN_FAIL_DF:-0}" \
    MOCK_FAIL_FREE="${RUN_FAIL_FREE:-0}" \
    MOCK_FAIL_UPTIME="${RUN_FAIL_UPTIME:-0}" \
    MOCK_FAIL_SYSTEMCTL="${RUN_FAIL_SYSTEMCTL:-0}" \
    MOCK_BAD_UPTIME="${RUN_BAD_UPTIME:-0}" \
    "$BASH_BIN" "$PROJECT_DIR/health-report" "$@" 2>&1); then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
}

cat > "$MOCK_BIN/df" <<'MOCK'
#!/bin/sh
printf 'df' >> "$MOCK_CALL_LOG"
for arg in "$@"; do printf ' %s' "$arg" >> "$MOCK_CALL_LOG"; done
printf '\n' >> "$MOCK_CALL_LOG"
[ "${MOCK_FAIL_DF:-0}" = 1 ] && exit 4
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/root 1000000 250000 750000 25%% /\n'
MOCK

cat > "$MOCK_BIN/free" <<'MOCK'
#!/bin/sh
printf 'free' >> "$MOCK_CALL_LOG"
for arg in "$@"; do printf ' %s' "$arg" >> "$MOCK_CALL_LOG"; done
printf '\n' >> "$MOCK_CALL_LOG"
[ "${MOCK_FAIL_FREE:-0}" = 1 ] && exit 4
printf '               total used free shared buff/cache available\nMem:            4096 1024 512 128 2560 2800\nSwap:              0    0   0\n'
MOCK

cat > "$MOCK_BIN/uptime" <<'MOCK'
#!/bin/sh
printf 'uptime' >> "$MOCK_CALL_LOG"
for arg in "$@"; do printf ' %s' "$arg" >> "$MOCK_CALL_LOG"; done
printf '\n' >> "$MOCK_CALL_LOG"
[ "${MOCK_FAIL_UPTIME:-0}" = 1 ] && exit 4
[ "${MOCK_BAD_UPTIME:-0}" = 1 ] && { printf 'load average: 1..2, 0.08, 0.04\n'; exit 0; }
printf ' 22:37:10 up 1 day, 2 users, load average: 0.12, 0.08, 0.04\n'
MOCK

cat > "$MOCK_BIN/systemctl" <<'MOCK'
#!/bin/sh
printf 'systemctl' >> "$MOCK_CALL_LOG"
for arg in "$@"; do printf ' %s' "$arg" >> "$MOCK_CALL_LOG"; done
printf '\n' >> "$MOCK_CALL_LOG"
[ "$1" = is-active ] || exit 64
[ "${MOCK_FAIL_SYSTEMCTL:-0}" = 1 ] && exit 4
case "$2" in
  nginx) printf 'active\n'; exit 0 ;;
  cron) printf 'inactive\n'; exit 3 ;;
  *) printf 'unknown\n'; exit 4 ;;
esac
MOCK

cat > "$MOCK_BIN/sudo" <<'MOCK'
#!/bin/sh
printf 'sudo was invoked\n' >> "$MOCK_CALL_LOG"
exit 99
MOCK

chmod +x "$MOCK_BIN/df" "$MOCK_BIN/free" "$MOCK_BIN/uptime" "$MOCK_BIN/systemctl" "$MOCK_BIN/sudo"
cp "$MOCK_BIN/df" "$MOCK_BIN/free" "$MOCK_BIN/uptime" "$MOCK_BIN/sudo" "$NO_SYSTEMCTL_BIN/"

run_report "$MOCK_BIN" --service nginx --service cron
assert_status 0
assert_contains "$RUN_OUTPUT" 'Root disk: 25% used'
assert_contains "$RUN_OUTPUT" '250000 KiB used of 1000000 KiB'
assert_contains "$RUN_OUTPUT" '750000 KiB available'
assert_contains "$RUN_OUTPUT" 'Memory: 1024 MiB used of 4096 MiB'
assert_contains "$RUN_OUTPUT" '2800 MiB available'
assert_contains "$RUN_OUTPUT" 'Load average: 0.12, 0.08, 0.04'
assert_contains "$RUN_OUTPUT" 'nginx: active'
assert_contains "$RUN_OUTPUT" 'cron: inactive'
assert_not_contains "$RUN_OUTPUT" 'sudo'
[ "$(cat "$RUN_LOG")" = "$(printf 'df -P -k /\nfree -m\nuptime\nsystemctl is-active nginx\nsystemctl is-active cron')" ] || fail "unexpected command calls: $(cat "$RUN_LOG")"

run_report "$NO_SYSTEMCTL_BIN" --service nginx
assert_status 0
assert_contains "$RUN_OUTPUT" 'nginx: unavailable'
[ "$(cat "$RUN_LOG")" = "$(printf 'df -P -k /\nfree -m\nuptime')" ] || fail "systemctl should be optional: $(cat "$RUN_LOG")"

run_report "$MOCK_BIN"
assert_status 0
assert_contains "$RUN_OUTPUT" 'Services: none requested'
[ "$(cat "$RUN_LOG")" = "$(printf 'df -P -k /\nfree -m\nuptime')" ] || fail "services were queried without --service: $(cat "$RUN_LOG")"

JSON_FILE="$TEST_DIR/report.json"
run_report "$NO_SYSTEMCTL_BIN" --json
assert_status 0
printf '%s\n' "$RUN_OUTPUT" > "$JSON_FILE"
"$PYTHON_BIN" - "$JSON_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as report_file:
    report = json.load(report_file)
assert report["disk"]["status"] == "available"
assert report["disk"]["used_percent"] == 25
assert report["memory"]["available_mib"] == 2800
assert report["load_average"]["one_minute"] == 0.12
assert report["services"] == []
PY

JSON_SERVICE='quoted"unit\name'
run_report "$MOCK_BIN" --json --service "$JSON_SERVICE"
assert_status 0
printf '%s\n' "$RUN_OUTPUT" > "$JSON_FILE"
"$PYTHON_BIN" - "$JSON_FILE" "$JSON_SERVICE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as report_file:
    report = json.load(report_file)
assert report["services"] == [{"name": sys.argv[2], "status": "unknown"}]
PY

RUN_FAIL_DF=1 RUN_FAIL_FREE=1 RUN_FAIL_UPTIME=1 RUN_FAIL_SYSTEMCTL=1 \
  run_report "$MOCK_BIN" --json --service failing.service
assert_status 0
printf '%s\n' "$RUN_OUTPUT" > "$JSON_FILE"
"$PYTHON_BIN" - "$JSON_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as report_file:
    report = json.load(report_file)
assert report["disk"]["status"] == "unavailable"
assert report["disk"]["used_kib"] is None
assert report["memory"]["status"] == "unavailable"
assert report["load_average"]["status"] == "unavailable"
assert report["services"] == [{"name": "failing.service", "status": "unavailable"}]
PY

RUN_BAD_UPTIME=1 run_report "$MOCK_BIN" --json
assert_status 0
printf '%s\n' "$RUN_OUTPUT" > "$JSON_FILE"
"$PYTHON_BIN" - "$JSON_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as report_file:
    report = json.load(report_file)
assert report["load_average"]["status"] == "unavailable"
PY

printf 'PASS: system metrics, selected services, optional systemctl, text/JSON output, escaping, and command failures\n'

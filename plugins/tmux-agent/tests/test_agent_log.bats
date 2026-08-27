#!/usr/bin/env bats
# Tests for the lifecycle event log (log_event + the `log` verb): every
# spawn/reuse/bind/new/kill decision appends one JSONL record. Runs against a
# dedicated detached test session with the mock codex fixture, like the other
# suites. See README.md.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/codex-tmux.sh"

setup() {
    PANE_SESSION="cc-codex-log-test-$$"
    tmux kill-session -t "$PANE_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$PANE_SESSION" -x 220 -y 50
    REF_PANE="$(tmux list-panes -t "$PANE_SESSION" -F '#{pane_id}' | head -n1)"
    export CC_CODEX_REF_PANE="$REF_PANE"
    export CC_CODEX_BIN="$BATS_TEST_DIRNAME/fixtures/mock-codex.sh"
    export CLAUDE_CODE_SESSION_ID="106f11e-0000-0000-0000-000000000000"  # claude6=106f11
    export CC_CODEX_SESSION_NAME="cc-codex-logtest-$$"
    export CC_CODEX_EXIT_SHELL="/bin/bash"
    export CC_AGENT_LOG_FILE="$BATS_TEST_TMPDIR/events.jsonl"
}

teardown() {
    tmux kill-session -t "$PANE_SESSION" 2>/dev/null || true
    tmux kill-session -t "$CC_CODEX_SESSION_NAME" 2>/dev/null || true
}

@test "log: pane spawn then reuse append distinct events" {
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    PANE="${lines[0]}"
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    run cat "$CC_AGENT_LOG_FILE"
    [[ "$output" == *'"event":"spawn","reason":"fresh"'* ]]
    [[ "$output" == *'"event":"reuse","reason":"alive"'* ]]
    [[ "$output" == *'"kind":"codex"'* ]]
    [[ "$output" == *"\"target\":\"$PANE\""* ]]
    [[ "$output" == *'"claude6":"106f11"'* ]]
}

@test "log: new and kill append events with the topic" {
    run "$SCRIPT" new logdemo --cwd /tmp
    [ "$status" -eq 0 ]
    WIN="${lines[0]}"
    run "$SCRIPT" kill "$WIN"
    [ "$status" -eq 0 ]
    run cat "$CC_AGENT_LOG_FILE"
    [[ "$output" == *'"event":"new-window","reason":"explicit","claude6":"106f11","topic":"logdemo"'* ]]
    [[ "$output" == *'"event":"kill","reason":"window"'* ]]
}

@test "log: kill --mine appends a summary event" {
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    run "$SCRIPT" kill --mine
    [ "$status" -eq 0 ]
    run cat "$CC_AGENT_LOG_FILE"
    [[ "$output" == *'"event":"kill-mine","reason":"removed=1"'* ]]
}

@test "log: CC_AGENT_LOG=0 disables logging" {
    export CC_AGENT_LOG=0
    run "$SCRIPT" new logoff --cwd /tmp
    [ "$status" -eq 0 ]
    [ ! -f "$CC_AGENT_LOG_FILE" ]
}

@test "log verb: --tail prints recent events, --path prints the file, empty log exits 1" {
    run "$SCRIPT" log
    [ "$status" -eq 1 ]
    run "$SCRIPT" new logtail --cwd /tmp
    [ "$status" -eq 0 ]
    run "$SCRIPT" log --tail 5
    [ "$status" -eq 0 ]
    [[ "$output" == *'"event":"new-window"'* ]]
    run "$SCRIPT" log --path
    [ "$status" -eq 0 ]
    [[ "$output" == "$CC_AGENT_LOG_FILE" ]]
}

@test "log: rotates once at ~1MB keeping the old file as .1" {
    mkdir -p "$(dirname "$CC_AGENT_LOG_FILE")"
    head -c 1100000 /dev/zero | tr '\0' 'x' > "$CC_AGENT_LOG_FILE"
    run "$SCRIPT" new logrot --cwd /tmp
    [ "$status" -eq 0 ]
    [ -f "$CC_AGENT_LOG_FILE.1" ]
    run cat "$CC_AGENT_LOG_FILE"
    [[ "$output" == *'"event":"new-window"'* ]]
    [ "$(wc -c < "$CC_AGENT_LOG_FILE")" -lt 10000 ]
}

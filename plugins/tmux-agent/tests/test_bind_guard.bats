#!/usr/bin/env bats
# Tests for the bind guard and late session creation:
#   - `bind` refuses (exit 7) while this session already owns a live or
#     kept-shell agent PANE, so a drifting caller cannot strand the
#     conversation in a second target;
#   - a refused/aborted call creates NO shared session and no placeholder;
#   - --force still allows the deliberate case.
# Runs against a dedicated detached test session with the mock codex fixture,
# like the other suites. See README.md.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/codex-tmux.sh"

setup() {
    PANE_SESSION="cc-codex-guard-test-$$"
    tmux kill-session -t "$PANE_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$PANE_SESSION" -x 220 -y 50
    REF_PANE="$(tmux list-panes -t "$PANE_SESSION" -F '#{pane_id}' | head -n1)"
    export CC_CODEX_REF_PANE="$REF_PANE"
    export CC_CODEX_BIN="$BATS_TEST_DIRNAME/fixtures/mock-codex.sh"
    export CLAUDE_CODE_SESSION_ID="9a71cc-0000-0000-0000-000000000000"  # claude6=9a71cc
    export CC_CODEX_SESSION_NAME="cc-codex-guardtest-$$"
    export CC_CODEX_EXIT_SHELL="/bin/bash"
    export CC_AGENT_LOG_FILE="$BATS_TEST_TMPDIR/events.jsonl"
}

teardown() {
    tmux kill-session -t "$PANE_SESSION" 2>/dev/null || true
    tmux kill-session -t "$CC_CODEX_SESSION_NAME" 2>/dev/null || true
}

@test "bind: refuses with exit 7 while a live pane exists, naming the pane" {
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    local pane="${lines[0]}"
    run "$SCRIPT" bind --cwd /tmp
    [ "$status" -eq 7 ]
    [[ "$output" == *"already owns codex pane $pane"* ]]
    [[ "$output" == *"--force"* ]]
}

@test "bind: a refused bind creates no session and no placeholder" {
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    run "$SCRIPT" bind --cwd /tmp
    [ "$status" -eq 7 ]
    run tmux has-session -t "$CC_CODEX_SESSION_NAME"
    [ "$status" -ne 0 ]
}

@test "bind: the refusal is logged with the pane state and target" {
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    local pane="${lines[0]}"
    run "$SCRIPT" bind --cwd /tmp
    [ "$status" -eq 7 ]
    run cat "$CC_AGENT_LOG_FILE"
    [[ "$output" == *'"event":"bind-refused","reason":"pane-exists-alive"'* ]]
    [[ "$output" == *"\"target\":\"$pane\""* ]]
}

@test "bind: the guard also fires for a kept-shell pane (relaunchable, not gone)" {
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    local pane="${lines[0]}"
    # /exit makes the mock exit 0 → the pane stays, dropped into a shell.
    tmux send-keys -t "$pane" "/exit" Enter
    sleep 1.0
    run "$SCRIPT" bind --cwd /tmp
    [ "$status" -eq 7 ]
    [[ "$output" == *"state: shell"* ]]
}

@test "bind --force: overrides the guard and creates the bound window" {
    run "$SCRIPT" pane --cwd /tmp
    [ "$status" -eq 0 ]
    run "$SCRIPT" bind --force --cwd /tmp
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "codex-9a71cc" ]
}

@test "bind: with no pane it still works and logs session-create once" {
    unset CC_CODEX_REF_PANE
    run "$SCRIPT" bind --cwd /tmp
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "codex-9a71cc" ]
    run cat "$CC_AGENT_LOG_FILE"
    [[ "$output" == *"\"event\":\"session-create\",\"reason\":\"$CC_CODEX_SESSION_NAME\""* ]]
    [ "$(grep -c '"event":"session-create"' "$CC_AGENT_LOG_FILE")" -eq 1 ]
}

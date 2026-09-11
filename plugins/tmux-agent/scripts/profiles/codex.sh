# shellcheck shell=bash
# shellcheck disable=SC2034  # PROFILE_* vars are consumed by the sourcing engine
# profiles/codex.sh — codex kind profile for agent-tmux.sh (sourced, not run).
#
# Profile contract — every profile defines:
#   PROFILE_TITLE          display name used in success messages ("Codex pane %s ...")
#   PROFILE_BIN_DEFAULT    binary launched when CC_AGENT_BIN is unset
#   PROFILE_MODEL_DEFAULT  model passed at every spawn (CC_AGENT_MODEL overrides);
#                          empty = omit the flag and inherit the CLI's own config
#   PROFILE_EFFORT_DEFAULT reasoning effort passed at every spawn; empty = inherit
#   PROFILE_ENV_PREFIX     legacy env-var prefix shown in user-facing messages
#   PROFILE_RESUME_CMD     command a human types in the kept shell to continue
#                          the previous conversation (keep-shell hint text)
#   PROFILE_LOGIN_HINT     auth command suggested when the CLI dies at launch
#   PROFILE_IDLE_REGEX     input-ready status-line regex (consumed by the skill
#                          recipes today; the `wait` verb in a later ticket)
#   PROFILE_VERSION_FLOOR  minimum CLI version these defaults assume
#   agent_compose_cmd SANDBOX APPROVAL
#                          append the full launch argv to the AGENT_CMD array,
#                          starting from $AGENT_BIN and using $AGENT_MODEL /
#                          $AGENT_EFFORT (already env-resolved by the engine)
#
# Version-sensitive facts live HERE (single source of truth) — a codex CLI
# upgrade should only ever touch this file and the codex skill references.

PROFILE_TITLE="Codex"
PROFILE_BIN_DEFAULT="codex"
# Empty = inherit the user's own codex config (~/.codex/config.toml `model` and
# `model_reasoning_effort`): -m / model_reasoning_effort are passed ONLY when a
# model or effort is explicitly requested via CC_CODEX_MODEL / CC_CODEX_EFFORT.
# Same policy as the claude profile.
PROFILE_MODEL_DEFAULT=""
PROFILE_EFFORT_DEFAULT=""
PROFILE_ENV_PREFIX="CC_CODEX"
PROFILE_RESUME_CMD="codex resume --last"
PROFILE_LOGIN_HINT="codex login"
# Safety defaults applied when the caller passes no --full-auto/--read-only:
# sandbox mode and approval policy for every fresh start (spawn or relaunch).
PROFILE_SANDBOX_DEFAULT="read-only"
PROFILE_APPROVAL_DEFAULT="on-request"
# First-run gate: on a fresh CODEX_HOME the TUI shows a "Hooks need review"
# prompt before accepting work — dismiss with: send-keys "2" Enter ("Trust
# all and continue"). Auth gate: "Not authenticated" → PROFILE_LOGIN_HINT.
# Consumed by the skill recipes (tmux-mode.md) and T5's blocked-state work.
PROFILE_FIRST_RUN_GATE='Hooks need review -> send "2" Enter (Trust all and continue)'
# Model-agnostic: codex's idle footer is "<model> [<effort>] · <cwd>" whatever
# model the user's config selects — "gpt-6-astra medium · ~/x", "gpt-5.6-sol
# xhigh · /x", "o4-mini · /x" (verified live on codex 0.154.0). Anchored to ONE
# model token, an optional lowercase effort word, then the middot, so notices
# that also carry "·" ("⚠ 1 MCP startup issue · ctrl + t") never match.
# POSIX ERE: `wait` applies it with `grep -E` to the bottom 3 pane lines.
PROFILE_IDLE_REGEX='^[[:space:]]*[^[:space:]]+( [a-z]+)? · '
PROFILE_VERSION_FLOOR="0.144.0"

agent_compose_cmd() {
    local sandbox="$1" approval="$2"
    AGENT_CMD=( "$AGENT_BIN" )
    # Model/effort only when explicitly requested; otherwise codex's own config.
    [[ -n "$AGENT_MODEL" ]] && AGENT_CMD+=( -m "$AGENT_MODEL" )
    AGENT_CMD+=( -c "approval_policy=$approval" )
    [[ -n "$AGENT_EFFORT" ]] && AGENT_CMD+=( -c "model_reasoning_effort=$AGENT_EFFORT" )
    AGENT_CMD+=( -s "$sandbox" )
    if [[ "$sandbox" == "workspace-write" ]]; then
        AGENT_CMD+=( -c "sandbox_workspace_write.network_access=true" )
    fi
    return 0
}

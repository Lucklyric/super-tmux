#!/usr/bin/env bash
# UserPromptSubmit hook: when the user's prompt names a supported agent CLI,
# inject a reminder to invoke the matching tmux-agent skill before driving that
# CLI. Skill-description triggering is probabilistic; this makes the nudge
# deterministic. Codex matches on any mention; claude only on narrow co-worker
# phrasing (bare "claude" is ambient in Claude Code conversations).
set -euo pipefail

# Version staleness: Claude Code pins a plugin's paths for the LIFE of a
# session, so a conversation started before an update keeps loading the OLD
# copy of the skills and calling the OLD scripts — shipped fixes never reach
# it, silently, for as long as it runs. This hook knows its own version from
# its path (<cache>/<plugin>/<version>/hooks/<file>), so it can compare that
# against the newest installed copy and say so on every nudge. Prints a
# sentence to append to the context, or nothing when current / not a
# versioned install (local checkout, dev symlink).
staleness_note() {
    local here version parent newest
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || return 0
    version="$(basename "$here")"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0
    parent="$(dirname "$here")"
    newest="$(find "$parent" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
    [[ -n "$newest" && "$newest" != "$version" ]] || return 0
    # Only warn when the installed copy is actually NEWER than ours.
    [[ "$(printf '%s\n%s\n' "$version" "$newest" | sort -V | tail -n1)" == "$newest" ]] || return 0
    printf ' [STALE PLUGIN] This session loaded tmux-agent %s, but %s is installed. Plugin paths are pinned when a session starts, so fixes in %s are NOT active here and the skill text you have may be outdated. Tell the user to restart this session (or run /reload-plugins) before relying on agent-pane orchestration.' \
        "$version" "$newest" "$newest"
}

input=$(cat)

# Extract the prompt field (jq preferred; python3 fallback; else give up silently).
prompt=$(printf '%s' "$input" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null) \
  || prompt=$(printf '%s' "$input" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("prompt") or d.get("user_prompt") or "")' 2>/dev/null) \
  || prompt=""

[[ -z "$prompt" ]] && exit 0

context=""

# Word-boundary match without \b (portable across BSD and GNU grep).
if printf '%s' "$prompt" | grep -qiE '(^|[^a-zA-Z0-9_])codex([^a-zA-Z0-9_]|$)'; then
  context="[tmux-agent plugin] This prompt names codex. If it asks codex to perform ANY task (any phrasing: use/using codex, ask/run/call codex, have/let/tell/get codex, delegate to codex, 'codex: <task>', bare 'codex review/fix/...'), invoke the codex skill via the Skill tool (skill: tmux-agent:codex) BEFORE running any codex CLI command or tmux interaction with codex — do not drive codex from memory. Codex is a co-worker in a visible tmux pane beside Claude: reuse the existing pane (spawn only if absent), give parallel workers their own panes, and NEVER run headless 'codex exec' unless the user explicitly asked for headless or confirmed it. Skip this only if the codex skill is already loaded in this conversation, or if codex is merely being discussed rather than asked to act."
elif printf '%s' "$prompt" | grep -qiE '(^|[^a-zA-Z0-9_])((spawn|launch|start|drive|open|another|second)[a-zA-Z ]{0,24} claude([^a-zA-Z0-9_]|$)|claude +(pane|co-?worker|worker|instance|cli))'; then
  context="[tmux-agent plugin] This prompt asks for Claude Code CLI as a pane co-worker. Invoke the claude skill via the Skill tool (skill: tmux-agent:claude) BEFORE spawning or driving a claude pane — do not drive it from memory. Reuse the existing co-worker pane (spawn only if absent) and give parallel workers their own topic-named panes. Skip this only if the claude skill is already loaded in this conversation, or if claude is merely being discussed rather than asked to act as a co-worker."
fi

[[ -z "$context" ]] && exit 0

# Append the staleness warning (if any) so a session running an outdated copy
# says so instead of silently misbehaving.
context+="$(staleness_note)"

jq -n --arg ctx "$context" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}' 2>/dev/null || printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$context"

exit 0

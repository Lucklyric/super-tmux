#!/usr/bin/env bash
# UserPromptSubmit hook: when the user's prompt names a supported agent CLI,
# inject a reminder to invoke the matching tmux-agent skill before driving that
# CLI. Skill-description triggering is probabilistic; this makes the nudge
# deterministic. Codex matches on any mention; claude only on narrow co-worker
# phrasing (bare "claude" is ambient in Claude Code conversations).
set -euo pipefail

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
elif printf '%s' "$prompt" | grep -qiE '(^|[^a-zA-Z0-9_])((spawn|launch|start|drive|open|another)[a-zA-Z ]{0,24} claude([^a-zA-Z0-9_]|$)|claude +(pane|co-?worker|worker|instance|cli))'; then
  context="[tmux-agent plugin] This prompt asks for Claude Code CLI as a pane co-worker. Invoke the claude skill via the Skill tool (skill: tmux-agent:claude) BEFORE spawning or driving a claude pane — do not drive it from memory. Reuse the existing co-worker pane (spawn only if absent) and give parallel workers their own topic-named panes. Skip this only if the claude skill is already loaded in this conversation, or if claude is merely being discussed rather than asked to act as a co-worker."
fi

[[ -z "$context" ]] && exit 0

jq -n --arg ctx "$context" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}' 2>/dev/null || printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$context"

exit 0

---
description: Re-sync this session with the current tmux-agent orchestration contract — resolve the helper path, restate the routing rules, and report drift in panes, plugin version, and project/memory context files
argument-hint: "[codex|claude|all] [--fix]"
allowed-tools: [Bash, Read, Grep, Glob, Skill]
---

# tmux-agent: refresh

Bring THIS session back onto the current orchestration contract, and surface any
context that is pulling it toward an older manner (cc-codex windows, headless
`exec`, removed verbs). Run all six steps in order and report at the end.

Argument (`$ARGUMENTS`): `codex` (default), `claude`, or `all` — which agent
skill to re-sync. `--fix` = after reporting, offer the corrections one by one.
**Never edit a context file or kill a pane in this command without confirming.**

## 1. Resolve the helper script (do this FIRST)

Claude Code substitutes the braces-form plugin-root placeholder with the
plugin's absolute install path in skill content it loads — but it never exports
it as an environment variable, so bare `$CLAUDE_PLUGIN_ROOT` is empty in the
Bash tool. A snippet typed from memory in the bare form fails with exit 127, and
a `pane || bind` guard then silently falls through to `bind` — exactly how a
session drifts back to a `cc-codex` window. Resolve a real path once
(placeholder first; newest installed copy as the fallback):

```bash
ROOT="${CLAUDE_PLUGIN_ROOT}"   # literal path if substituted here; else empty → fallback
[[ -x "$ROOT/scripts/codex-tmux.sh" ]] || \
  ROOT=$(ls -d "$HOME"/.claude/plugins/cache/*/tmux-agent/*/ 2>/dev/null | sort -V | tail -1)
ROOT="${ROOT%/}"
AGENT="$ROOT/scripts/agent-tmux.sh"; CODEX="$ROOT/scripts/codex-tmux.sh"
[[ -x "$CODEX" ]] && echo "helper: $CODEX" || echo "HELPER NOT FOUND — reinstall tmux-agent"
```

Report the resolved path and **use that absolute path for every helper call for
the rest of the conversation** (re-state it per Bash call — each is a fresh
shell). Never type bare `$CLAUDE_PLUGIN_ROOT` into a Bash command.

## 2. Re-read the contract

Invoke the matching skill(s) via the Skill tool — `tmux-agent:codex`, and
`tmux-agent:claude` when the argument asks for it — so the session is working
from the installed text, not from recall. Then state the contract back in six
lines so the correction is explicit in-context:

- **Default target = a pane in the CURRENT window.** `pane` is idempotent:
  reuse-if-alive, relaunch-in-kept-shell, relocate-if-drifted, respawn-if-dead.
- **`bind` (a `cc-codex` window) is the NOT-inside-tmux fallback only** — `pane`
  exit 3, or exit 4 after codex died at launch. Never the first choice inside tmux.
- **`new <topic>` only on an explicit "separate window" / "new window" request.**
  "side by side", "beside me", "in a pane" all mean the default pane.
- **Parallel workers = `pane --topic <slug>` in the CURRENT window**, one driver
  per pane, never several `exec` one-shots.
- **Headless `exec` only when the user asked for headless, a hook is calling, or
  `codex review` on a diff** — otherwise confirm first.
- **Drive with the verbs**: `prompt --wait` → `read --delta`, `wait` exit codes
  0/5/6/8/9, `cancel` to interrupt. `send`/`capture` were removed (exit 64).

## 3. Inventory what this session owns

```bash
"$CODEX" panes                 # TSV: pane_id, topic, state, session:window, cwd (exit 1 = none)
"$CODEX" ls --mine             # windows owned by this claude6
"$CODEX" log --tail 20         # recent lifecycle events — bind-*/new-window rows explain any window
tmux display-message -p '#{session_name}:#{window_index}'   # where we are now
```

Flag as **drift** (report, then offer the fix — do not act unsolicited):

| Observation | Meaning | Offer |
|---|---|---|
| `TMUX` set AND `ls --mine` lists a window | old-manner artifact: a `cc-codex` window exists while a pane was possible | consolidate: `kill <window>`, then `pane --cwd "$PWD"` |
| A `cc-<kind>` session holding only `_placeholder` | leftover from an aborted/refused window call (pre-1.3.0 created it up front) | offer `tmux kill-session -t cc-<kind>` — check first that it holds no real window |
| two panes with topic `main` | duplicate from a rolled session id | `kill %id` on the stale one |
| pane in a different `session:window` than current | it will be relocated on the next `pane` call | none — informational |
| state `dead` / `shell` | respawn / relaunch happens automatically on next `pane` | none — informational |
| no panes and no windows | clean slate | none |

## 4. Version check

```bash
python3 - <<'PY'
import json, os
p = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))['plugins']
for k, v in p.items():
    if 'tmux' in k:
        for i in v: print(k, i['version'], i['installPath'])
PY
ls -d "$HOME"/.claude/plugins/cache/*/tmux-agent/*/ 2>/dev/null   # other cached versions
```

Report the active version, and whether older cached versions are present (they
are inert unless enabled, but confirm none is enabled at project scope by
checking `.claude/settings.json` in the current project).

**Staleness is the important one.** Plugin paths are pinned when a session
starts, so a conversation older than the last update keeps loading the OLD
skills and calling the OLD scripts — shipped fixes never reach it. Compare the
version in the resolved helper path against the newest installed copy; if they
differ, say so plainly and tell the user to restart the session (or run
`/reload-plugins`). The skill-nudge hook also flags this on every prompt that
names an agent, but only from the version it is itself pinned to.

## 5. Scan context and memory files for conflicts

The most common cause of an agent reverting to an older manner is stale text in
files that load ahead of the skill. Scan, in this order, only what exists:

```bash
# Glob-free file list: zsh (the Bash tool's shell on macOS) aborts on an
# unmatched glob, so collect paths with ls/find instead.
MEM="$HOME/.claude/projects/$(echo "$PWD" | tr '/' '-')/memory"
{ ls ./CLAUDE.md ./AGENTS.md "$HOME/.claude/CLAUDE.md" 2>/dev/null
  find ./.claude ./.remember "$MEM" -maxdepth 2 -name '*.md' 2>/dev/null; } | sort -u |
  tr '\n' '\0' | xargs -0 grep -nEi \
  'codex exec|cc-codex|codex-tmux\.sh (spawn|send|capture)|plugins/codex/|codex@cc-dev-tools|gpt-5(\.[0-5])?\b' \
  2>/dev/null
```

Classify every hit against the contract in step 2:

- **Conflict** — instructs an older route: `exec`/headless as the default, a
  `cc-codex` window as the default target, `spawn`/`send`/`capture` verbs, the
  retired `codex@cc-dev-tools` plugin or `plugins/codex/...` paths, a model pin
  older than `gpt-5.6-sol`.
- **Stale but harmless** — historical notes, changelogs, spec files describing
  past versions.
- **Fine** — matches the current contract.

Report conflicts as `file:line — what it says → what the contract says`. With
`--fix`, propose one edit per conflict and apply only what the user approves.
Memory files under `~/.claude/projects/*/memory/` and `.remember/` are the
user's — always ask before rewriting them.

## 6. Report

Close with a compact status block and one carry-forward line:

```
helper    : <abs path>            [ok|missing]
skills    : tmux-agent:<name> re-read  (plugin <version>)
panes     : <n> (<topics/states>) in <session:window>
drift     : none | <list, with the offer made>
context   : <n> conflicts | none  (<file:line list>)
carry-fwd : default target = pane in current window; call the helper by absolute path
```

If everything is clean, say so in one line — do not manufacture findings.

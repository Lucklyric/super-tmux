---
name: tmux-agent
description: This skill should be used when the agent needs to drive, observe, or manage ANOTHER interactive command-line program inside tmux — especially other agent CLIs such as codex, claude, gemini, or aider. Triggers on spawning or reusing a pane/window co-worker for a long-lived CLI, sending it prompts and reading its responses (prompt/wait/read verbs or send-keys/capture-pane), detecting when the driven CLI is idle/busy/blocked, binding one Claude session to its sub-processes, running several agent panes in parallel (multi-agent collaboration), serializing concurrent drivers, and lifecycle/cleanup of those panes. For codex-as-actor requests ("ask codex to X") the codex skill is the entry point — this skill is the generic engine behind it. Do NOT trigger for plain one-shot shell commands that finish on their own, for daily tmux usage questions (sessions, layouts, copy-mode — the tmux-core plugin's tmux skill), or when the user is merely discussing tmux as a topic.
---

# Tmux-Agent: Driving Agent CLIs as Pane Co-Workers

Use this skill when you (Claude) must run **another interactive command-line program** —
typically another agent CLI like codex, claude, gemini, or aider — keep it alive across
your bash calls, feed it input, watch its output, know when it has finished a turn, and
iterate. The driven CLI runs as a **visible tmux pane co-worker beside you**, in the
window the human is already looking at: progress is watchable live, with no separate
attach.

This plugin ships a kind-agnostic **engine** (`scripts/agent-tmux.sh`), one ~50-line
**profile** per supported CLI (`scripts/profiles/<kind>.sh`), and **driving verbs** that
make the whole interaction loop a script surface instead of copy-pasted shell. Daily tmux
fundamentals (sessions, layouts, copy-mode) are the `tmux` skill in the **tmux-core**
plugin; per-CLI specifics are the kind skills (`codex`, `claude`) in this plugin.

## Mental model: a co-worker in a pane

- **One reused co-worker per driving session by default.** Follow-up work goes to the
  same pane, same conversation. Parallel work gets *extra* topic-named panes; a separate
  window only on explicit request.
- **Marker-based identity.** Every pane/window is stamped with a per-session token
  (`claude6` = first 6 chars of the driving session's id) plus its topic, as tmux user
  options. Location is by marker — never by guessed pane index — so reuse survives pane
  moves, and one driving session can never touch another's workers.
- **Keep-shell lifecycle.** When the CLI exits, the pane does NOT die: it drops into an
  interactive shell with scrollback intact (a human can take over, e.g. `codex resume
  --last`), and the next lifecycle call relaunches the CLI in the same pane.

Object-model and naming theory: `references/model-and-identity.md`.

> **Agent-session isolation (hard rule).** Every operation — resolve/reuse, relocate,
> spawn, cleanup — touches ONLY this session's own markered panes/windows. **Never**
> move, kill, reuse, or disturb a pane belonging to another agent (a different
> `claude6`) or one you did not create. `kill --orphaned` is global/cross-agent
> housekeeping — only on explicit user request.

## Kinds and profiles

Everything CLI-specific lives in one profile: binary, model/effort defaults,
sandbox/approval defaults, launch-flag composition, idle/busy regexes, first-run gates,
resume command, login hint, version floor. The engine is kind-agnostic; select the kind
with `--kind <k>` or `CC_AGENT_KIND`.

| Kind | Profile | Notes |
|---|---|---|
| `codex` | `scripts/profiles/codex.sh` | Full depth. Drive it through the wrapper `scripts/codex-tmux.sh` (stable legacy surface, `CC_CODEX_*` env, codex-only `exec`/review verbs) — see the **codex skill**. |
| `claude` | `scripts/profiles/claude.sh` | Claude Code CLI as a co-worker — see the **claude skill**. No reliable idle footer (user-configurable), so `wait` anchors on the busy marker `esc to interrupt`. |
| anything else | calibrate one | **New kinds are profiles, not plugins** — see "Unknown CLIs" below. |

Generic env knobs (kind wrappers map their legacy names onto these): `CC_AGENT_BIN`,
`CC_AGENT_MODEL`, `CC_AGENT_EFFORT`, `CC_AGENT_SESSION_NAME`, `CC_AGENT_KEEP_SHELL`,
`CC_AGENT_IDLE_REGEX`, `CC_AGENT_BUSY_REGEX`.

## The script surface

Lifecycle + interaction, all with clean exit codes:

```bash
# Literal absolute path once this skill is loaded via the Skill tool (the braces
# placeholder is substituted; bare $CLAUDE_PLUGIN_ROOT is NOT an exported variable).
# Re-state this line at the top of every Bash call.
ENGINE="${CLAUDE_PLUGIN_ROOT}/scripts/agent-tmux.sh"

# Lifecycle: resolve/reuse THE co-worker pane (idempotent: reuse if alive,
# relaunch in kept shell if exited, respawn if dead, split only if absent).
$ENGINE --kind claude pane --cwd "$PWD"              # → pane id, e.g. %53
$ENGINE --kind claude pane --topic tests --cwd "$PWD" # extra parallel worker
$ENGINE --kind claude new tests --cwd "$PWD"          # separate WINDOW (explicit request only)
$ENGINE --kind claude panes --json                    # this session's panes + states
$ENGINE --kind claude bind --cwd "$PWD"               # fallback window when not inside tmux

# Driving verbs: the interaction loop as commands.
$ENGINE --kind claude prompt --wait -- "Review the diff in @changes.patch"
$ENGINE --kind claude read --delta                    # only output since that prompt
$ENGINE --kind claude cancel                          # Escape the in-flight turn
```

- **`prompt`** — atomic send (literal keys, pause, Enter as its own event). Long or
  multi-line text is handed over via a tmp file automatically (or pass `--file PATH`).
  Records the baseline that `wait` and `read --delta` anchor to. `--wait` chains.
- **`wait`** — settled-state detection: first requires pane *activity* (exit 8 =
  stalled, the send never started a turn), then stability plus the profile's idle
  regex / busy-marker absence. Exit 0 = idle; 5 = timeout; 6 = no target; 9 = agent
  exited. Standalone `wait` asks "is it idle now?".
- **`read --delta`** — only what the agent emitted since the last `prompt`; works on
  growing-buffer and screen-padding TUIs alike. Plain `read` = last N lines.
- **`cancel`** — Escape, then re-run `wait`.

For codex, use `codex-tmux.sh` (same verbs, codex defaults) — the codex skill is
canonical. The raw `send-keys`/`capture-pane` recipes behind these verbs — for
hand-driving an unprofiled CLI — live in `references/interaction-recipes.md`.

**Readiness-or-dead check.** A freshly spawned CLI can die at launch (bad flag, missing
auth). `pane`/`bind` verify liveness with one auto-retry and surface the CLI's last
output on stderr (exit 4). Never drive a target you haven't confirmed alive.

**Structural guard on routing.** `bind` (the dedicated-window fallback) **refuses with
exit 7 while this session already owns a live or kept-shell pane** — that pane is
drivable from anywhere, so a second target would only strand the conversation. Nothing
is created on a refusal, and the shared `cc-<kind>` session is created only at the
moment of an actual spawn, so an aborted call never leaves a stray session behind.
`--force` covers the deliberate case. This is a guard in the engine, not advice in a
skill: it holds even when a session is running outdated skill text.

**Event log (audit trail).** Every lifecycle decision — spawn/reuse/relaunch/relocate,
each `bind` fallback with its reason, `new` windows, kills — appends one JSONL record
to `~/.local/state/tmux-agent/events.jsonl` (shared across kinds; `CC_AGENT_LOG=0`
disables, `CC_AGENT_LOG_FILE` overrides, rotated once at ~1MB). `log --tail 20` shows
recent events; `log --path` prints the file. It is an audit trail only — live state
stays in tmux options — but it answers "why did a `cc-<kind>` window appear?" after
the fact: look for `bind-*` / `new-window` events and their reasons.

## States (keep-shell)

| State | Meaning |
|---|---|
| `alive` | the agent CLI is running — drive it |
| `shell` | the CLI exited; the pane sits at a usable shell — next `pane` relaunches in place |
| `dead`  | the pane's root process exited (kept for post-mortem) |

Liveness is read from the process tree (the launched binary is recorded per pane), not
from parsing the screen. `panes` reports the state per pane.

## Adaptive I/O: pick the channel by content

Everything flows through a tmux screen, which redraws, wraps, and forgets
(`history-limit`). Choose the input and output channel **per message, by size and
structure** — never lose information to the pane:

**Input (you → co-worker):**

| Content | Channel |
|---|---|
| Short, single-line (≤ ~500 chars) | Inline — `prompt -- "text"` (literal send-keys + Enter). |
| Long, multi-line, code blocks, specs | Tmp-file handoff — `prompt` does this automatically (or `--file PATH`): body goes to a tmp file, the pane gets `Read @/path and follow its instructions.` Never a heredoc (delimiter collisions truncate silently). |

**Output (co-worker → you):**

| Content | Channel |
|---|---|
| Normal turn response | `read --delta` after `wait` — exactly what was emitted this turn. |
| Long response (> ~200 lines) | `read --lines 1000`, or the `incremental-capture` / `copy-mode-navigation` recipes. |
| Structured deliverable (report, review, plan, diff) or anything near the scrollback limit | **File handoff**: put the output path in the prompt itself — *"write your full report to `/tmp/agent-out.md`; reply DONE when finished"* — then `wait` and Read the file. Lossless: no redraw noise, no wrap damage, no history-limit cliff. |

```bash
OUT=$(mktemp -t agent-out).md
$ENGINE --kind claude prompt --wait -- \
  "Review this branch. Write the full review to $OUT, then reply DONE."
$ENGINE --kind claude read --delta        # small ack on screen…
# …the real payload is read losslessly from "$OUT" with the Read tool.
```

The pane stays the *visibility* channel either way — the human watches progress live;
the file carries the payload when the payload outgrows the screen. Escalate to the file
channel proactively when you *expect* a long/structured answer; don't wait for
truncation to prove it.

## Routing judgment: reuse, fresh, parallel, close

Routing is judgment, not keyword matching:

- **Reuse by default.** The co-worker keeps its conversation context across tasks —
  that is the point. New sub-task ≠ new pane.
- **Fresh context** only when the conversation genuinely moved to unrelated work —
  suggest it and confirm in one line before `kill` + re-resolve.
- **Topic panes** (`pane --topic <slug>`) when work is naturally concurrent ("two
  reviewers", "meanwhile run the tests through it").
- **Separate window** (`new <topic>`) only on explicit request; **close** only on an
  explicit yes — killing destroys scrollback irreversibly, never kill silently.
- **Explicit user phrasing overrides everything** ("new pane", "fresh codex", "kill
  it").

## One-driver discipline

Each pane has exactly **one driver at a time** — you. Complete the full loop (prompt →
wait → read) before the next send to the *same* pane; driving several *different* topic
panes concurrently is fine (each has its own baseline and idle state). Serialize
lifecycle operations and any same-pane parallelism with `flock`:
`references/sync-and-lifecycle.md`.

## Multi-agent collaboration

N named co-worker panes side by side, one driver (you) orchestrating:

```bash
CODEX="${CLAUDE_PLUGIN_ROOT}/scripts/codex-tmux.sh"   # substituted at skill load, like $ENGINE
$CODEX pane --topic review --cwd "$PWD"                      # codex reviewer
$ENGINE --kind claude pane --topic impl --cwd "$PWD"         # claude implementer

$CODEX prompt --topic review -- "Review @spec.md; write findings to /tmp/rev.md, reply DONE."
$ENGINE --kind claude prompt --topic impl -- "Implement section 2 of @spec.md."

$CODEX wait --topic review && cat /tmp/rev.md                # each waited independently
$ENGINE --kind claude wait --topic impl && $ENGINE --kind claude read --delta
```

Relay results between workers yourself (through prompts/files) — one driver per pane,
always; direct agent-to-agent messaging is deliberately out of scope.

## Unknown CLIs: calibrate from the pane

Any interactive CLI can be driven. Calibrate in three steps, entirely from its pane:
capture the settled screen (`tail -5`), pick a stable idle marker (or a busy marker if
the idle footer is configurable), verify submit behavior — then either export
`CC_AGENT_IDLE_REGEX`/`CC_AGENT_BUSY_REGEX` for a one-off, or write
`scripts/profiles/<kind>.sh` (~50 lines, contract documented in `profiles/codex.sh`) to
make it a first-class kind. Full walkthrough + per-CLI table:
`references/driving-agent-clis.md`.

## Decision table

| Situation | Action |
|---|---|
| First task for a CLI this conversation | `pane --cwd "$PWD"` (resolve/reuse THE co-worker), then `prompt --wait` + `read --delta`. |
| Follow-up / "continue" / "now also…" | Same pane, next `prompt`. |
| Naturally concurrent work | `pane --topic <slug>` per worker; drive each independently. |
| User asks for a separate window | `new <topic>`. |
| Conversation moved to unrelated work | Suggest fresh context; confirm; `kill` + re-resolve. |
| Long/multi-line prompt | `prompt` tmp-file handoff (automatic). |
| Expecting a long/structured answer | File handoff: output path in the prompt, Read the file after `wait`. |
| "Is it done?" | `wait` (exit 0 idle / 5 timeout / 8 stalled / 9 exited). |
| "Stop / cancel / never mind" | `cancel`, then `wait`. |
| CLI shows an unexpected prompt (trust/auth/approval) | Profile's first-run gate note; `handle-interruption` recipe. |
| CLI exited | Pane state `shell`: next `pane` relaunches in place (or the human resumes manually). |
| Wrapping up | Offer cleanup; confirm before any kill; `kill --mine` scoped to this session. |

## Reference index

- `references/model-and-identity.md` — session/window/pane model; `claude6` identity;
  naming; binding and reuse; topic-slug derivation; the matcher contract.
- `references/interaction-recipes.md` — the raw loop behind the verbs: send-inline,
  send-via-tmpfile, detect-idle (two-phase), extract-delta, incremental-capture,
  copy-mode, cancel, handle-interruption.
- `references/sync-and-lifecycle.md` — one-driver discipline, `flock` serialization,
  spawn/find/kill/cleanup, orphan/dead detection, `remain-on-exit`.
- `references/driving-agent-clis.md` — calibrating any CLI; per-CLI table; the engine +
  profiles as reference implementation.

# Architecture

Two plugins, three layers: generic tmux at the bottom, generic agent
orchestration in the middle, thin per-agent calibration on top. This document
is the design reference; the skills inside each plugin are the operational
documentation.

```
┌─────────────────────────────────────────────────────────────┐
│  L3  per-agent skills          plugins/tmux-agent/skills/   │
│      codex/  claude/  (+ generic fallback for unknown CLIs) │
├─────────────────────────────────────────────────────────────┤
│  L2  tmux-agent               plugins/tmux-agent/           │
│      kinds & profiles · pane co-workers · keep-shell ·      │
│      driving verbs · routing judgment · collaboration       │
├─────────────────────────────────────────────────────────────┤
│  L1  tmux-core                plugins/tmux-core/            │
│      daily tmux: sessions/windows/panes, layouts,           │
│      persistence, copy-mode + the raw primitives            │
└─────────────────────────────────────────────────────────────┘
```

## The co-worker model

An agent CLI (codex, claude, …) runs as a **visible tmux pane beside the
driving agent** in the window the human is already looking at — progress is
watchable live, with no separate attach. The rules that make this pleasant:

- **One reused co-worker per driving session by default.** Follow-up work goes
  to the same pane, same conversation. Parallel work gets *extra* topic-named
  panes; a separate window only on explicit request.
- **Marker-based identity.** Every pane/window is stamped with a per-session
  token (first 6 chars of the driving session's id) plus its topic, as tmux
  user options. Location is by marker — never by guessed pane index — so reuse
  survives pane moves, and one driving session can never touch another's
  workers.
- **Context-driven routing, confirm-gated.** The skill teaches judgment, not
  keyword matching: reuse by default; suggest a fresh context only when the
  conversation genuinely moved to unrelated work (one-line confirmation);
  spawn topic panes when work is naturally concurrent; close only on an
  explicit yes. Explicit user phrasing overrides everything.

## Lifecycle: keep-shell

When the agent CLI exits — cleanly or crashed — the pane does **not** die: it
drops into an interactive shell with scrollback intact, so a human can take
over manually (e.g. `codex resume --last`), and the next lifecycle call
relaunches the CLI **in the same pane**. Liveness is read from the process
tree (the launched binary is recorded per pane), giving three states:

| State | Meaning |
|---|---|
| `alive` | the agent CLI is running — drive it |
| `shell` | the CLI exited; the pane sits at a usable shell — relaunchable |
| `dead`  | the pane's root process exited (kept for post-mortem) |

Spawns verify the CLI survived launch (one auto-retry, error surfaced on
stderr), keep the CLI ≥80 columns by auto-switching split orientation, and
never kill anything silently.

## Driving verbs

The interaction loop is a script surface, not copy-pasted shell:

- **`prompt`** — atomic send (literal keys, pause, Enter as its own event);
  long or multi-line text is handed over via a tmp file automatically; records
  the baseline that `wait` and `read --delta` anchor to; `--wait` chains.
- **`wait`** — settled-state detection: after a prompt, first require pane
  *activity* (else a distinct "stalled" exit), then stability plus per-kind
  **idle** and **busy** markers. Busy markers matter because some TUIs
  (Claude Code) have user-configurable idle footers — "esc to interrupt" is
  the universal inverse signal. Distinct exit codes for timeout / no target /
  stalled / agent-exited.
- **`read --delta`** — only what the agent emitted since the last prompt.
  Works on growing-buffer TUIs (line-count tail) and screen-padding TUIs
  (first-divergence diff against the prompt-time baseline) alike.
- **`cancel`** — Escape to abort the in-flight turn.
- **`panes` / `find` `--json`** — machine-readable listings.

## Kinds and profiles

Everything CLI-specific lives in one ~50-line profile per kind
(`scripts/profiles/<kind>.sh`): binary, model/effort defaults, sandbox and
approval defaults, launch-flag composition, idle/busy regexes, first-run
gates, resume command, login hint, version floor. The engine
(`agent-tmux.sh`) is kind-agnostic; a kind wrapper (e.g. `codex-tmux.sh`)
keeps each CLI's historic command surface stable and maps its legacy
environment variables.

Supported kinds: **codex** (full depth: model pinning with fallback chain,
sandbox/approval mapping, confirm-gated headless `exec`, `review`/`apply`)
and **claude** (Claude Code CLI as a co-worker). Unknown CLIs calibrate from
their own pane: capture the settled screen, pick a stable idle/busy marker,
verify submit behavior.

## Design principles

1. **Agent-oriented.** Skills teach judgment; scripts are dumb, deterministic
   tools with clean exit codes; hooks only nudge skills into context. Nothing
   auto-acts.
2. **Single source of truth for version-sensitive facts.** Idle regexes,
   model slugs, CLI flags, version floors live in exactly one place — the
   kind's profile and that kind's own references. A CLI upgrade touches one
   file.
3. **Never break the golden flow.** "Ask the agent to do X" → visible pane
   co-worker → results relayed back. Every change is gated on the full test
   suite (bats), shellcheck, and a live smoke of that flow.
4. **New kinds are profiles, not plugins.** Supporting another agent CLI
   should cost a calibration file and a short skill, never new machinery.

## Multi-agent collaboration

Today: N named co-worker panes side by side (e.g. a codex reviewer beside a
claude implementer), with the driving agent orchestrating — sending each
worker its task, waiting on each pane independently, and relaying results.
One driver per pane, always. Direct agent-to-agent messaging is deliberately
out of scope until two kinds have run side by side in daily use; it will be
designed as its own increment.

## Status

1.0.0 — the engine, profiles, driving verbs, skills, hook, and the full test
suite are migrated here from the
[cc-dev-tools](https://github.com/Lucklyric/cc-dev-tools) marketplace's codex
plugin (v3.11.0), preserving the parity contract (spec 016). cc-dev-tools
retires its `codex` and `tmux` plugins at the corresponding cutover release.

# Tmux-Agent Plugin (L2 + L3 — agent CLIs as pane co-workers)

Drive agent CLIs (codex, claude, or any interactive CLI) as **visible tmux
pane co-workers** beside Claude Code:

- **Co-worker model**: one reused pane per session by default, topic panes for
  parallel workers, marker-based identity and strict per-session isolation,
  context-driven routing with confirm gates.
- **Keep-shell lifecycle**: the pane survives the CLI exiting (usable shell,
  relaunch in place, `alive/shell/dead` states from the process tree).
- **Driving verbs**: `prompt` / `wait` / `read --delta` / `cancel` plus
  `--json` listings — the whole interaction loop as script commands with
  distinct exit codes.
- **Kinds via profiles**: codex (full depth) and claude (Claude Code CLI)
  ship as ~50-line calibration profiles over one generic engine; unknown CLIs
  calibrate from their own pane.
- **Deterministic triggering**: a UserPromptSubmit hook nudges the right
  skill when a prompt names an agent.

Depends on the `tmux-core` plugin (auto-installed as a dependency).

See the repo [ARCHITECTURE.md](../../ARCHITECTURE.md) for the full design.

## Status

1.0.0 — the engine (`agent-tmux.sh`), kind profiles (codex, claude), driving verbs,
skill-nudge hook, skills (`tmux-agent`, `codex`, `claude`), and the full bats test
suite are migrated from [cc-dev-tools](https://github.com/Lucklyric/cc-dev-tools)'
codex plugin v3.11.0.

## Installation

```
/plugin marketplace add Lucklyric/tmux-agent
/plugin install tmux-agent@super-tmux
```

## License

Apache-2.0

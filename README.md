# super-tmux

A Claude Code plugin marketplace for tmux-based workflows, in two layers:

- **`tmux-core`** — daily tmux fundamentals and best practices: session/window/pane model,
  dev layouts, persistent sessions, attach/detach, copy-mode and scrollback, plus the
  generic `send-keys` / `capture-pane` primitives the agent layer builds on. Agent-free
  and useful standalone.
- **`tmux-agent`** — drive agent CLIs (codex, claude, or any interactive CLI) as **visible
  tmux pane co-workers**: reuse-by-default routing, keep-shell panes that survive the CLI
  exiting, named parallel workers, idle/blocked detection, per-agent calibration profiles,
  and a generic fallback for unknown CLIs. Depends on `tmux-core` (auto-installed).

## Status

1.0.0 — fully migrated from the
[cc-dev-tools](https://github.com/Lucklyric/cc-dev-tools) marketplace (formerly its
`codex` and `tmux` plugins): engine, kind profiles, driving verbs, hooks, skills, and
the full test suite live here.

## Installation

```
/plugin marketplace add Lucklyric/super-tmux
/plugin install tmux-agent@super-tmux
```

Installing `tmux-agent` automatically installs its `tmux-core` dependency from this
marketplace.

## Structure

```
.claude-plugin/marketplace.json      marketplace metadata
plugins/tmux-core/                   layer 1 — tmux basics
plugins/tmux-agent/                  layer 2+3 — orchestration + per-agent skills
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — the layered design: co-worker model,
  keep-shell lifecycle, driving verbs, kinds/profiles, design principles.
- [plugins/tmux-core/README.md](plugins/tmux-core/README.md) — the daily-tmux layer.
- [plugins/tmux-agent/README.md](plugins/tmux-agent/README.md) — the
  orchestration layer.

## License

Apache-2.0

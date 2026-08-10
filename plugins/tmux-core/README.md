# Tmux-Core Plugin (L1 — daily tmux)

Daily tmux fundamentals and best practices for Claude Code, agent-free:

- The session ⊃ window ⊃ pane model and when to use each.
- Dev layouts: editor + server + logs splits, resizing, layout presets.
- Persistent sessions: attach/detach workflows, surviving disconnects,
  one session per project.
- Copy-mode and scrollback: navigating, searching, capturing output,
  history limits.
- The raw primitives (`send-keys`, `capture-pane`, pane user options, naming
  hygiene) that the `tmux-agent` plugin builds on — documented once here.

Useful standalone: installing only this plugin adds zero agent content, no
hooks, and no prompt scanning.

## Status

1.0.0 — the `tmux` skill ships daily fundamentals plus the raw scripting primitives
(see the repo [ARCHITECTURE.md](../../ARCHITECTURE.md)).

## Installation

```
/plugin marketplace add Lucklyric/tmux-agent
/plugin install tmux-core@super-tmux
```

## License

Apache-2.0

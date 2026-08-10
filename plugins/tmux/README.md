# Tmux Plugin (L1 — daily tmux)

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

Pre-release scaffold — the skill content lands with the migration from
[cc-dev-tools](https://github.com/Lucklyric/cc-dev-tools) (see the repo
[ARCHITECTURE.md](../../ARCHITECTURE.md)).

## Installation (once released)

```
/plugin marketplace add Lucklyric/tmux-agent
/plugin install tmux@tmux-agent
```

## License

Apache-2.0

---
name: tmux
description: This skill should be used for daily tmux usage — creating and organizing sessions, windows, and panes; building dev layouts (editor + server + logs splits, resizing, zoom); persistent sessions and attach/detach workflows; copy-mode, scrollback navigation, searching, and capturing output; history limits; window/pane naming hygiene; and the raw send-keys / capture-pane / pane-user-option primitives used to script tmux. Do NOT trigger for programmatically driving ANY interactive CLI as a co-worker — agent CLIs (codex, claude, aider), REPLs, or other TUIs, including their send-keys/capture-pane/idle-detection loops — that is the tmux-agent skill; nor when tmux is merely a discussion topic.
---

# Tmux: Daily Fundamentals

tmux multiplexes one terminal into persistent named workspaces. Everything here is
agent-free daily usage; driving another interactive CLI programmatically is the
`tmux-agent` skill (tmux-agent plugin), which builds on the primitives documented at the
bottom of this page.

## Mental model: session ⊃ window ⊃ pane

- **Session** — a named, persistent container that survives detach and terminal loss.
  You attach to a session, not to programs: `tmux attach -t <name>`. Keep **one session
  per project**, named after the project.
- **Window** — one "tab" inside a session. Has a *name you control* — use it
  (`editor`, `server`, `logs`), don't leave a wall of `zsh` tabs.
- **Pane** — a rectangular split inside a window, running one process. A pane has no
  name, but it has an **immutable pane-id (`%NN`)** and per-pane user options. Pane
  *indexes* renumber as panes open and close — script against pane-ids, never indexes.

| You want… | Use |
|---|---|
| A separate project / long-lived context | A **session** |
| A separate task area within the project | A **window** |
| Two things visible at once (editor + tests) | A **pane** split |

## Sessions: persistence and attach/detach

```bash
tmux new -s myproj            # create + attach
tmux new -d -s myproj         # create detached (from scripts)
tmux ls                       # list sessions
tmux attach -t myproj         # reattach (survives SSH drops, terminal restarts)
tmux detach                   # or prefix d from inside
tmux kill-session -t myproj   # tear down when done
```

The default prefix is `Ctrl-b` (shown as `prefix` below). Detaching leaves everything
running — the shell, the server, the logs. Reattaching from a new terminal (or a new SSH
connection) restores the exact screen. This is the core daily win: start `tmux new -s
proj` in the morning, `tmux attach -t proj` after any disconnect.

Sessions do **not** survive a machine reboot — the tmux server is a process. For
across-reboot restoration use `tmux-resurrect`/`tmux-continuum` plugins.

## Windows

```bash
tmux new-window -n logs             # prefix c  (then prefix , to rename)
tmux rename-window -t 1 editor
```

Navigate: `prefix w` (interactive list), `prefix n`/`p` (next/prev), `prefix 0-9`
(by index), `prefix l` (last). Name windows after their role; a named window is
findable in `prefix w` and targetable by name (`myproj:logs`).

## Panes and layouts

```bash
tmux split-window -h                # prefix %  — side-by-side (left|right)
tmux split-window -v                # prefix "  — stacked (top/bottom)
tmux select-pane -t %53             # focus by pane-id
```

- Navigate: `prefix` + arrow keys; `prefix o` cycles; `prefix q` shows pane numbers.
- Resize: `prefix Ctrl-arrow` (repeatable), or `tmux resize-pane -t %53 -x 120 -y 40`.
- **Zoom**: `prefix z` toggles the current pane full-window — the fastest way to read a
  cramped pane; zoom back out rather than re-splitting.
- Presets: `prefix space` cycles built-in layouts (`even-horizontal`, `main-vertical`,
  `tiled`, …); `tmux select-layout main-vertical` sets one directly.
- Break a pane out to its own window: `prefix !`; join it back:
  `tmux join-pane -s <src-pane> -t <dst-window>`.

A classic dev layout — editor on the left, server and logs stacked on the right:

```bash
tmux new -d -s myproj -n main
tmux split-window -h -t myproj:main            # right column
tmux split-window -v -t myproj:main.1          # split the right column
tmux send-keys -t myproj:main.1 'npm run dev' Enter
tmux send-keys -t myproj:main.2 'tail -f logs/app.log' Enter
tmux attach -t myproj
```

Keep splits ≥80 columns for anything that wraps code; prefer zoom over ever-smaller
splits.

## Copy-mode and scrollback

Enter copy-mode with `prefix [` — the pane freezes and you can navigate history:

- Move: arrows / `PgUp` / vi keys (with `setw -g mode-keys vi`); `g`/`G` top/bottom.
- Search: `/` forward, `?` backward, `n`/`N` repeat.
- Select + copy: `Space` start selection, `Enter` copy; paste with `prefix ]`.
- Leave with `q`.

Capture scrollback non-interactively (the scripting equivalent):

```bash
tmux capture-pane -t myproj:main.1 -p            # visible screen to stdout
tmux capture-pane -t myproj:main.1 -p -S -1000   # last 1000 lines of history
tmux capture-pane -t myproj:main.1 -p -S - > full.log   # entire history
```

Scrollback depth is `history-limit` (default 2000 lines), set **before** a pane is
created: `set -g history-limit 50000` in `~/.tmux.conf`. Output older than the limit is
gone — capture early for long-running processes, or log continuously with
`tmux pipe-pane -t <pane> -o 'cat >> ~/pane.log'`.

## Raw scripting primitives

These are the building blocks other tooling (notably the `tmux-agent` plugin) composes.
Documented once here.

**send-keys** — type into a pane from outside:

```bash
tmux send-keys -t %53 -l -- 'echo hello'   # -l = literal (no key-name lookup); -- guards leading dashes
sleep 0.3                                  # let a TUI register the typing burst
tmux send-keys -t %53 Enter                # Enter as its OWN event — bundling it with the
                                           # text can fail to submit in TUIs
tmux send-keys -t %53 Escape               # named keys: Escape, C-c, Up, PgDn, …
```

**capture-pane** — read a pane from outside (see scrollback section above): `-p` to
stdout, `-S -N` for history depth. Capture a baseline before an action and compare
afterward to see what changed.

**Pane user options** — attach your own metadata to a pane; this is how scripts tag
panes they own so they can find them again reliably:

```bash
tmux set-option -p -t %53 @my_marker "value"     # stamp
tmux display -p -t %53 '#{@my_marker}'           # read
tmux list-panes -a -F '#{pane_id} #{@my_marker}' # enumerate server-wide and filter
```

**Liveness** — `tmux display -p -t %53 '#{pane_dead}'` (needs `remain-on-exit on` to
observe a dead pane; otherwise the pane closes with its process). `remain-on-exit
failed` keeps a pane only when its process crashed — scrollback preserved for diagnosis.

**Naming hygiene** — scripts that create windows/panes should use a predictable,
greppable convention (`<tool>-<token>` window names, `@<tool>_<token>` pane markers) so
"mine" is distinguishable from a human's windows; never assume index positions. The
`tmux-agent` skill defines the full identity contract on top of these primitives.

## Quick reference

| Action | Key / command |
|---|---|
| New session / attach / detach | `tmux new -s X` / `tmux attach -t X` / `prefix d` |
| New window / rename / list | `prefix c` / `prefix ,` / `prefix w` |
| Split side-by-side / stacked | `prefix %` / `prefix "` |
| Move between panes | `prefix` + arrows |
| Zoom pane | `prefix z` |
| Cycle layouts | `prefix space` |
| Copy-mode (scroll/search) | `prefix [` … `q` |
| Paste | `prefix ]` |
| Kill pane / window | `prefix x` / `prefix &` (both confirm) |

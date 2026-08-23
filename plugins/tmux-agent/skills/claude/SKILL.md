---
name: claude
description: This skill should be used when the user asks to spawn, drive, or collaborate with a Claude Code CLI instance as a tmux pane co-worker — "spawn a claude pane", "another claude for X", "a second claude", "a claude worker/instance beside you", "drive claude in a pane", "have claude do/review X in a/its pane", or pairing a claude implementer with a codex reviewer. Do NOT trigger when "claude" refers to the current session itself, to Claude the model/product as a discussion topic, or to ordinary requests addressed to the current assistant.
---

# Claude: Claude Code CLI as a Pane Co-Worker

Drive a **second Claude Code CLI** as a visible tmux pane co-worker beside this session
— for parallel implementation work, a second opinion with its own context, or pairing
with other kinds (e.g. a codex reviewer). All generic machinery — co-worker model,
driving verbs, routing judgment, adaptive I/O, isolation rules — is the **`tmux-agent`
skill**; read it first. This page is only the claude-kind calibration facts.

```bash
# Literal absolute path once this skill is loaded via the Skill tool (the braces
# placeholder is substituted; bare $CLAUDE_PLUGIN_ROOT is NOT an exported variable).
# Re-state this line at the top of every Bash call.
ENGINE="${CLAUDE_PLUGIN_ROOT}/scripts/agent-tmux.sh"

$ENGINE --kind claude pane --cwd "$PWD"          # resolve/reuse THE claude co-worker pane
$ENGINE --kind claude prompt --wait -- "Read @spec.md and implement section 2."
$ENGINE --kind claude read --delta
```

## Profile facts (`scripts/profiles/claude.sh`)

| Fact | Value |
|---|---|
| Binary / version floor | `claude`, ≥ 2.0.0 |
| Model default | empty — inherits the user's configured default; pin per spawn with `CC_AGENT_MODEL` (`sonnet`, `opus`, `haiku`, or a full model id) |
| Reasoning effort | none — Claude Code has no effort flag |
| Sandbox mapping | `--read-only` (default) = normal permission mode, every edit approved in the pane; `--full-auto` = `--permission-mode acceptEdits` |
| Idle detection | **No reliable idle marker** — the idle footer is user-configurable (custom statuslines, vim mode). `wait` uses stability + the universal **busy marker `esc to interrupt`** (shown near the input box while a turn runs). |
| First-run gates | Theme picker on the very first launch; per-directory trust prompt — *"Do you trust the files in this folder?"* → send `Enter` to accept |
| Auth gate | run `claude /login` inside the pane |
| Resume (kept shell) | `claude --continue` |
| File include | `@path` in the prompt |

## Claude-specific notes

- **Approvals are visible, on purpose.** In the default read-only mapping every edit
  the co-worker proposes needs an approval *in its pane* — the human beside you can
  approve, or you relay ("approve the pending edit" → the human acts, or spawn with
  `--full-auto` when the user wants it autonomous).
- **A blocked turn looks busy.** An approval or trust prompt keeps `esc to interrupt`
  off-screen but the turn unfinished — if `wait` times out (exit 5), `read` the pane
  and check for a pending question before assuming a hang (`handle-interruption`
  recipe in the `tmux-agent` skill's `references/interaction-recipes.md`).
- **Don't confuse the co-worker with yourself.** All isolation rules apply: the
  co-worker pane carries this session's marker; never drive a claude pane you did not
  create.

## Collaboration example (codex reviewer + claude implementer)

```bash
CODEX="${CLAUDE_PLUGIN_ROOT}/scripts/codex-tmux.sh"   # substituted at skill load, like $ENGINE
$ENGINE --kind claude pane --topic impl --cwd "$PWD"
$CODEX pane --topic review --cwd "$PWD"

$ENGINE --kind claude prompt --topic impl -- "Implement @spec.md section 2; write a summary to /tmp/impl.md, reply DONE."
$CODEX prompt --topic review -- "Review the diff once /tmp/impl.md exists; write findings to /tmp/rev.md, reply DONE."

$ENGINE --kind claude wait --topic impl && $CODEX wait --topic review
# Read /tmp/impl.md and /tmp/rev.md losslessly; relay between panes yourself.
```

One driver per pane, always — full collaboration recipes and the adaptive I/O rules are
in the `tmux-agent` skill.

#!/usr/bin/env bash
# Mock codex TUI whose idle prompt line carries an animated braille-dot
# background (U+2800–U+28FF), as codex 0.155 draws after a finished turn:
# the raw pane never settles, only the braille glyphs change.
frames=( '⡀ ⠈ ⠁' '⠈ ⠁ ⡀' '⠁ ⡀ ⠈' )
i=0
while :; do
    clear
    echo "mock-codex braille"
    echo "• DONE"
    echo "  done 8:44 PM"
    printf '› Ask Codex to do anything%s\n' "${frames[i]}"
    echo "  gpt-5.6-sol xhigh · /mock-cwd · thread title"
    i=$(( (i + 1) % 3 ))
    sleep 0.2
done

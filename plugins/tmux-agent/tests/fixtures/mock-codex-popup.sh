#!/usr/bin/env bash
# Mock codex TUI with a `$mention` completion popup: once the typed input
# contains `$`, a "Press enter to insert or esc to close" popup replaces the
# footer and swallows Enter until Escape dismisses it (codex 0.155 behavior).
stty -icanon -echo 2>/dev/null
buf="" hist="" popup=0 dismissed=0
draw() {
    clear
    printf '%s' "$hist"
    printf '› %s\n' "$buf"
    if (( popup )); then echo "  Press enter to insert or esc to close"
    else echo "  gpt-5.6-sol xhigh · /mock-cwd"; fi
}
draw
while IFS= read -rsn1 c; do
    case "$c" in
        $'\e') popup=0; dismissed=1 ;;
        '') if (( ! popup )); then
                hist+="› $buf"$'\n'"[mock-response] you said: $buf"$'\n'
                buf="" dismissed=0
            fi ;;
        *) buf+="$c"
           [[ "$buf" == *'$'* ]] && (( ! dismissed )) && popup=1 ;;
    esac
    draw
done

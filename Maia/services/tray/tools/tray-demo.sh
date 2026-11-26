#!/bin/bash
# A set of pretend applications with tray icons in the current session (fake-tray-item.py), for
# trying a shell's tray by hand. Each one prints what the tray does to it, with its name in front,
# and takes commands through its own pipe:
#
#   tray-demo.sh                 # five icons: active, needing attention, pixels, passive ones
#   tray-demo.sh 8               # and three more, for "+N" and a full taskbar
#
#   tray-demo.sh send chat status NeedsAttention
#   tray-demo.sh send music status Active
#   tray-demo.sh send chat menu "Show,-,Quit"
#
# Ctrl+C ends all of them; their icons go from the tray.
set -u
TOOLS=$(cd "$(dirname "$0")" && pwd)
PIPES="${XDG_RUNTIME_DIR:-/tmp}/maia-tray-demo"

if [ "${1:-}" = "send" ]; then
    name=$2; shift 2
    [ -p "$PIPES/$name" ] || { echo "no demo icon \"$name\" (running: $(ls "$PIPES" 2>/dev/null | tr '\n' ' '))" >&2; exit 1; }
    echo "$*" > "$PIPES/$name"
    exit 0
fi

COUNT=${1:-5}
# Nothing of Maia's own session goes to these programs
for v in $(env | grep -o '^MAIA_[A-Z_]*'); do unset "$v"; done
mkdir -p "$PIPES"
PIDS=()
cleanup() {
    for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
    rm -rf "$PIPES"
}
trap cleanup EXIT INT TERM

# name, then the arguments of fake-tray-item.py
start() {
    local name=$1; shift
    rm -f "$PIPES/$name"; mkfifo "$PIPES/$name"
    # The pipe stays open (a writer that never writes): one "send" does not end the program
    ( exec 3<>"$PIPES/$name"; exec python3 "$TOOLS/fake-tray-item.py" "$@" <&3 ) 2>&1 | sed -u "s/^/[$name] /" &
    PIDS+=($!)
    sleep 0.2
}

start chat --title "Chat" --icon internet-chat --tooltip "2 new messages" \
    --menu "Show Chat,-,Status>(o)Online|( )Away|( )Busy,[x]Sounds,!Offline mode,-,Quit"
start mail --title "Mail" --icon mail-unread --status NeedsAttention --tooltip "Inbox: 5 unread" --menu "Check mail,Compose,-,Quit"
start orange --title "Orange (pixels)" --pixmap ff8800 --menu "Show,-,Quit"
start music --title "Music" --icon media-playback-start --status Passive --menu "Play,Next,-,Quit"
start backup --title "Backup" --icon folder-sync --status Passive --item-is-menu --menu "Back up now,Settings…,-,Quit"
extra=("network:network-wireless" "weather:weather-clear" "vpn:network-vpn" "updates:system-software-update" "printer:printer")
for ((i = 5; i < COUNT && i - 5 < ${#extra[@]}; i++)); do
    entry=${extra[$((i - 5))]}
    start "${entry%%:*}" --title "${entry%%:*}" --icon "${entry#*:}"
done

echo "--- ${#PIDS[@]} icons in the tray; commands: $0 send <name> <command>; Ctrl+C ends them ---"
wait

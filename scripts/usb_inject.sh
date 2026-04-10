#!/usr/bin/env bash
# =============================================================================
# usb_inject.sh — USB HID keyboard injection helper
#
# Requires: the kernel was built with CONFIG_USB_CONFIGFS_F_HID=y (or =m)
#           and the gadget has been configured (see README § USB HID Gadget)
#
# Usage:
#   bash scripts/usb_inject.sh "Hello, World!"
#   bash scripts/usb_inject.sh -f /path/to/payload.txt
#
# The script writes HID keyboard scan-code reports to /dev/hidg0.
# =============================================================================

set -euo pipefail

HIDG=/dev/hidg0

usage() {
    echo "Usage: $0 [-f file] [\"string to type\"]"
    echo "  -f FILE   Read keystrokes from file (one character per line)"
    exit 1
}

# HID key code lookup table (US QWERTY)
declare -A KEY_MAP=(
    ['a']='0x04' ['b']='0x05' ['c']='0x06' ['d']='0x07' ['e']='0x08'
    ['f']='0x09' ['g']='0x0a' ['h']='0x0b' ['i']='0x0c' ['j']='0x0d'
    ['k']='0x0e' ['l']='0x0f' ['m']='0x10' ['n']='0x11' ['o']='0x12'
    ['p']='0x13' ['q']='0x14' ['r']='0x15' ['s']='0x16' ['t']='0x17'
    ['u']='0x18' ['v']='0x19' ['w']='0x1a' ['x']='0x1b' ['y']='0x1c'
    ['z']='0x1d' [' ']='0x2c' ['\n']='0x28' ['\t']='0x2b'
    ['1']='0x1e' ['2']='0x1f' ['3']='0x20' ['4']='0x21' ['5']='0x22'
    ['6']='0x23' ['7']='0x24' ['8']='0x25' ['9']='0x26' ['0']='0x27'
    ['-']='0x2d' ['=']='0x2e' ['[']='0x2f' [']']='0x30' ['\\']='0x31'
    [';']='0x33' ["'"]='0x34' ['`']='0x35' [',']='0x36' ['.']='0x37'
    ['/']='0x38'
)

# Characters that require Shift modifier (modifier byte = 0x02)
SHIFT_CHARS="ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#\$%^&*()_+{}|:\"<>?"

send_key() {
    local modifier="$1"   # 0x00 = none, 0x02 = left shift
    local keycode="$2"    # 0x00 = key up

    # HID keyboard report: modifier, reserved, key[1..6]
    printf "\\x${modifier#0x}\\x00\\x${keycode#0x}\\x00\\x00\\x00\\x00\\x00" > "$HIDG"
    # Key release
    printf "\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00" > "$HIDG"
    sleep 0.02
}

type_string() {
    local text="$1"
    local i char lower modifier keycode

    for (( i=0; i<${#text}; i++ )); do
        char="${text:$i:1}"

        # Determine if shift is needed
        if [[ "$SHIFT_CHARS" == *"$char"* ]]; then
            modifier="02"
            lower="${char,,}"   # lowercase to look up keycode
        else
            modifier="00"
            lower="$char"
        fi

        keycode="${KEY_MAP[$lower]:-}"
        if [[ -z "$keycode" ]]; then
            warn "No keycode for character: '$char' — skipping"
            continue
        fi

        send_key "0x$modifier" "$keycode"
    done
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }

[[ -c "$HIDG" ]] || { echo "Error: $HIDG not found. Is the HID gadget configured?"; exit 1; }
[[ $(id -u) -eq 0 ]] || { echo "Error: must run as root (su / Magisk)"; exit 1; }

if [[ "${1:-}" == "-f" ]]; then
    [[ -f "${2:-}" ]] || usage
    while IFS= read -r line; do
        type_string "$line"
        send_key "0x00" "0x28"   # Enter after each line
    done < "$2"
elif [[ -n "${1:-}" ]]; then
    type_string "$1"
else
    usage
fi

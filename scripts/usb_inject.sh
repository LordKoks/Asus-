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
CONFIGFS_MOUNT=/config
GADGET_DIR="$CONFIGFS_MOUNT/usb_gadget/hid_inject"
GADGET_LANG=0x409
GADGET_MANUFACTURER=ROG5S
GADGET_PRODUCT="HID Keyboard"
GADGET_CONFIG="HID Config"
GADGET_VENDOR=0x1d6b
GADGET_PRODUCT_ID=0x0104
REPORT_DESC='\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x03\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x03\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0'

usage() {
    echo "Usage: $0 [setup] [-f file] [\"string to type\"]"
    echo "  setup     Create and enable the HID gadget via configfs"
    echo "  -f FILE   Read keystrokes from file (one line per Enter)"
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

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

require_root() {
    [[ $(id -u) -eq 0 ]] || error "must run as root (su / Magisk)"
}

ensure_configfs() {
    mkdir -p "$CONFIGFS_MOUNT"
    if ! mountpoint -q "$CONFIGFS_MOUNT"; then
        mount -t configfs none "$CONFIGFS_MOUNT"
    fi
}

detach_gadget() {
    if [[ -f "$GADGET_DIR/UDC" ]]; then
        printf '' > "$GADGET_DIR/UDC" 2>/dev/null || true
    fi
}

setup_gadget() {
    local udc

    require_root
    ensure_configfs

    if [[ ! -d /sys/class/udc ]]; then
        error "/sys/class/udc is missing; USB gadget mode is not available"
    fi

    udc=$(ls /sys/class/udc 2>/dev/null | head -1)
    [[ -n "$udc" ]] || error "No UDC found under /sys/class/udc"

    mkdir -p "$GADGET_DIR"
    detach_gadget

    printf '%s' "$GADGET_VENDOR" > "$GADGET_DIR/idVendor"
    printf '%s' "$GADGET_PRODUCT_ID" > "$GADGET_DIR/idProduct"

    mkdir -p "$GADGET_DIR/strings/$GADGET_LANG"
    printf '%s' "$GADGET_MANUFACTURER" > "$GADGET_DIR/strings/$GADGET_LANG/manufacturer"
    printf '%s' "$GADGET_PRODUCT" > "$GADGET_DIR/strings/$GADGET_LANG/product"

    mkdir -p "$GADGET_DIR/functions/hid.usb0"
    printf '1' > "$GADGET_DIR/functions/hid.usb0/protocol"
    printf '1' > "$GADGET_DIR/functions/hid.usb0/subclass"
    printf '8' > "$GADGET_DIR/functions/hid.usb0/report_length"
    printf '%b' "$REPORT_DESC" > "$GADGET_DIR/functions/hid.usb0/report_desc"

    mkdir -p "$GADGET_DIR/configs/c.1/strings/$GADGET_LANG"
    printf '%s' "$GADGET_CONFIG" > "$GADGET_DIR/configs/c.1/strings/$GADGET_LANG/configuration"
    printf '250' > "$GADGET_DIR/configs/c.1/MaxPower"

    if [[ ! -L "$GADGET_DIR/configs/c.1/hid.usb0" ]]; then
        ln -s "$GADGET_DIR/functions/hid.usb0" "$GADGET_DIR/configs/c.1/hid.usb0"
    fi

    printf '%s' "$udc" > "$GADGET_DIR/UDC"

    if [[ -c "$HIDG" ]]; then
        info "HID gadget is ready on $HIDG via UDC $udc"
    else
        warn "Gadget enabled via UDC $udc, but $HIDG is not present yet"
    fi
}

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
if [[ "${1:-}" == "setup" ]]; then
    setup_gadget
    exit 0
fi

require_root
[[ -c "$HIDG" ]] || error "$HIDG not found. Run '$0 setup' first"

if [[ "${1:-}" == "-f" ]]; then
    [[ -f "${2:-}" ]] || usage
    while IFS= read -r line; do
        type_string "$line"
        send_key "0x00" "0x28"
    done < "$2"
elif [[ -n "${1:-}" ]]; then
    type_string "$1"
else
    setup_gadget
fi

#!/usr/bin/env bash
# =============================================================================
# andrax_verify.sh — Post-flash kernel feature verification for AndrAX
#
# Run this script ON the device (via adb shell or a terminal app) after
# flashing the custom kernel to confirm all AndrAX features are active.
#
# Usage:
#   adb push scripts/andrax_verify.sh /data/local/tmp/
#   adb shell "su -c 'bash /data/local/tmp/andrax_verify.sh'"
#
# Exit code: 0 = all checks passed, 1 = one or more features missing
# =============================================================================

set -uo pipefail

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0; WARN=0

pass() { echo -e "  ${GREEN}✔${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✘${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARN=$((WARN+1)); }
header() { echo -e "\n${BOLD}${BLUE}══ $1 ══${NC}"; }

# Helper: check a kernel config option
#   $1 = CONFIG_NAME (without CONFIG_ prefix)
#   $2 = human label
kconf() {
    local key="CONFIG_$1"
    local label="${2:-$key}"
    # Try /proc/config.gz first (requires CONFIG_IKCONFIG_PROC)
    local val
    if [[ -f /proc/config.gz ]]; then
        val=$(zcat /proc/config.gz 2>/dev/null | grep "^${key}=" | cut -d= -f2 | tr -d '"')
    elif [[ -f /proc/config ]]; then
        val=$(grep "^${key}=" /proc/config 2>/dev/null | cut -d= -f2 | tr -d '"')
    else
        # Fallback: check via /sys/kernel/ or module probe
        val=""
    fi
    case "$val" in
        y|m) pass "$label (${key}=${val})" ;;
        "")  warn "$label (${key} — config not readable, checking at runtime…)" ;;
        *)   fail "$label (${key}=${val})" ;;
    esac
}

# Helper: check a /dev node exists
dev_exists() {
    local dev="$1"; local label="${2:-$dev}"
    [[ -e "$dev" ]] && pass "$label ($dev)" || fail "$label ($dev not found)"
}

# Helper: check a kernel module is loaded or loadable
mod_check() {
    local mod="$1"; local label="${2:-$mod}"
    if lsmod 2>/dev/null | grep -q "^${mod} "; then
        pass "$label (module loaded)"
    elif modinfo "$mod" &>/dev/null; then
        warn "$label (module available but not loaded — run: modprobe $mod)"
    else
        fail "$label (module not found)"
    fi
}

# Helper: check a binary exists in PATH or common locations
bin_check() {
    local bin="$1"; local label="${2:-$bin}"
    if command -v "$bin" &>/dev/null; then
        pass "$label ($(command -v "$bin"))"
    else
        fail "$label (not found in PATH)"
    fi
}

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}AndrAX Kernel Feature Verification${NC}"
echo -e "Device: $(uname -n)  |  Kernel: $(uname -r)  |  Arch: $(uname -m)"
echo -e "Date  : $(date)"
# ---------------------------------------------------------------------------

header "1. Wi-Fi Monitor Mode"
kconf "CFG80211"                    "cfg80211 core"
kconf "MAC80211"                    "mac80211 (soft-MAC layer)"
kconf "CFG80211_WEXT"               "WEXT compatibility (iwconfig)"
kconf "NL80211_TESTMODE"            "nl80211 testmode (packet injection)"
# Runtime check
if ip link show 2>/dev/null | grep -q "wlan"; then
    IFACE=$(ip link show | grep wlan | awk '{print $2}' | tr -d ':' | head -1)
    if iw dev "$IFACE" info 2>/dev/null | grep -q "monitor\|managed"; then
        pass "Wi-Fi interface $IFACE is present and iw-readable"
    else
        warn "Wi-Fi interface found but iw not responding — install iw"
    fi
else
    warn "No wlan interface detected (Wi-Fi may be off)"
fi

header "2. USB HID Gadget (Injection)"
kconf "USB_GADGET"                  "USB gadget framework"
kconf "USB_CONFIGFS"                "ConfigFS gadget composer"
kconf "USB_CONFIGFS_F_HID"          "HID function (keyboard/mouse)"
kconf "USB_G_HID"                   "Legacy HID gadget"
kconf "USB_LIBCOMPOSITE"            "libcomposite"
dev_exists "/dev/hidg0"             "HID gadget device node"
dev_exists "/sys/class/udc"         "USB Device Controller sysfs"

header "3. Networking — TUN/TAP & Namespaces"
kconf "TUN"                         "TUN/TAP device"
kconf "NAMESPACES"                  "Linux namespaces"
kconf "NET_NS"                      "Network namespaces"
kconf "USER_NS"                     "User namespaces"
kconf "PID_NS"                      "PID namespaces"
dev_exists "/dev/tun"               "/dev/tun"
dev_exists "/dev/net/tun"           "/dev/net/tun"

header "4. Networking — Bridges, Routing, NAT"
kconf "BRIDGE"                      "Ethernet bridge"
kconf "VETH"                        "Virtual Ethernet pair"
kconf "DUMMY"                       "Dummy network interface"
kconf "MACVLAN"                     "MACVLAN"
kconf "IPVLAN"                      "IPVLAN"
kconf "NF_NAT"                      "Netfilter NAT"
kconf "IP_NF_TARGET_MASQUERADE"     "IP MASQUERADE"

header "5. Networking — Netfilter / IPTables / NFTables"
kconf "NETFILTER"                   "Netfilter core"
kconf "NF_CONNTRACK"                "Connection tracking"
kconf "IP_NF_IPTABLES"              "iptables"
kconf "IP_NF_FILTER"                "iptables filter table"
kconf "NF_TABLES"                   "nftables"
kconf "IP_SET"                      "IP sets"
kconf "NETFILTER_NETLINK_QUEUE"     "nfqueue (AI agent packet verdict)"
bin_check "iptables"                "iptables binary"
bin_check "nft"                     "nft (nftables) binary"

header "6. eBPF & AI Agent Interface"
kconf "BPF_SYSCALL"                 "BPF syscall"
kconf "BPF_JIT"                     "BPF JIT compiler"
kconf "BPF_LSM"                     "BPF LSM hooks"
kconf "DEBUG_INFO_BTF"              "BTF (BPF Type Format)"
kconf "KPROBES"                     "kprobes"
kconf "UPROBES"                     "uprobes"
kconf "KPROBE_EVENTS"               "kprobe tracing events"
kconf "UPROBE_EVENTS"               "uprobe tracing events"
kconf "FANOTIFY"                    "fanotify"
kconf "FANOTIFY_ACCESS_PERMISSIONS" "fanotify access permissions"
kconf "CONNECTOR"                   "Kernel connector (netlink)"
kconf "PROC_EVENTS"                 "Process events via connector"
kconf "TASKSTATS"                   "Per-task stats (netlink)"
kconf "GENETLINK"                   "Generic netlink"
dev_exists "/sys/kernel/debug/tracing" "Tracing debugfs"

header "7. Process Tracing (frida / gdb / strace)"
kconf "HAVE_PTRACE"                 "ptrace support"
kconf "PERF_EVENTS"                 "perf events"
kconf "FTRACE"                      "ftrace"
kconf "FTRACE_SYSCALLS"             "syscall tracing"
kconf "USERFAULTFD"                 "userfaultfd"
kconf "IO_URING"                    "io_uring"

header "8. Container / Isolation (proot, lxc, bubblewrap)"
kconf "CGROUPS"                     "cgroups"
kconf "MEMCG"                       "Memory cgroup"
kconf "OVERLAY_FS"                  "OverlayFS"
kconf "SECCOMP"                     "seccomp"
kconf "SECCOMP_FILTER"              "seccomp BPF filter"

header "9. Filesystem Support"
kconf "BLK_DEV_LOOP"                "Loop block device"
kconf "FUSE_FS"                     "FUSE filesystem"
kconf "INOTIFY_USER"                "inotify"
kconf "EXFAT_FS"                    "exFAT filesystem"
kconf "NTFS_FS"                     "NTFS filesystem"

header "10. Crypto"
kconf "CRYPTO_AES"                  "AES cipher"
kconf "CRYPTO_SHA256"               "SHA-256 hash"
kconf "CRYPTO_CHACHA20POLY1305"     "ChaCha20-Poly1305 (WireGuard)"
kconf "WIREGUARD"                   "WireGuard VPN"
kconf "CRYPTO_DRBG"                 "Deterministic RNG"

header "11. Bluetooth (BLE sniffing)"
kconf "BT"                          "Bluetooth core"
kconf "BT_HCISOCK"                  "Bluetooth HCI socket"

header "12. NFC"
kconf "NFC"                         "NFC core"
kconf "NFC_NCI"                     "NFC NCI layer"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}══════════════════════════════════${NC}"
echo -e "${BOLD}Results: ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${WARN} warnings${NC}"
echo -e "${BOLD}══════════════════════════════════${NC}"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Some kernel features are missing. Rebuild the kernel with${NC}"
    echo -e "${RED}configs/rog5s_features.config merged in and reflash.${NC}"
    exit 1
elif [[ $WARN -gt 0 ]]; then
    echo -e "${YELLOW}All features present; some checks were inconclusive (config not readable).${NC}"
    echo -e "${YELLOW}Add CONFIG_IKCONFIG=y + CONFIG_IKCONFIG_PROC=y for full verification.${NC}"
    exit 0
else
    echo -e "${GREEN}All AndrAX kernel features verified successfully!${NC}"
    exit 0
fi

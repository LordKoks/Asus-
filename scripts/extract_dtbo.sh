#!/usr/bin/env bash
# =============================================================================
# extract_dtbo.sh — Extract dtbo.img from an OTA payload and convert to DTS
#
# Extracts the DTBO (Device Tree Blob Overlay) partition from an ASUS OTA zip
# using payload-dumper-go, then converts the binary blob to a human-readable
# DTS source file using dtc.
#
# The resulting DTS file contains the proprietary hardware parameters
# (voltages, ROG trigger mappings, I2C addresses, etc.) for your specific
# device — information ASUS does not publish in the open-source kernel drop.
#
# Usage:
#   bash scripts/extract_dtbo.sh [firmware.zip] [output.dts]
#
# Defaults:
#   firmware.zip  ~/body.zip
#   output.dts    ~/body_config.dts
#
# Dependencies (auto-installed if missing on Termux / Debian/Ubuntu):
#   Go ≥ 1.18, python3, git, dtc (device-tree-compiler)
#   go install github.com/ssut/payload-dumper-go@latest
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
FIRMWARE_ZIP="${1:-$HOME/body.zip}"
OUTPUT_DTS="${2:-$HOME/body_config.dts}"
EXTRACT_DIR=$(mktemp -d)
trap 'rm -rf "$EXTRACT_DIR"' EXIT

# ---------------------------------------------------------------------------
# Colours / helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

# ---------------------------------------------------------------------------
# 1. Verify firmware archive
# ---------------------------------------------------------------------------
step "1. Firmware archive"
[[ -f "$FIRMWARE_ZIP" ]] || \
    error "Firmware zip not found: $FIRMWARE_ZIP\n       Run: bash scripts/download_firmware.sh first."
info "Firmware : $FIRMWARE_ZIP ($(du -sh "$FIRMWARE_ZIP" | cut -f1))"

# ---------------------------------------------------------------------------
# 2. Ensure dtc (device-tree-compiler) is available
# ---------------------------------------------------------------------------
step "2. Check / install dtc"
if ! command -v dtc &>/dev/null; then
    info "dtc not found — attempting to install …"
    if command -v pkg &>/dev/null; then          # Termux
        pkg install -y dtc
    elif command -v apt-get &>/dev/null; then    # Debian / Ubuntu
        sudo apt-get install -y device-tree-compiler
    else
        error "Cannot install dtc automatically. Install the 'device-tree-compiler' package manually."
    fi
fi
info "dtc version: $(dtc --version 2>&1 | head -1)"

# ---------------------------------------------------------------------------
# 3. Ensure payload-dumper-go is available
# ---------------------------------------------------------------------------
step "3. Check / install payload-dumper-go"
DUMPER_BIN="${GOPATH:-$HOME/go}/bin/payload-dumper-go"

if [[ ! -x "$DUMPER_BIN" ]]; then
    info "payload-dumper-go not found — installing via 'go install' …"
    if ! command -v go &>/dev/null; then
        info "Go not found — attempting to install …"
        if command -v pkg &>/dev/null; then      # Termux
            pkg install -y golang
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y golang-go
        else
            error "Go is required but could not be installed automatically."
        fi
    fi
    go install github.com/ssut/payload-dumper-go@latest
fi
info "payload-dumper-go: $DUMPER_BIN"

# ---------------------------------------------------------------------------
# 4. Extract dtbo partition from payload.bin
# ---------------------------------------------------------------------------
step "4. Extracting dtbo partition"
info "Output directory : $EXTRACT_DIR"
"$DUMPER_BIN" -p dtbo -o "$EXTRACT_DIR" "$FIRMWARE_ZIP"

# payload-dumper-go creates a sub-directory named after the zip contents
DTBO_IMG=$(find "$EXTRACT_DIR" -name "dtbo.img" | head -1)
[[ -n "$DTBO_IMG" ]] || error "dtbo.img not found after extraction — check the firmware zip."
info "Extracted dtbo.img: $DTBO_IMG ($(du -sh "$DTBO_IMG" | cut -f1))"

# ---------------------------------------------------------------------------
# 5. Convert binary DTBO to human-readable DTS
# ---------------------------------------------------------------------------
step "5. Converting dtbo.img → DTS"
dtc -I dtb -O dts -o "$OUTPUT_DTS" "$DTBO_IMG" 2>/dev/null || \
    dtc -I dtb -O dts -f -o "$OUTPUT_DTS" "$DTBO_IMG" || \
    error "dtc conversion failed. The image may be a multi-blob DTBO; try splitting it first."

info "DTS written : $OUTPUT_DTS ($(wc -l < "$OUTPUT_DTS") lines)"

# Quick sanity — look for expected ROG / I005 identifiers
if grep -qiE "I005|rog|ZS67[36]KS" "$OUTPUT_DTS"; then
    info "DTS content looks correct — ROG Phone identifiers found ✔"
else
    warn "Expected device identifiers not found in DTS. Verify the firmware source."
fi

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}✅ DTBO extraction complete${NC}"
echo ""
echo -e "  Firmware  : $FIRMWARE_ZIP"
echo -e "  dtbo.img  : $DTBO_IMG"
echo -e "  DTS file  : ${BOLD}$OUTPUT_DTS${NC}"
echo ""
echo -e "You can inspect the hardware parameters with:"
echo -e "  grep -i 'voltage\\|trigger\\|gpio\\|i2c\\|I005' $OUTPUT_DTS | head -40"
echo ""
echo -e "Next steps:"
echo -e "  1. Review $OUTPUT_DTS to extract proprietary hardware parameters."
echo -e "  2. Download the kernel source: bash scripts/download_kernel_src.sh"
echo -e "  3. Build the kernel:           bash scripts/clang_build_kernel.sh"
echo ""

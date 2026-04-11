#!/usr/bin/env bash
# =============================================================================
# download_firmware.sh — Download the official ASUS OTA firmware package
#
# Downloads the full OTA zip (body) for ROG Phone 5 / 5S firmware
# WW_33.0210.0210.200.  The archive contains payload.bin from which
# partition images (boot, dtbo, vendor, …) can be extracted.
#
# Usage:
#   bash scripts/download_firmware.sh [output-file]
#
# Default output file: ~/body.zip
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEST_FILE="${1:-$HOME/body.zip}"
FIRMWARE_URL="https://dlcdnets.asus.com/pub/ASUS/ZenFone/ZS673KS/UL-ASUS_I005_1-ASUS-33.0210.0210.200-1.1.300-2304-user.zip"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
command -v wget &>/dev/null || error "wget not found. Install it first."

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

if [[ -f "$DEST_FILE" ]]; then
    info "Firmware archive already exists at $DEST_FILE"
    info "Resuming download (if incomplete) …"
fi

echo -e "\n${BOLD}${CYAN}ASUS ROG Phone 5S — OTA Firmware Download${NC}\n"
echo -e "  Firmware : WW_33.0210.0210.200"
echo -e "  Android  : 13 (security patch April 2023)"
echo -e "  Device   : ROG Phone 5 (ZS673KS) / ROG Phone 5S (ZS676KS)"
echo -e "  Output   : $DEST_FILE"
echo -e "  Size     : ~4 GB"
echo ""
warn "This is a large download. Use -c to resume if interrupted."
echo ""

# -c enables resume; progress bar kept visible
wget -c --progress=bar:force:noscroll \
    -O "$DEST_FILE" \
    "$FIRMWARE_URL" || error "Download failed. Check your internet connection."

info "Download complete: $(du -sh "$DEST_FILE" | cut -f1)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}✅ Firmware ready at: $DEST_FILE${NC}"
echo ""
echo -e "Next steps:"
echo -e "  Extract partition images:"
echo -e "    bash scripts/extract_dtbo.sh $DEST_FILE"
echo ""

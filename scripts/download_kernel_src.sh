#!/usr/bin/env bash
# =============================================================================
# download_kernel_src.sh — Download and extract the official ASUS kernel source
#
# Downloads the open-source kernel release for ROG Phone 5 / 5S (SM8350)
# directly from the ASUS download server.
#
# Usage:
#   bash scripts/download_kernel_src.sh [output-directory]
#
# Default output directory: ~/rog5s-kernel
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEST_DIR="${1:-$HOME/rog5s-kernel}"
ARCHIVE_NAME="ASUS_I005_1-33.0210.0210.200-kernel-src.tar.gz"
DOWNLOAD_URL="https://dlcdnets.asus.com/pub/ASUS/ZenFone/ZS673KS/${ARCHIVE_NAME}"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
for cmd in wget tar; do
    command -v "$cmd" &>/dev/null || error "Required tool not found: $cmd"
done

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_PATH="$TMP_DIR/$ARCHIVE_NAME"

if [[ -f "$DEST_DIR/Makefile" ]]; then
    info "Kernel source already exists at $DEST_DIR"
    info "To re-download, remove the directory first: rm -rf $DEST_DIR"
    exit 0
fi

echo -e "\n${BOLD}${CYAN}ASUS ROG Phone 5S — Kernel Source Download${NC}\n"
echo -e "  Source  : ASUS official kernel-src release"
echo -e "  Version : 33.0210.0210.200 (Linux 5.4, SM8350)"
echo -e "  Device  : ROG Phone 5 (ZS673KS) / ROG Phone 5S (ZS676KS)"
echo -e "  Size    : ~450 MB"
echo ""

info "Downloading kernel source archive …"
wget --progress=bar:force:noscroll \
    -O "$ARCHIVE_PATH" \
    "$DOWNLOAD_URL" || error "Download failed. Check your internet connection."

info "Download complete: $(du -sh "$ARCHIVE_PATH" | cut -f1)"

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------
info "Extracting to $DEST_DIR …"
mkdir -p "$DEST_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$DEST_DIR" --strip-components=1

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
if [[ -f "$DEST_DIR/Makefile" ]]; then
    KVER=$(grep "^VERSION = " "$DEST_DIR/Makefile" | awk '{print $3}')
    KPATCH=$(grep "^PATCHLEVEL = " "$DEST_DIR/Makefile" | awk '{print $3}')
    KSUB=$(grep "^SUBLEVEL = " "$DEST_DIR/Makefile" | awk '{print $3}')
    info "Kernel version: ${KVER}.${KPATCH}.${KSUB}"
else
    warn "Makefile not found — the archive layout may differ. Check $DEST_DIR manually."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}✅ Kernel source ready at: $DEST_DIR${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Build with GCC:   bash scripts/build_kernel.sh $DEST_DIR"
echo -e "  2. Build with Clang: bash scripts/clang_build_kernel.sh $DEST_DIR"
echo ""

warn "Firmware compatibility note:"
warn "  This kernel source matches firmware 33.0210.0210.200 (Android 13, April 2023)."
warn "  It is the exact source for device build WW_33.0210.0210.200."

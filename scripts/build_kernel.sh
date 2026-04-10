#!/usr/bin/env bash
# =============================================================================
# build_kernel.sh — ASUS ROG Phone 5S custom kernel build script
#
# Usage:  bash scripts/build_kernel.sh [/path/to/kernel/source]
#
# The script:
#   1. Verifies build dependencies
#   2. Merges the custom config fragment on top of the stock defconfig
#   3. Builds the kernel image and modules
#   4. Produces a flashable AnyKernel3 zip
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

KERNEL_DIR="${1:-$HOME/rog5s-kernel}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FRAGMENT="$REPO_DIR/configs/rog5s_features.config"

ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
DEFCONFIG=vendor/kona-perf_defconfig
OUT_DIR="$KERNEL_DIR/out"
JOBS=$(nproc)

# AnyKernel3 zip output name
TIMESTAMP=$(date +%Y%m%d-%H%M)
KERNEL_ZIP="$REPO_DIR/rog5s-custom-kernel-$TIMESTAMP.zip"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Dependency check
# ---------------------------------------------------------------------------
info "Checking build dependencies …"
MISSING=()
for cmd in make aarch64-linux-gnu-gcc python3 zip; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    error "Missing tools: ${MISSING[*]}. Run: sudo apt install build-essential gcc-aarch64-linux-gnu python3 zip"
fi

# ---------------------------------------------------------------------------
# 2. Kernel source check
# ---------------------------------------------------------------------------
[[ -d "$KERNEL_DIR" ]] || error "Kernel source directory not found: $KERNEL_DIR"
[[ -f "$KERNEL_DIR/Makefile" ]] || error "Not a kernel source tree: $KERNEL_DIR/Makefile missing"
info "Kernel source: $KERNEL_DIR"

# ---------------------------------------------------------------------------
# 3. Generate .config from defconfig + feature fragment
# ---------------------------------------------------------------------------
info "Generating .config from $DEFCONFIG …"
cd "$KERNEL_DIR"
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE "$DEFCONFIG"

info "Merging feature fragment: $CONFIG_FRAGMENT …"
scripts/kconfig/merge_config.sh .config "$CONFIG_FRAGMENT"
info ".config merge complete."

# ---------------------------------------------------------------------------
# 4. Build
# ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR"

info "Building kernel with -j$JOBS …"
make -j"$JOBS" \
     ARCH=$ARCH \
     CROSS_COMPILE=$CROSS_COMPILE \
     O="$OUT_DIR" \
     Image.gz-dtb dtbs modules

info "Installing kernel modules …"
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE \
     O="$OUT_DIR" \
     INSTALL_MOD_PATH="$OUT_DIR/modules" \
     modules_install

# ---------------------------------------------------------------------------
# 5. Package into AnyKernel3 zip
# ---------------------------------------------------------------------------
info "Packaging kernel zip …"

AK3_DIR=$(mktemp -d)
trap 'rm -rf "$AK3_DIR"' EXIT

# Minimal AnyKernel3 layout
mkdir -p "$AK3_DIR"/{META-INF/com/google/android,modules}

# Kernel image
cp "$OUT_DIR/arch/$ARCH/boot/Image.gz-dtb" "$AK3_DIR/Image.gz-dtb"

# Loadable modules
find "$OUT_DIR/modules" -name "*.ko" -exec cp {} "$AK3_DIR/modules/" \;

# anykernel.sh
cat > "$AK3_DIR/anykernel.sh" <<'ANYKERNEL'
# AnyKernel3 script — ASUS ROG Phone 5S custom kernel
properties() { '
kernel.string=ROG5S-Custom (WiFi-Monitor + USB-HID + AndrAX)
do.devicecheck=1
do.modules=1
do.systemless=1
do.cleanup=1
device.name1=ZS676KS
device.name2=I005D
'; }
block=/dev/block/by-name/boot
is_slot_device=0
ramdisk_compression=auto

. tools/ak3-core.sh
. $AKHOME/patch.d-env

split_boot
flash_boot
ANYKERNEL

# update-binary (minimal stub)
mkdir -p "$AK3_DIR/META-INF/com/google/android"
cat > "$AK3_DIR/META-INF/com/google/android/update-binary" <<'UPDBINARY'
#!/sbin/sh
SKIPUNZIP=1
ash $ZIPFILE anykernel.sh install
UPDBINARY

echo "true" > "$AK3_DIR/META-INF/com/google/android/updater-script"

# Create zip
(cd "$AK3_DIR" && zip -r9 "$KERNEL_ZIP" . > /dev/null)
info "Flashable zip: $KERNEL_ZIP"

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
echo ""
info "===== Build complete ====="
echo "  Kernel image : $OUT_DIR/arch/$ARCH/boot/Image.gz-dtb"
echo "  Modules      : $OUT_DIR/modules/"
echo "  Flashable zip: $KERNEL_ZIP"
echo ""
warn "Flash via TWRP or: adb sideload $KERNEL_ZIP"

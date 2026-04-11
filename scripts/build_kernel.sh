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
AK3_REPO=https://github.com/osm0sis/AnyKernel3
MODULES_ENABLED=0
IMAGE_TARGET=Image.gz-dtb
IMAGE_OUTPUT_PATH=

choose_defconfig() {
    local candidates=(
        "vendor/kona-perf_defconfig"
        "vendor/ZS673KS-perf_defconfig"
        "vendor/ZS673KS_defconfig"
    )
    local cfg

    for cfg in "${candidates[@]}"; do
        if [[ -f "$KERNEL_DIR/arch/arm64/configs/$cfg" ]]; then
            DEFCONFIG="$cfg"
            return 0
        fi
    done

    error "No supported defconfig found. Checked: ${candidates[*]}"
}

choose_image_target() {
    local arm64_mk="$KERNEL_DIR/arch/arm64/Makefile"
    local kbuild_target

    if [[ ! -f "$arm64_mk" ]]; then
        error "Missing arm64 makefile: $arm64_mk"
    fi

    kbuild_target=$(grep -E '^KBUILD_TARGET\s*:=' "$arm64_mk" | awk '{print $3}' | head -1 || true)
    case "$kbuild_target" in
        Image.gz-dtb|Image.gz|Image)
            IMAGE_TARGET="$kbuild_target"
            return 0
            ;;
    esac

    # Conservative fallback for vendor trees without KBUILD_TARGET declaration.
    if grep -q 'Image\.gz-dtb' "$arm64_mk"; then
        IMAGE_TARGET="Image.gz-dtb"
    elif grep -q 'Image\.gz' "$arm64_mk"; then
        IMAGE_TARGET="Image.gz"
    else
        IMAGE_TARGET="Image"
    fi
}

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
choose_defconfig
info "Kernel source: $KERNEL_DIR"
info "Using defconfig: $DEFCONFIG"

# ---------------------------------------------------------------------------
# 3. Generate .config from defconfig + feature fragment
# ---------------------------------------------------------------------------
info "Generating .config from $DEFCONFIG …"
cd "$KERNEL_DIR"
mkdir -p "$OUT_DIR"
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O="$OUT_DIR" "$DEFCONFIG"

info "Merging feature fragment: $CONFIG_FRAGMENT …"
(
    cd "$OUT_DIR"
    KCONFIG_CONFIG=.config "$KERNEL_DIR/scripts/kconfig/merge_config.sh" -m \
        .config "$CONFIG_FRAGMENT"
)
rm -f "$KERNEL_DIR/.config"
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O="$OUT_DIR" olddefconfig
if grep -q '^CONFIG_MODULES=y' "$OUT_DIR/.config"; then
    MODULES_ENABLED=1
fi
choose_image_target
IMAGE_OUTPUT_PATH="$OUT_DIR/arch/$ARCH/boot/$IMAGE_TARGET"
info ".config merge complete."

# ---------------------------------------------------------------------------
# 4. Build
# ---------------------------------------------------------------------------
info "Building kernel with -j$JOBS …"
BUILD_TARGETS=("$IMAGE_TARGET")
if [[ "${ROG5S_BUILD_DTBS:-0}" == "1" ]]; then
    BUILD_TARGETS+=(dtbs)
fi
if [[ "$MODULES_ENABLED" -eq 1 ]]; then
    BUILD_TARGETS+=(modules)
else
    warn "CONFIG_MODULES is disabled; skipping module build"
fi

make -j"$JOBS" \
     ARCH=$ARCH \
     CROSS_COMPILE=$CROSS_COMPILE \
    DISABLE_WRAPPER=1 \
     O="$OUT_DIR" \
     "${BUILD_TARGETS[@]}"

if [[ "$MODULES_ENABLED" -eq 1 ]]; then
    info "Installing kernel modules …"
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE \
         O="$OUT_DIR" \
         INSTALL_MOD_PATH="$OUT_DIR/modules" \
         modules_install
fi

# ---------------------------------------------------------------------------
# 5. Package into AnyKernel3 zip
# ---------------------------------------------------------------------------
info "Packaging kernel zip …"

AK3_DIR=$(mktemp -d)
trap 'rm -rf "$AK3_DIR"' EXIT

git clone --depth=1 "$AK3_REPO" "$AK3_DIR" >/dev/null 2>&1 || \
    error "Failed to clone AnyKernel3 from $AK3_REPO"

# Kernel image
if [[ "$IMAGE_TARGET" == "Image.gz-dtb" && -f "$IMAGE_OUTPUT_PATH" ]]; then
    cp "$IMAGE_OUTPUT_PATH" "$AK3_DIR/Image.gz-dtb"
elif [[ "$IMAGE_TARGET" == "Image.gz" && -f "$IMAGE_OUTPUT_PATH" ]]; then
    cp "$IMAGE_OUTPUT_PATH" "$AK3_DIR/Image.gz"
elif [[ "$IMAGE_TARGET" == "Image" && -f "$IMAGE_OUTPUT_PATH" ]]; then
    cp "$OUT_DIR/arch/$ARCH/boot/Image" "$AK3_DIR/Image"
else
    error "Kernel image not found at $IMAGE_OUTPUT_PATH"
fi

# Loadable modules
if [[ "$MODULES_ENABLED" -eq 1 ]]; then
    mkdir -p "$AK3_DIR/modules/system/lib/modules"
    find "$OUT_DIR/modules" -name "*.ko" -exec cp {} "$AK3_DIR/modules/system/lib/modules/" \;
fi

DO_MODULES=0
if [[ "$MODULES_ENABLED" -eq 1 ]]; then
    DO_MODULES=1
fi

# anykernel.sh
cat > "$AK3_DIR/anykernel.sh" <<'ANYKERNEL'
properties() { '
kernel.string=ROG5S-Custom (WiFi-Monitor + USB-HID + AndrAX)
do.devicecheck=1
do.modules=__DO_MODULES__
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=ZS676KS
device.name2=I005D
device.name3=ASUS_I005D
'; }

block=/dev/block/by-name/boot;
is_slot_device=0;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;
. $patch_boot;
split_boot;
flash_boot;
ANYKERNEL

sed -i "s/__DO_MODULES__/$DO_MODULES/" "$AK3_DIR/anykernel.sh"

# Create zip
(cd "$AK3_DIR" && zip -r9 "$KERNEL_ZIP" . -x "*.git*" > /dev/null)
info "Flashable zip: $KERNEL_ZIP"

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
echo ""
info "===== Build complete ====="
echo "  Kernel image : $IMAGE_OUTPUT_PATH"
if [[ "$MODULES_ENABLED" -eq 1 ]]; then
    echo "  Modules      : $OUT_DIR/modules/"
else
    echo "  Modules      : disabled in defconfig"
fi
echo "  Flashable zip: $KERNEL_ZIP"
echo ""
warn "Flash via TWRP or: adb sideload $KERNEL_ZIP"

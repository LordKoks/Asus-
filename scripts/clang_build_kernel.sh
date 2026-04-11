#!/usr/bin/env bash
# =============================================================================
# clang_build_kernel.sh — ASUS ROG Phone 5S kernel build with Clang/LLVM
#
# Использует Clang вместо GCC — официальный компилятор Google для SM8350.
# Быстрее, лучше оптимизирует, обязателен для некоторых LTO-опций.
#
# Использование:
#   bash scripts/clang_build_kernel.sh [/path/to/kernel-src] [/path/to/clang]
#
# Если Clang не указан — скачивается автоматически (proton-clang).
#
# Пример:
#   bash scripts/clang_build_kernel.sh ~/rog5s-kernel ~/clang
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Пути
# ---------------------------------------------------------------------------
KERNEL_DIR="${1:-$HOME/rog5s-kernel}"
CLANG_DIR="${2:-$HOME/clang}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FRAGMENT="$REPO_DIR/configs/rog5s_features.config"

# ---------------------------------------------------------------------------
# Параметры сборки
# ---------------------------------------------------------------------------
ARCH=arm64
DEFCONFIG=vendor/kona-perf_defconfig
OUT_DIR="$KERNEL_DIR/out"
JOBS=$(nproc)
TIMESTAMP=$(date +%Y%m%d-%H%M)
KERNEL_ZIP="$REPO_DIR/ROG5S-AndrAX-Kernel-$TIMESTAMP.zip"
MODULES_ENABLED=0
CC_WRAPPER=""

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

    error "Не найден поддерживаемый defconfig. Проверено: ${candidates[*]}"
}

# Toolchain
CROSS_COMPILE=aarch64-linux-gnu-
CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
CLANG_TRIPLE=aarch64-linux-gnu-

# Цвета
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

# ---------------------------------------------------------------------------
# 1. Проверка зависимостей
# ---------------------------------------------------------------------------
step "1. Проверка зависимостей"
MISSING=()
for cmd in make python3 zip aarch64-linux-gnu-gcc; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    warn "Устанавливаю недостающие пакеты: ${MISSING[*]}"
    sudo apt-get install -y build-essential gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabi python3 zip libssl-dev libelf-dev bc \
        flex bison ccache 2>/dev/null || true
fi
info "Зависимости OK"

# ---------------------------------------------------------------------------
# 2. Установка Clang (если не найден)
# ---------------------------------------------------------------------------
step "2. Clang toolchain"
if [[ -x "$CLANG_DIR/bin/clang" ]]; then
    info "Clang найден: $($CLANG_DIR/bin/clang --version | head -1)"
else
    info "Clang не найден, скачиваю proton-clang …"
    mkdir -p "$CLANG_DIR"
    TMP_CLANG=$(mktemp -d)
    trap 'rm -rf "$TMP_CLANG"' EXIT

    # Попытка 1: proton-clang (ARM64, для Android ядер)
    PROTON_URL="https://github.com/kdrag0n/proton-clang/archive/refs/heads/master.tar.gz"
    if wget -q --show-progress "$PROTON_URL" -O "$TMP_CLANG/clang.tar.gz" 2>/dev/null; then
        tar -xzf "$TMP_CLANG/clang.tar.gz" --strip-components=1 -C "$CLANG_DIR"
    else
        warn "proton-clang недоступен, пробую AOSP Clang r487747c …"
        AOSP_CLANG="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r487747c.tar.gz"
        wget -q --show-progress "$AOSP_CLANG" -O "$TMP_CLANG/clang.tar.gz" || \
            error "Не удалось скачать Clang. Укажите путь вручную: $0 [kernel-dir] [clang-dir]"
        tar -xzf "$TMP_CLANG/clang.tar.gz" -C "$CLANG_DIR"
    fi
    info "Clang установлен: $($CLANG_DIR/bin/clang --version | head -1)"
fi

export PATH="$CLANG_DIR/bin:$PATH"

# ---------------------------------------------------------------------------
# 3. Проверка исходников ядра
# ---------------------------------------------------------------------------
step "3. Исходники ядра"
if [[ ! -d "$KERNEL_DIR" ]]; then
    warn "Исходники ядра не найдены в $KERNEL_DIR"
    info "Клонирую ядро ASUS ROG Phone 5S (SM8350) …"
    git clone --depth=1 \
        --branch lineage-20 \
        https://github.com/LineageOS/android_kernel_asus_sm8350 \
        "$KERNEL_DIR" \
    || git clone --depth=1 \
        https://github.com/ASUS-Mobile-Open-Source/android_kernel_asus_sm8350 \
        "$KERNEL_DIR"
fi
[[ -f "$KERNEL_DIR/Makefile" ]] || error "Директория не является исходниками ядра: $KERNEL_DIR"
choose_defconfig
KERNEL_VERSION=$(make -C "$KERNEL_DIR" kernelversion 2>/dev/null || grep "^VERSION = " "$KERNEL_DIR/Makefile" | awk '{print $3}')
info "Ядро: $KERNEL_VERSION | Путь: $KERNEL_DIR"
info "Defconfig: $DEFCONFIG"

# ---------------------------------------------------------------------------
# 4. Генерация .config (defconfig + наш фрагмент — НЕИЗМЕНЁН)
# ---------------------------------------------------------------------------
step "4. Конфигурация ядра"
mkdir -p "$OUT_DIR"

info "Применяю базовый defconfig: $DEFCONFIG"
make -C "$KERNEL_DIR" \
    ARCH=$ARCH \
    CC="$CLANG_DIR/bin/clang" \
    CROSS_COMPILE=$CROSS_COMPILE \
    CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT \
    CLANG_TRIPLE=$CLANG_TRIPLE \
    O="$OUT_DIR" \
    $DEFCONFIG

info "Сливаю AndrAX фрагмент: $CONFIG_FRAGMENT"
info "(ВНИМАНИЕ: фрагмент применяется как есть, без изменений)"
(
    cd "$OUT_DIR"
    KCONFIG_CONFIG=.config "$KERNEL_DIR/scripts/kconfig/merge_config.sh" -m \
        .config \
        "$CONFIG_FRAGMENT"
)
rm -f "$KERNEL_DIR/.config"

info "Запускаю olddefconfig (заполняю новые символы значениями по умолчанию) …"
make -C "$KERNEL_DIR" \
    ARCH=$ARCH \
    CC="$CLANG_DIR/bin/clang" \
    CROSS_COMPILE=$CROSS_COMPILE \
    CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT \
    CLANG_TRIPLE=$CLANG_TRIPLE \
    O="$OUT_DIR" \
    olddefconfig < /dev/null

if grep -q '^CONFIG_MODULES=y' "$OUT_DIR/.config"; then
    MODULES_ENABLED=1
fi

# Верификация ключевых опций
info "Проверяю ключевые AndrAX опции в .config:"
for key in CONFIG_TUN CONFIG_WIREGUARD CONFIG_BPF_SYSCALL CONFIG_BPF_LSM \
           CONFIG_OVERLAY_FS CONFIG_SECCOMP_FILTER CONFIG_IKCONFIG_PROC \
           CONFIG_TASKSTATS CONFIG_FANOTIFY_ACCESS_PERMISSIONS \
           CONFIG_DEBUG_INFO_BTF CONFIG_NF_TABLES CONFIG_CGROUPS; do
    val=$(grep "^${key}=" "$OUT_DIR/.config" 2>/dev/null || echo "NOT SET")
    if [[ "$val" == "NOT SET" ]]; then
        warn "  $key = NOT SET ← может потребоваться ручная правка"
    else
        info "  $key = $val"
    fi
done

# ---------------------------------------------------------------------------
# 5. Сборка ядра
# ---------------------------------------------------------------------------
step "5. Сборка (-j$JOBS)"
START_TIME=$(date +%s)

BUILD_TARGETS=(Image)
if [[ "${ROG5S_BUILD_DTBS:-0}" == "1" ]]; then
    BUILD_TARGETS+=(dtbs)
fi
if [[ "$MODULES_ENABLED" -eq 1 ]]; then
    BUILD_TARGETS+=(modules)
else
    warn "CONFIG_MODULES отключён; пропускаю modules"
fi

if command -v ccache >/dev/null 2>&1; then
    CC_WRAPPER="ccache "
fi

make -C "$KERNEL_DIR" \
    ARCH=$ARCH \
    CC="${CC_WRAPPER}$CLANG_DIR/bin/clang" \
    KCFLAGS="-Wno-error" \
    LD="$CLANG_DIR/bin/ld.lld" \
    AR="$CLANG_DIR/bin/llvm-ar" \
    NM="$CLANG_DIR/bin/llvm-nm" \
    OBJCOPY="$CLANG_DIR/bin/llvm-objcopy" \
    OBJDUMP="$CLANG_DIR/bin/llvm-objdump" \
    STRIP="$CLANG_DIR/bin/llvm-strip" \
    CROSS_COMPILE=$CROSS_COMPILE \
    CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT \
    CLANG_TRIPLE=$CLANG_TRIPLE \
    O="$OUT_DIR" \
    -j"$JOBS" \
    "${BUILD_TARGETS[@]}"

END_TIME=$(date +%s)
BUILD_SECS=$((END_TIME - START_TIME))
info "Сборка завершена за $((BUILD_SECS/60))м $((BUILD_SECS%60))с"

# ---------------------------------------------------------------------------
# 6. Установка модулей
# ---------------------------------------------------------------------------
step "6. Модули"
if [[ "$MODULES_ENABLED" -eq 1 ]]; then
    mkdir -p "$OUT_DIR/modules_out"
    make -C "$KERNEL_DIR" \
        ARCH=$ARCH \
        CC="$CLANG_DIR/bin/clang" \
        CROSS_COMPILE=$CROSS_COMPILE \
        O="$OUT_DIR" \
        INSTALL_MOD_PATH="$OUT_DIR/modules_out" \
        modules_install
    info "Модули установлены"
else
    warn "Пропускаю modules_install (CONFIG_MODULES=n)"
fi

# ---------------------------------------------------------------------------
# 7. Упаковка AnyKernel3 ZIP
# ---------------------------------------------------------------------------
step "7. Упаковка flashable ZIP"

AK3_DIR=$(mktemp -d)
trap 'rm -rf "$AK3_DIR"' EXIT

# Клонируем AnyKernel3
git clone --depth=1 https://github.com/osm0sis/AnyKernel3 "$AK3_DIR" 2>/dev/null || {
    warn "Не удалось клонировать AnyKernel3, создаю минимальный шаблон"
    mkdir -p "$AK3_DIR/META-INF/com/google/android"
    mkdir -p "$AK3_DIR/tools"
}

# Копируем образ ядра
if [[ -f "$OUT_DIR/arch/$ARCH/boot/Image.gz-dtb" ]]; then
    cp "$OUT_DIR/arch/$ARCH/boot/Image.gz-dtb" "$AK3_DIR/Image.gz-dtb"
    info "Ядро: Image.gz-dtb"
elif [[ -f "$OUT_DIR/arch/$ARCH/boot/Image" ]]; then
    cp "$OUT_DIR/arch/$ARCH/boot/Image" "$AK3_DIR/Image"
    info "Ядро: Image"
else
    error "Образ ядра не найден в $OUT_DIR/arch/$ARCH/boot/"
fi

# Копируем DTB
mkdir -p "$AK3_DIR/dtbs"
if [[ -d "$OUT_DIR/arch/$ARCH/boot/dts" ]]; then
    find "$OUT_DIR/arch/$ARCH/boot/dts" -name "*.dtb" -exec cp {} "$AK3_DIR/dtbs/" \; 2>/dev/null || true
fi

# Копируем модули
if [[ "$MODULES_ENABLED" -eq 1 ]]; then
    mkdir -p "$AK3_DIR/modules/system/lib/modules"
    find "$OUT_DIR/modules_out" -name "*.ko" \
         -exec cp {} "$AK3_DIR/modules/system/lib/modules/" \; 2>/dev/null || true
fi
MOD_COUNT=$(find "$AK3_DIR/modules" -name "*.ko" 2>/dev/null | wc -l)
info "Модулей: $MOD_COUNT"

# anykernel.sh
cat > "$AK3_DIR/anykernel.sh" <<'ANYKERNEL'
properties() { '
kernel.string=ROG5S-AndrAX (WiFi-Monitor + USB-HID + AndrAX Full + AI Pentest Agent)
do.devicecheck=1
do.modules=0
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

# update-binary stub (если AK3 не клонировался)
mkdir -p "$AK3_DIR/META-INF/com/google/android"
if [[ ! -f "$AK3_DIR/META-INF/com/google/android/update-binary" ]]; then
cat > "$AK3_DIR/META-INF/com/google/android/update-binary" <<'UPDBINARY'
#!/sbin/sh
SKIPUNZIP=1
ash $ZIPFILE anykernel.sh install
UPDBINARY
    echo "true" > "$AK3_DIR/META-INF/com/google/android/updater-script"
fi

chmod +x "$AK3_DIR/META-INF/com/google/android/update-binary" 2>/dev/null || true

# Создаём ZIP
(cd "$AK3_DIR" && zip -r9 "$KERNEL_ZIP" . -x "*.git*" > /dev/null)

# ---------------------------------------------------------------------------
# 8. Итог
# ---------------------------------------------------------------------------
step "Итог сборки"
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   ✅  СБОРКА УСПЕШНО ЗАВЕРШЕНА               ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Устройство  : ASUS ROG Phone 5S (ZS676KS)"
echo -e "  SoC         : Snapdragon 888+ (SM8350-AC)"
echo -e "  Время       : $((BUILD_SECS/60))м $((BUILD_SECS%60))с"
echo -e "  Образ ядра  : $OUT_DIR/arch/$ARCH/boot/"
echo -e "  Модулей     : $MOD_COUNT"
echo -e "  Flashable   : ${BOLD}$KERNEL_ZIP${NC}"
echo -e "  Размер ZIP  : $(du -sh "$KERNEL_ZIP" | cut -f1)"
echo ""
echo -e "${YELLOW}Прошивка через TWRP:${NC}"
echo -e "  adb push $KERNEL_ZIP /sdcard/"
echo -e "  → TWRP → Install → выбрать ZIP → Swipe to Flash"
echo ""
echo -e "${YELLOW}Или через fastboot:${NC}"
echo -e "  adb reboot bootloader"
echo -e "  fastboot flash boot <custom_boot.img>"
echo ""
warn "Ваш configs/rog5s_features.config НЕ БЫЛ ИЗМЕНЁН"

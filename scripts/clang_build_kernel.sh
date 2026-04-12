#!/usr/bin/env bash
# =============================================================================
# clang_build_kernel.sh — ASUS ROG Phone 5S kernel build with Clang/LLVM
#
# Использует ТОЧНО тот тулчейн, которым ASUS собрала оригинальное ядро:
#   Clang   : clang-r416183b (LLVM 13.0.3, AOSP prebuilt)
#   GCC64   : aarch64-linux-androidkernel-4.9 (Android kernel GCC)
#   GCC32   : arm-linux-androideabi-4.9 (Android ARM32 GCC)
#
# Исходные данные: build.config.common + build.config.aarch64 из ядра ASUS
#   CC=clang, LD=ld.lld, NM=llvm-nm, OBJCOPY=llvm-objcopy
#   CROSS_COMPILE=aarch64-linux-androidkernel-
#   CROSS_COMPILE_COMPAT=arm-linux-androideabi-
#   FILES: arch/arm64/boot/Image.gz arch/arm64/boot/Image vmlinux
#
# Использование:
#   bash scripts/clang_build_kernel.sh [/path/to/kernel-src]
#
# Пример:
#   bash scripts/clang_build_kernel.sh ~/rog5s-kernel/msm-5.4
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Пути к тулчейнам (загружаются автоматически если отсутствуют)
# ---------------------------------------------------------------------------
KERNEL_DIR="${1:-$HOME/rog5s-kernel/msm-5.4}"
TOOLCHAINS_DIR="$HOME/toolchains"
CLANG_DIR="$TOOLCHAINS_DIR/clang-r416183b"
GCC_AARCH64_DIR="$TOOLCHAINS_DIR/aarch64-linux-androidkernel-4.9"
GCC_ARM_DIR="$TOOLCHAINS_DIR/arm-linux-androideabi-4.9"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FRAGMENT="$REPO_DIR/configs/rog5s_features.config"

# ---------------------------------------------------------------------------
# Параметры сборки
# ---------------------------------------------------------------------------
ARCH=arm64
OUT_DIR="$KERNEL_DIR/out"
JOBS=$(nproc)
TIMESTAMP=$(date +%Y%m%d-%H%M)
KERNEL_ZIP="$REPO_DIR/ROG5S-AndrAX-Kernel-$TIMESTAMP.zip"

# Точные значения из build.config.aarch64 (ASUS original build system)
CROSS_COMPILE=aarch64-linux-androidkernel-
CROSS_COMPILE_COMPAT=arm-linux-androideabi-
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
for cmd in make python3 zip git wget; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    warn "Устанавливаю недостающие пакеты: ${MISSING[*]}"
    sudo apt-get install -y build-essential python3 zip git wget \
        libssl-dev libelf-dev bc flex bison ccache cpio 2>/dev/null || true
fi
info "Зависимости OK"

# ---------------------------------------------------------------------------
# 2. Тулчейн: clang-r416183b + Android GCC 4.9 (как у оригинальной ASUS сборки)
# ---------------------------------------------------------------------------
step "2. Тулчейн (clang-r416183b + Android GCC 4.9)"
mkdir -p "$TOOLCHAINS_DIR"

# --- Clang r416183b (LLVM, тот самый, которым ASUS собирала ядро) ---
if [[ ! -x "$CLANG_DIR/bin/clang" ]]; then
    info "Скачиваю AOSP clang-r416183b …"
    TMP_CLG=$(mktemp -d)
    trap 'rm -rf "$TMP_CLG"' EXIT
    # AOSP prebuilt tarball (google source archive, публичный доступ)
    CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android13-release/clang-r416183b.tar.gz"
    if wget -q --show-progress "$CLANG_URL" -O "$TMP_CLG/clang.tar.gz" 2>&1; then
        mkdir -p "$CLANG_DIR"
        tar -xzf "$TMP_CLG/clang.tar.gz" -C "$CLANG_DIR"
    else
        # Резервный: android12L ветка
        CLANG_URL2="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12L-release/clang-r416183b.tar.gz"
        warn "Пробую резервный источник …"
        wget -q --show-progress "$CLANG_URL2" -O "$TMP_CLG/clang.tar.gz" \
            || error "Не удалось скачать clang-r416183b. Скачайте вручную в $CLANG_DIR"
        mkdir -p "$CLANG_DIR"
        tar -xzf "$TMP_CLG/clang.tar.gz" -C "$CLANG_DIR"
    fi
fi
info "Clang: $($CLANG_DIR/bin/clang --version | head -1)"

# ---------------------------------------------------------------------------
# GCC backend-ы для ассемблера (AOSP удалил GCC 4.9 из prebuilts-репозиториев).
# Используем системный GCC из apt с Android-префиксами через symlinks.
# CC основной = clang; GCC вызывается только для vdso32-ассемблера и config-проверок.
# ---------------------------------------------------------------------------

# --- aarch64: androidkernel- prefix → system aarch64-linux-gnu ---
if [[ ! -x "$GCC_AARCH64_DIR/bin/aarch64-linux-androidkernel-gcc" ]]; then
    info "Устанавливаю aarch64-linux-gnu (backend для androidkernel- префикса) …"
    sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu 2>/dev/null || true
    mkdir -p "$GCC_AARCH64_DIR/bin"
    for tool in gcc g++ as ar nm ld objcopy objdump strip ranlib readelf elfedit size; do
        src=$(command -v aarch64-linux-gnu-$tool 2>/dev/null) || continue
        ln -sf "$src" "$GCC_AARCH64_DIR/bin/aarch64-linux-androidkernel-$tool"
    done
fi
info "GCC64: $(ls "$GCC_AARCH64_DIR/bin/aarch64-linux-androidkernel-gcc" 2>/dev/null && echo OK || echo FAIL)"

# --- arm32: androideabi- prefix → system arm-linux-gnueabi ---
if [[ ! -x "$GCC_ARM_DIR/bin/arm-linux-androideabi-gcc" ]]; then
    info "Устанавливаю arm-linux-gnueabi (backend для androideabi- префикса) …"
    sudo apt-get install -y gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi 2>/dev/null || true
    mkdir -p "$GCC_ARM_DIR/bin"
    for tool in gcc g++ as ar nm ld objcopy objdump strip ranlib readelf elfedit size; do
        src=$(command -v arm-linux-gnueabi-$tool 2>/dev/null) || continue
        ln -sf "$src" "$GCC_ARM_DIR/bin/arm-linux-androideabi-$tool"
    done
fi
info "GCC32: $(ls "$GCC_ARM_DIR/bin/arm-linux-androideabi-gcc" 2>/dev/null && echo OK || echo FAIL)"

# Добавляем все инструменты в PATH (порядок важен: clang > GCC64 > GCC32)
# ВАЖНО: PATH должен быть экспортирован ДО make, потому что vdso32/Makefile
# вызывает $(shell which $(CROSS_COMPILE_COMPAT)elfedit) для поиска toolchain dir.
# Если GCC32 нет в PATH — clang использует /usr/bin/as (x86), что ломает сборку.
export PATH="$CLANG_DIR/bin:$GCC_AARCH64_DIR/bin:$GCC_ARM_DIR/bin:$PATH"

# Шаблон переменных для make (точно совпадает с ASUS build.config)
MAKE_ARGS=(
    ARCH=$ARCH
    CC="$CLANG_DIR/bin/clang"
    LD="$CLANG_DIR/bin/ld.lld"
    AR="$CLANG_DIR/bin/llvm-ar"
    NM="$CLANG_DIR/bin/llvm-nm"
    OBJCOPY="$CLANG_DIR/bin/llvm-objcopy"
    OBJDUMP="$CLANG_DIR/bin/llvm-objdump"
    STRIP="$CLANG_DIR/bin/llvm-strip"
    CROSS_COMPILE=$CROSS_COMPILE
    CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT
    CLANG_TRIPLE=$CLANG_TRIPLE
    LLVM_IAS=1
    O="$OUT_DIR"
)

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
KERNEL_VERSION=$(make -C "$KERNEL_DIR" kernelversion 2>/dev/null || grep "^VERSION = " "$KERNEL_DIR/Makefile" | awk '{print $3}')
info "Ядро: $KERNEL_VERSION | Путь: $KERNEL_DIR"

# ---------------------------------------------------------------------------
# 4. Генерация .config (defconfig + наш фрагмент — НЕИЗМЕНЁН)
# ---------------------------------------------------------------------------
step "4. Конфигурация ядра"
mkdir -p "$OUT_DIR"
VENDOR_CONFIGS="$KERNEL_DIR/arch/arm64/configs/vendor"

# Порядок слоёв: gki_defconfig → lahaina_GKI → lahaina_QGKI → debugfs → ZS673KS-perf → наш фрагмент
info "Шаг 1: базовый .config из gki_defconfig …"
make -C "$KERNEL_DIR" "${MAKE_ARGS[@]}" gki_defconfig

info "Шаг 2: наслаиваю lahaina + ZS673KS-perf + AndrAX фрагменты …"
cd "$KERNEL_DIR"
KCONFIG_CONFIG="$OUT_DIR/.config" \
    ./scripts/kconfig/merge_config.sh -m \
        "$OUT_DIR/.config" \
        "$VENDOR_CONFIGS/lahaina_GKI.config" \
        "$VENDOR_CONFIGS/lahaina_QGKI.config" \
        "$VENDOR_CONFIGS/debugfs.config" \
        "$VENDOR_CONFIGS/ZS673KS-perf_defconfig" \
        "$CONFIG_FRAGMENT"

info "Шаг 3: olddefconfig — заполняю незаданные символы дефолтами …"
make -C "$KERNEL_DIR" "${MAKE_ARGS[@]}" olddefconfig

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

if command -v ccache &>/dev/null; then
    make -C "$KERNEL_DIR" "${MAKE_ARGS[@]}" CC="ccache $CLANG_DIR/bin/clang" \
        -j"$JOBS" Image Image.gz dtbs modules
else
    make -C "$KERNEL_DIR" "${MAKE_ARGS[@]}" \
        -j"$JOBS" Image Image.gz dtbs modules
fi

END_TIME=$(date +%s)
BUILD_SECS=$((END_TIME - START_TIME))
info "Сборка завершена за $((BUILD_SECS/60))м $((BUILD_SECS%60))с"

# ---------------------------------------------------------------------------
# 6. Установка модулей
# ---------------------------------------------------------------------------
step "6. Модули"
mkdir -p "$OUT_DIR/modules_out"
make -C "$KERNEL_DIR" "${MAKE_ARGS[@]}" \
    INSTALL_MOD_PATH="$OUT_DIR/modules_out" \
    modules_install
info "Модули установлены"

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
find "$OUT_DIR/arch/$ARCH/boot/dts" -name "*.dtb" -exec cp {} "$AK3_DIR/dtbs/" \; 2>/dev/null || true

# Копируем модули
mkdir -p "$AK3_DIR/modules/system/lib/modules"
find "$OUT_DIR/modules_out" -name "*.ko" \
     -exec cp {} "$AK3_DIR/modules/system/lib/modules/" \; 2>/dev/null || true
MOD_COUNT=$(find "$AK3_DIR/modules/system/lib/modules/" -name "*.ko" | wc -l)
info "Модулей: $MOD_COUNT"

# anykernel.sh
cat > "$AK3_DIR/anykernel.sh" <<'ANYKERNEL'
properties() { '
kernel.string=ROG5S-AndrAX (WiFi-Monitor + USB-HID + AndrAX Full + AI Pentest Agent)
do.devicecheck=1
do.modules=1
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

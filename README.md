# ASUS ROG Phone 5S — Custom Kernel: Wi-Fi Monitor Mode, USB Injection, Full AndrAX & AI Pentest Agent

> **Target device:** ASUS ROG Phone 5S (ZS676KS)  
> **SoC:** Qualcomm Snapdragon 888+ (SM8350-AC)  
> **Kernel base:** Linux 5.4 (ASUS open-source release `33.0210.0210.235`)  
> **Kernel source:** [ASUS_I005_1-33.0210.0210.235-kernel-src.tar.gz](https://dlcdnets.asus.com/pub/ASUS/ZenFone/ROG%20Phone%205%20(ZS673KS)/ASUS_I005_1-33.0210.0210.235-kernel-src.tar.gz?model=ROG%20Phone%205S%20(ZS676KS))

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Obtaining and extracting the kernel source](#obtaining-and-extracting-the-kernel-source)
4. [Enabled features](#enabled-features)
   - [Wi-Fi monitor mode](#wi-fi-monitor-mode)
   - [USB HID gadget (USB injection)](#usb-hid-gadget-usb-injection)
   - [Full AndrAX support](#full-andrax-support)
5. [Kernel configuration](#kernel-configuration)
6. [Building the kernel](#building-the-kernel)
7. [Flashing the kernel](#flashing-the-kernel)
8. [Post-flash setup](#post-flash-setup)
9. [Installing AndrAX after the kernel flash](#installing-andrax-after-the-kernel-flash)
10. [AI Pentest Agent](#ai-pentest-agent)
11. [Verifying all features](#verifying-all-features)
12. [Troubleshooting](#troubleshooting)

---

## Overview

This repository documents how to build a custom Android kernel for the ASUS ROG Phone 5S that enables **every feature required by AndrAX** (the ARM64 Android penetration-testing framework) plus an optional AI-powered pentest agent.

| Feature | Purpose |
|---|---|
| **Wi-Fi monitor mode** | Passive wireless packet capture, injection (airodump-ng, aircrack-ng, wifite…) |
| **USB HID gadget injection** | USB keyboard/mouse emulation (BadUSB / Rubber Ducky style) |
| **Full AndrAX networking stack** | TUN, bridges, iptables, nftables, IP sets, eBPF, WireGuard, VPN tunnels |
| **BLE / NFC radio tools** | Bluetooth LE sniffing, NFC fuzzing |
| **Container isolation** | cgroups v2, overlayfs, user/net namespaces (proot, lxc, bubblewrap) |
| **Filesystem & forensics** | Loop devices, FUSE, fanotify, dm-crypt, NTFS, exFAT |
| **Crypto primitives** | AES-ARM64-CE, ChaCha20, SHA-3, BLAKE2, full cipher suite |
| **Process tracing** | ptrace, kprobes, uprobes, ftrace, perf (frida, gdb, strace) |
| **AI agent kernel interface** | eBPF/BTF, nfqueue, fanotify, taskstats, genetlink for AI pentest agent |

> **Note:** The ROG Phone 5 (ZS673KS) and ROG Phone 5S (ZS676KS) share the same kernel source tree. The only hardware difference relevant to the kernel is the upgraded Snapdragon 888+ CPU; all driver paths and defconfig targets are identical.

> **Firmware compatibility:** The kernel source archive is version `33.0210.0210.235`. If your device runs an older firmware (e.g. `WW_33.0210.0210.200` / Android 13, security patch April 2023), the kernel will still boot — the DTB and drivers are forward-compatible within the same major release. However, it is recommended to update to the latest firmware before flashing a custom kernel to avoid driver version mismatches.

---

## Prerequisites

### Host machine

```
Ubuntu 20.04 / 22.04 (x86_64 recommended)
Git ≥ 2.30
GNU Make ≥ 4.0
Python 3 ≥ 3.8
```

Install the required packages:

```bash
sudo apt update
sudo apt install -y \
  git curl wget \
  build-essential bc bison flex libssl-dev libelf-dev \
  gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi \
  python3 python3-pip \
  zip unzip tar gzip \
  libncurses-dev cpio
```

### Android device

- ASUS ROG Phone 5S (ZS676KS) with **unlocked bootloader**
- ADB / Fastboot installed on the host (`platform-tools`)
- TWRP or another custom recovery flashed (recommended)

---

## Obtaining and extracting the kernel source

### Automated (recommended)

```bash
bash scripts/download_kernel_src.sh          # downloads + extracts to ~/rog5s-kernel
bash scripts/download_kernel_src.sh /my/path  # or specify a custom directory
```

### Manual

```bash
# 1. Download (≈ 450 MB)
wget -O asus-rog5s-kernel-src.tar.gz \
  "https://dlcdnets.asus.com/pub/ASUS/ZenFone/ROG%20Phone%205%20(ZS673KS)/ASUS_I005_1-33.0210.0210.235-kernel-src.tar.gz?model=ROG%20Phone%205S%20(ZS676KS)"

# 2. Extract
mkdir -p ~/rog5s-kernel
tar -xzf asus-rog5s-kernel-src.tar.gz -C ~/rog5s-kernel --strip-components=1

# 3. Enter the source tree
cd ~/rog5s-kernel
```

---

## Enabled features

### Wi-Fi monitor mode

The ROG Phone 5S uses a **Qualcomm WCN6750** (or WCN3998) Wi-Fi 6E chip driven by the `mac80211`/`cfg80211` subsystem and the in-tree `wcn36xx` / out-of-tree `wlan_cnss` drivers supplied by Qualcomm.

To enable monitor mode you must:

1. Enable `cfg80211` monitor interface support in the kernel config (see [Kernel configuration](#kernel-configuration)).
2. Allow the Qualcomm proprietary Wi-Fi driver to expose a `mon0` interface. ASUS ships a vendor blob (`wlan_cnss_fw`) but the kernel side (`cfg80211`) must already export the capability.
3. After boot, create the monitor interface with `iw`:

```bash
# Requires root (su or Magisk)
ip link set wlan0 down
iw wlan0 set monitor none   # or: iw dev wlan0 interface add mon0 type monitor
ip link set wlan0 up
ip link set mon0 up

# Capture packets
tcpdump -i mon0 -w /sdcard/capture.pcap
```

> **Important:** Some Qualcomm vendor drivers ignore the `NL80211_IFTYPE_MONITOR` request even when `cfg80211` allows it. In that case you must also apply the [Nexmon](https://github.com/seemoo-lab/nexmon) patch for your specific firmware, or use a patched vendor Wi-Fi firmware blob.

---

### USB HID gadget (USB injection)

The USB HID gadget allows the phone to impersonate a USB keyboard or mouse when plugged into a PC, enabling scripts to be "typed" automatically (similar to a USB Rubber Ducky).

Kernel modules required:

```
USB_GADGET              — core USB gadget framework
USB_CONFIGFS            — configfs-based gadget composition
USB_CONFIGFS_F_HID      — HID function for configfs gadgets
USB_G_HID               — legacy monolithic HID gadget (alternative)
HID                     — generic HID layer
```

After flashing the kernel, configure the gadget from userspace:

```bash
# 1. Mount configfs (usually already mounted by Android init)
mount -t configfs none /config

GADGET=/config/usb_gadget/hid_inject

# 2. Create gadget
mkdir -p $GADGET
echo 0x1d6b > $GADGET/idVendor   # Linux Foundation
echo 0x0104 > $GADGET/idProduct  # Multifunction Composite Gadget

# 3. Create strings
mkdir -p $GADGET/strings/0x409
echo "ROG5S"   > $GADGET/strings/0x409/manufacturer
echo "HID Keyboard" > $GADGET/strings/0x409/product

# 4. Create HID function (keyboard)
mkdir -p $GADGET/functions/hid.usb0
echo 1 > $GADGET/functions/hid.usb0/protocol   # keyboard
echo 1 > $GADGET/functions/hid.usb0/subclass
echo 8 > $GADGET/functions/hid.usb0/report_length
printf '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x03\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x03\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' \
  > $GADGET/functions/hid.usb0/report_desc

# 5. Create config and link function
mkdir -p $GADGET/configs/c.1/strings/0x409
echo "HID Config" > $GADGET/configs/c.1/strings/0x409/configuration
echo 250         > $GADGET/configs/c.1/MaxPower
ln -s $GADGET/functions/hid.usb0 $GADGET/configs/c.1/

# 6. Enable gadget (replace <UDC> with the actual UDC name, e.g. a600000.dwc3)
UDC=$(ls /sys/class/udc | head -1)
echo "$UDC" > $GADGET/UDC

# 7. Write keystrokes via /dev/hidg0
#    (use the hid-gadget-test utility or write your own injection script)
```

A ready-made injection script is provided in [`scripts/usb_inject.sh`](scripts/usb_inject.sh).

---

### Full AndrAX support

The kernel config fragment [`configs/rog5s_features.config`](configs/rog5s_features.config) enables **all** kernel features required by every AndrAX tool category. The detailed mapping is in [`configs/andrax_tools.md`](configs/andrax_tools.md).

Summary of covered subsystems:

| Category | Kernel subsystems enabled |
|---|---|
| Wireless attack tools | `cfg80211`, `mac80211`, `NL80211_TESTMODE`, `CFG80211_WEXT` |
| Bluetooth LE sniffing | `BT`, `BT_HCISOCK`, `BT_LE`, `BT_HCIBTUSB` |
| NFC fuzzing | `NFC`, `NFC_NCI` |
| USB injection / gadgets | `USB_GADGET`, `USB_CONFIGFS_F_HID`, `USB_G_HID`, all configfs functions |
| VPN & tunneling | `TUN`, `WIREGUARD`, `XFRM_USER`, `INET_ESP`, `INET_AH` |
| Networking / NAT | `NF_TABLES`, `IP_NF_IPTABLES`, `NF_NAT`, `IP_SET`, `NETFILTER_NETLINK_QUEUE` |
| Container runtime | `CGROUPS` (v1+v2), `OVERLAY_FS`, `NAMESPACES`, `USER_NS`, `SECCOMP_FILTER` |
| Filesystem forensics | `BLK_DEV_LOOP`, `FUSE_FS`, `FANOTIFY`, `DM_CRYPT`, `NTFS_FS`, `EXFAT_FS` |
| Crypto / cracking | `CRYPTO_AES_ARM64_CE`, `CRYPTO_SHA3`, `CRYPTO_BLAKE2B`, `CRYPTO_CHACHA20` |
| Process tracing | `HAVE_PTRACE`, `UPROBES`, `KPROBES`, `FTRACE_SYSCALLS`, `USERFAULTFD` |
| AI agent interface | `BPF_SYSCALL`, `BPF_LSM`, `DEBUG_INFO_BTF`, `FANOTIFY_ACCESS_PERMISSIONS`, `TASKSTATS`, `GENETLINK` |

---

## Kernel configuration

Apply the defconfig fragment provided in this repository on top of the stock ASUS defconfig:

```bash
cd ~/rog5s-kernel

mkdir -p out

# Start with the stock defconfig for the ROG Phone 5(S)
make ARCH=arm64 \
     CROSS_COMPILE=aarch64-linux-gnu- \
     O=out \
     vendor/kona-perf_defconfig

# Merge the custom fragment (adds/overrides the options above)
scripts/kconfig/merge_config.sh -m \
  out/.config configs/rog5s_features.config

# Normalize any newly introduced symbols
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out olddefconfig

# Optional: review / further tune with menuconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=out menuconfig
```

The fragment file [`configs/rog5s_features.config`](configs/rog5s_features.config) is included in this repository.

---

## Building the kernel

```bash
# GCC / binutils workflow
bash scripts/build_kernel.sh ~/rog5s-kernel

# Clang / LLVM workflow
bash scripts/clang_build_kernel.sh ~/rog5s-kernel
```

If you prefer the manual path, the equivalent steps are:

```bash
cd ~/rog5s-kernel

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Build (adjust -j to match your CPU core count)
make -j$(nproc) \
     ARCH=arm64 \
     CROSS_COMPILE=aarch64-linux-gnu- \
  O=out \
     Image.gz-dtb dtbs modules

# Package modules
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     INSTALL_MOD_PATH=out/modules modules_install
```

Successful output produces:
- `out/arch/arm64/boot/Image.gz-dtb` — combined kernel + device-tree blob
- `out/modules/` — loadable kernel modules
- `rog5s-custom-kernel-*.zip` or `ROG5S-AndrAX-Kernel-*.zip` in the repository root — flashable AnyKernel3 package

---

## Flashing the kernel

### Via Fastboot (recommended)

```bash
# Boot into the bootloader
adb reboot bootloader

# Flash the new boot image
#   First, unpack the existing boot.img, replace the kernel, and repack.
#   magiskboot is bundled inside the Magisk APK — extract it:
#     1. Rename Magisk-v*.apk → Magisk.zip, unzip it
#     2. Copy lib/arm64-v8a/libmagiskboot.so → magiskboot  (chmod +x)
#   Or download a pre-built magiskboot binary from the Magisk GitHub releases:
#   https://github.com/topjohnwu/Magisk/releases

#   Grab the stock boot.img from the device
adb pull /dev/block/by-name/boot stock_boot.img

#   Unpack
magiskboot unpack stock_boot.img

#   Replace kernel
cp ~/rog5s-kernel/arch/arm64/boot/Image.gz-dtb kernel

#   Repack
magiskboot repack stock_boot.img custom_boot.img

#   Flash
fastboot flash boot custom_boot.img
fastboot reboot
```

### Via TWRP

1. Build one of the provided flashable AnyKernel3 zips with the scripts above.
2. Sideload or copy the zip to `/sdcard/`.
3. In TWRP → Install → select the zip → Swipe to flash.

---

## Post-flash setup

After first boot with the custom kernel:

```bash
# Verify kernel version
adb shell uname -r

# Load Wi-Fi monitor module (if built as module)
adb shell su -c "modprobe cfg80211; modprobe mac80211"

# Load HID gadget module (if built as module)
adb shell su -c "modprobe libcomposite; modprobe usb_f_hid"

# Verify TUN interface (for AndrAX / VPN)
adb shell su -c "ls /dev/tun"
```

---

## Installing AndrAX after the kernel flash

AndrAX is a full Linux-based penetration-testing environment that runs inside an
ARM64 chroot on Android (similar to Kali NetHunter).

### Step 1 — Install Magisk (root access)

AndrAX and almost all pentest tools require root. Flash
[Magisk](https://github.com/topjohnwu/Magisk) via TWRP alongside the kernel zip.

### Step 2 — Install NetHunter or AndrAX

```bash
# Option A: Kali NetHunter (easiest, well-maintained)
# Download the arm64 NetHunter installer from https://www.kali.org/get-kali/#kali-mobile
# Flash via TWRP, then install the NetHunter app from the included APK.

# Option B: AndrAX (dedicated pentest chroot)
# 1. Download AndrAX bootstrap from the official Telegram/GitHub channel.
# 2. Extract to /sdcard/andrax/
# 3. Run the installer script (requires Magisk root):
adb shell su -c "bash /sdcard/andrax/install.sh"
```

### Step 3 — Run the feature verification script

```bash
adb push scripts/andrax_verify.sh /data/local/tmp/
adb shell su -c "bash /data/local/tmp/andrax_verify.sh"
```

Expected output: all checks show ✔ green.

### Step 4 — Configure Wi-Fi monitor mode for wireless tools

```bash
# Inside AndrAX terminal (as root):
ip link set wlan0 down
iw dev wlan0 interface add mon0 type monitor
ip link set wlan0 up
ip link set mon0 up

# Confirm monitor mode
iw dev mon0 info | grep type    # should print: type monitor

# Start airodump-ng
airodump-ng mon0
```

### Step 5 — Enable USB injection

```bash
# Run the USB gadget setup explicitly (creates /dev/hidg0):
adb shell su -c "bash /data/local/tmp/usb_inject.sh setup"

# Or call without arguments; the script defaults to setup mode:
adb shell su -c "bash /data/local/tmp/usb_inject.sh"

# Type a payload:
adb shell su -c "bash /data/local/tmp/usb_inject.sh 'Hello from ROG5S!'"
```

### Step 6 — Quick start for common AndrAX tools

| Goal | Command inside AndrAX chroot |
|---|---|
| Wi-Fi WPA handshake capture | `airodump-ng -w /tmp/cap --output-format pcap mon0` |
| Crack captured handshake | `aircrack-ng -w /sdcard/rockyou.txt /tmp/cap*.cap` |
| LAN port scan | `nmap -sV -T4 192.168.1.0/24` |
| Web vuln scan | `nikto -h http://target` |
| SQL injection test | `sqlmap -u "http://target/page?id=1" --batch` |
| Reverse shell listener | `msfconsole -q -x "use multi/handler; set PAYLOAD linux/x64/shell_reverse_tcp; run"` |
| BLE scan | `hcitool lescan` |
| USB keyboard injection | `/data/local/tmp/usb_inject.sh "payload text"` |

---

## AI Pentest Agent

The file [`scripts/ai_pentest_agent.py`](scripts/ai_pentest_agent.py) is a Python
AI agent that combines a large language model with direct access to AndrAX tools.
It can plan, execute, and analyze multi-step penetration tests autonomously.

### Architecture

```
User goal → LLM Planner → tool calls → Executor → raw output → LLM Analyzer → report
                ↑                                                      |
                └──────────────── feedback loop ──────────────────────┘
```

The kernel's eBPF + fanotify + taskstats interfaces feed real-time telemetry
(syscalls, network events, file access) directly to the agent for context-aware
decision-making.

### Quick start

```bash
# 1. Install Python dependencies (on the phone or host with adb)
pip3 install openai rich prompt_toolkit

# 2a. Use with OpenAI (GPT-4o)
export OPENAI_API_KEY="sk-..."
python3 scripts/ai_pentest_agent.py

# 2b. Use with a local LLM via Ollama (no internet, runs on the phone!)
#     Install Ollama ARM64: https://ollama.ai/download/linux
ollama pull llama3
python3 scripts/ai_pentest_agent.py --local --model llama3

# 3. Interactive console
agent> Scan 192.168.1.0/24 and find open HTTP services

# 4. One-shot mode
python3 scripts/ai_pentest_agent.py --goal "Check if 192.168.1.1 is vulnerable to CVE-2021-44228 Log4Shell"
```

### Supported tools (auto-dispatched by the AI)

| Tool name | What it does |
|---|---|
| `nmap` | Port + service scan |
| `masscan` | Ultra-fast port scan |
| `wifi_scan` | List nearby Wi-Fi networks |
| `wifi_monitor` | Enable monitor mode |
| `airodump` | Capture Wi-Fi traffic |
| `usb_hid_setup` | Configure USB keyboard gadget |
| `usb_inject` | Type keystrokes via USB |
| `nikto` | Web vulnerability scan |
| `sqlmap` | SQL injection scan |
| `hashcat` | Password hash cracking |
| `msf_run` | Run a Metasploit resource script |
| `bpf_net_watch` | eBPF network telemetry |
| `proc_watch` | syscall trace a process (strace) |

### Extending the agent with new tools

```python
# In scripts/ai_pentest_agent.py, add:

@register_tool("my_tool")
def tool_my_tool(target: str) -> ToolResult:
    """Short description shown to the LLM."""
    return _run(["my_binary", "--target", target], timeout=60)
```

The LLM will automatically discover and use the new tool.

### Future AI improvements planned

- **Fine-tuned model** on public CTF write-ups and CVE PoCs (ARM64 quantized GGUF)
- **eBPF telemetry integration** — kernel feeds live syscall / network graphs to agent
- **Autonomous exploit chaining** — agent links recon → vuln scan → exploitation steps
- **Report generation** — Markdown / PDF pentest report auto-written by the AI

---

## Verifying all features

Run the comprehensive post-flash checker:

```bash
adb push scripts/andrax_verify.sh /data/local/tmp/
adb shell su -c "bash /data/local/tmp/andrax_verify.sh"
```

The script tests 50+ kernel features across Wi-Fi, USB, networking, eBPF,
crypto, filesystems, and the AI agent interface. It exits with code `0` on
full success and `1` if any required feature is missing.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Wi-Fi drops after `iw set monitor` | Vendor driver resets interface | Use `-p` flag: `iw dev wlan0 interface add mon0 type monitor` then bring wlan0 back up |
| `/dev/hidg0` not present | Module not loaded or CONFIG missing | Check `dmesg` for HID gadget errors; ensure `USB_CONFIGFS_F_HID=y` |
| AndrAX reports missing kernel feature | Missing `CONFIG_*` option | Re-run `merge_config.sh` and rebuild |
| Bootloop after flash | Mismatched DTB | Make sure you are using `Image.gz-dtb` (combined), not plain `Image.gz` |
| Fastboot "FAILED (remote: 'Partition doesn't exist')" | Locked bootloader | Unlock via `fastboot oem unlock` (erases data) |
| `andrax_verify.sh` — config not readable | `CONFIG_IKCONFIG_PROC` not set | Add `CONFIG_IKCONFIG=y` + `CONFIG_IKCONFIG_PROC=y` to the config fragment |
| AI agent: `openai package not found` | Python dep missing | `pip3 install openai rich prompt_toolkit` |
| AI agent: LLM timeout | Ollama not running or model not pulled | `ollama serve & ollama pull llama3` |
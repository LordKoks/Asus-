# ASUS ROG Phone 5S — Custom Kernel: Wi-Fi Monitor Mode, USB Injection & AndrAX

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
   - [AndrAX-compatible networking stack](#andrax-compatible-networking-stack)
5. [Kernel configuration](#kernel-configuration)
6. [Building the kernel](#building-the-kernel)
7. [Flashing the kernel](#flashing-the-kernel)
8. [Post-flash setup](#post-flash-setup)
9. [Troubleshooting](#troubleshooting)

---

## Overview

This repository documents how to build a custom Android kernel for the ASUS ROG Phone 5S that enables:

| Feature | Purpose |
|---|---|
| **Wi-Fi monitor mode** | Passive wireless packet capture for security auditing |
| **USB HID gadget injection** | USB keyboard/mouse emulation (BadUSB / Rubber Ducky style) |
| **AndrAX networking stack** | Full suite of kernel options required by [AndrAX](https://github.com/AndraxOS) penetration-testing framework |

> **Note:** The ROG Phone 5 (ZS673KS) and ROG Phone 5S (ZS676KS) share the same kernel source tree. The only hardware difference relevant to the kernel is the upgraded Snapdragon 888+ CPU; all driver paths and defconfig targets are identical.

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

### AndrAX-compatible networking stack

[AndrAX](https://github.com/AndraxOS) requires a rich set of kernel networking features. All options listed below must be compiled **into the kernel** (`=y`) or as **loadable modules** (`=m`).

| Subsystem | Required options |
|---|---|
| TUN/TAP (VPN, OpenVPN) | `CONFIG_TUN=y` |
| Network namespaces | `CONFIG_NET_NS=y`, `CONFIG_NAMESPACES=y` |
| Virtual Ethernet pairs | `CONFIG_VETH=y` |
| Bridges | `CONFIG_BRIDGE=y`, `CONFIG_BRIDGE_NETFILTER=y` |
| IP sets | `CONFIG_IP_SET=y` and sub-modules |
| NFTables | `CONFIG_NF_TABLES=y` |
| IPTables (legacy) | `CONFIG_IP_NF_IPTABLES=y`, `CONFIG_IP_NF_FILTER=y` |
| NAT / masquerade | `CONFIG_NF_NAT=y`, `CONFIG_IP_NF_NAT=y` |
| Packet socket | `CONFIG_PACKET=y` |
| Raw sockets | `CONFIG_INET_RAW=y` |
| Traffic control (TC) | `CONFIG_NET_SCHED=y`, `CONFIG_NET_CLS_BPF=y` |
| eBPF | `CONFIG_BPF_SYSCALL=y`, `CONFIG_BPF_JIT=y` |
| XFRM/IPsec | `CONFIG_XFRM_USER=y`, `CONFIG_INET_ESP=y` |
| Cgroup networking | `CONFIG_CGROUP_NET_PRIO=y`, `CONFIG_NET_CLS_CGROUP=y` |
| Dummy interfaces | `CONFIG_DUMMY=y` |
| IPVLAN / MACVLAN | `CONFIG_IPVLAN=y`, `CONFIG_MACVLAN=y` |

---

## Kernel configuration

Apply the defconfig fragment provided in this repository on top of the stock ASUS defconfig:

```bash
cd ~/rog5s-kernel

# Start with the stock defconfig for the ROG Phone 5(S)
make ARCH=arm64 \
     CROSS_COMPILE=aarch64-linux-gnu- \
     vendor/kona-perf_defconfig

# Merge the custom fragment (adds/overrides the options above)
KCONFIG_CONFIG=.config scripts/kconfig/merge_config.sh \
  .config configs/rog5s_features.config

# Optional: review / further tune with menuconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
```

The fragment file [`configs/rog5s_features.config`](configs/rog5s_features.config) is included in this repository.

---

## Building the kernel

```bash
cd ~/rog5s-kernel

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-

# If ASUS uses Clang (common for Qualcomm kernels):
export CC=clang
export HOSTCC=gcc

# Build (adjust -j to match your CPU core count)
make -j$(nproc) \
     ARCH=arm64 \
     CROSS_COMPILE=aarch64-linux-gnu- \
     Image.gz-dtb dtbs modules

# Package modules
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     INSTALL_MOD_PATH=out/modules modules_install
```

Successful output produces:
- `arch/arm64/boot/Image.gz-dtb` — combined kernel + device-tree blob
- `out/modules/` — loadable kernel modules

---

## Flashing the kernel

### Via Fastboot (recommended)

```bash
# Boot into the bootloader
adb reboot bootloader

# Flash the new boot image
#   First, unpack the existing boot.img, replace the kernel, and repack:
pip3 install --user magiskboot   # or use the Magisk binary directly

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

1. Copy `arch/arm64/boot/Image.gz-dtb` to a zip using AnyKernel3.
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

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Wi-Fi drops after `iw set monitor` | Vendor driver resets interface | Use `-p` flag: `iw dev wlan0 interface add mon0 type monitor` then bring wlan0 back up |
| `/dev/hidg0` not present | Module not loaded or CONFIG missing | Check `dmesg` for HID gadget errors; ensure `USB_CONFIGFS_F_HID=y` |
| AndrAX reports missing kernel feature | Missing `CONFIG_*` option | Re-run `merge_config.sh` and rebuild |
| Bootloop after flash | Mismatched DTB | Make sure you are using `Image.gz-dtb` (combined), not plain `Image.gz` |
| Fastboot "FAILED (remote: 'Partition doesn't exist')" | Locked bootloader | Unlock via `fastboot oem unlock` (erases data) |
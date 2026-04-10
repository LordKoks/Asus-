# AndrAX Tool → Kernel Feature Mapping

This document lists every tool category in AndrAX and the exact kernel
`CONFIG_*` option(s) required for it to work on the ASUS ROG Phone 5S.
All options are already included in `configs/rog5s_features.config`.

---

## 1. Wireless / 802.11 tools

| Tool | Kernel requirement |
|---|---|
| `aircrack-ng`, `airodump-ng`, `aireplay-ng` | `CONFIG_CFG80211`, `CONFIG_MAC80211`, `CONFIG_NL80211_TESTMODE` — monitor mode + injection |
| `mdk4`, `mdk3` | Same as above |
| `hostapd` (rogue AP) | `CONFIG_MAC80211`, `CONFIG_CFG80211` |
| `kismet` | `CONFIG_CFG80211_WEXT`, `CONFIG_PACKET` |
| `wavemon` | `CONFIG_CFG80211` |
| `pixiewps`, `wifite`, `fluxion` | No extra kernel deps (user-space only), but require monitor mode above |
| `hcxdumptool`, `hcxtools` | `CONFIG_CFG80211`, `CONFIG_NL80211_TESTMODE`, raw packet socket |

---

## 2. Bluetooth tools

| Tool | Kernel requirement |
|---|---|
| `btlejuice`, `gattacker` | `CONFIG_BT`, `CONFIG_BT_LE`, `CONFIG_BT_HCIBTUSB` |
| `bleah`, `blesuite` | `CONFIG_BT_HCISOCK`, `CONFIG_BT` |
| `ubertooth` utilities | `CONFIG_USB_ACM` (USB CDC ACM for Ubertooth dongle) |
| `hciconfig`, `hcitool`, `gatttool` | `CONFIG_BT_HCISOCK` |
| `bluesnarfer`, `btscanner` | `CONFIG_BT`, `CONFIG_BT_RFCOMM` |
| `crackle` | User-space only; needs BT stack above |

---

## 3. Network scanning / exploitation tools

| Tool | Kernel requirement |
|---|---|
| `nmap` | `CONFIG_PACKET`, `CONFIG_INET_RAW` (raw socket + ICMP) |
| `masscan` | `CONFIG_PACKET`, `CONFIG_INET_RAW` |
| `zmap` | `CONFIG_PACKET`, `CONFIG_INET_RAW` |
| `netcat`, `socat` | Standard TCP/UDP (always enabled) |
| `hping3` | `CONFIG_INET_RAW`, `CONFIG_PACKET` |
| `scapy` | `CONFIG_PACKET`, `CONFIG_INET_RAW`, `CONFIG_BPF_SYSCALL` |
| `metasploit` (msfconsole) | TUN (`CONFIG_TUN`), standard networking |
| `impacket` | Standard TCP/UDP + raw sockets |
| `responder` | `CONFIG_PACKET`, raw sockets |
| `crackmapexec` | Standard networking, CIFS (`CONFIG_CIFS`) |
| `evil-winrm` | Standard TCP |
| `sqlmap` | Standard TCP (HTTP) |
| `nikto`, `gobuster` | Standard TCP (HTTP) |
| `burpsuite` proxy | TUN (`CONFIG_TUN`) for transparent proxy |

---

## 4. VPN / tunneling tools

| Tool | Kernel requirement |
|---|---|
| `openvpn` | `CONFIG_TUN`, `CONFIG_INET_ESP`, `CONFIG_NF_NAT` |
| `wireguard` | `CONFIG_WIREGUARD` |
| `strongSwan` (IPsec) | `CONFIG_XFRM_USER`, `CONFIG_INET_ESP`, `CONFIG_INET_AH` |
| `proxychains` | No kernel dep (user-space SOCKS wrapper) |
| `tor` | `CONFIG_TUN` or standard TCP |
| `sshuttle` | `CONFIG_TUN` |
| `iodine` (DNS tunnel) | `CONFIG_TUN` |
| `chisel`, `ligolo` | Standard TCP / TUN |

---

## 5. USB attack tools

| Tool | Kernel requirement |
|---|---|
| USB Rubber Ducky emulation | `CONFIG_USB_CONFIGFS_F_HID`, `CONFIG_USB_G_HID` |
| P4wnP1 / BadUSB keyboard | Same as above |
| USB MITM (`USBProxy`) | `CONFIG_USB_GADGET`, `CONFIG_USB_OTG` |
| USB storage injection | `CONFIG_USB_CONFIGFS_MASS_STORAGE` |
| USB-to-Ethernet (RNDIS gadget) | `CONFIG_USB_CONFIGFS_NCM` |
| USB serial console gadget | `CONFIG_USB_CONFIGFS_ACM`, `CONFIG_USB_CONFIGFS_SERIAL` |
| `usbutils` / `lsusb` | `CONFIG_USB_DEVICEFS` (usbfs) |
| `facedancer` | `CONFIG_USB_OTG` + userspace USB library |

---

## 6. Password cracking tools

| Tool | Kernel requirement |
|---|---|
| `hashcat` (CPU mode) | Crypto modules: `CONFIG_CRYPTO_MD5`, `CONFIG_CRYPTO_SHA256`, etc. |
| `john the ripper` | Same crypto modules |
| `hydra`, `medusa`, `ncrack` | Standard TCP networking |
| `crunch` (wordlist gen) | User-space only |
| `cewl` | Standard TCP (HTTP) |

---

## 7. Exploitation frameworks / binary analysis

| Tool | Kernel requirement |
|---|---|
| `metasploit` | TUN, standard networking |
| `frida` | `CONFIG_HAVE_PTRACE`, `CONFIG_PROC_MEM`, `CONFIG_UPROBES` |
| `gdb` / `gdbserver` | `CONFIG_HAVE_PTRACE` |
| `strace` | `CONFIG_HAVE_PTRACE` |
| `ltrace` | `CONFIG_HAVE_PTRACE`, `CONFIG_UPROBES` |
| `radare2` | User-space only |
| `pwntools` | `CONFIG_HAVE_PTRACE`, `CONFIG_USERFAULTFD` |
| `objection` (mobile bypass) | `CONFIG_HAVE_PTRACE`, `CONFIG_PROC_MEM` |
| `apktool`, `jadx` | User-space only |
| `drozer` | Standard ADB / TCP |

---

## 8. Web application tools

| Tool | Kernel requirement |
|---|---|
| `burpsuite` | Standard TCP + TUN (for transparent mode) |
| `zaproxy` | Standard TCP |
| `sqlmap` | Standard TCP |
| `wfuzz`, `ffuf` | Standard TCP |
| `dirb`, `dirbuster` | Standard TCP |
| `xsser` | Standard TCP |
| `commix` | Standard TCP |

---

## 9. Container / chroot tools (AndrAX internal runtime)

| Tool | Kernel requirement |
|---|---|
| `proot` | `CONFIG_HAVE_PTRACE`, user-space ptrace |
| `chroot` (real) | Requires CAP_SYS_CHROOT (always present) |
| `lxc` / `lxd` | `CONFIG_NAMESPACES`, `CONFIG_CGROUPS`, `CONFIG_OVERLAY_FS`, `CONFIG_VETH` |
| `docker` | Same as LXC + `CONFIG_BRIDGE`, `CONFIG_NF_NAT` |
| `bubblewrap` (bwrap) | `CONFIG_USER_NS`, `CONFIG_NAMESPACES` |

---

## 10. Forensics & disk imaging tools

| Tool | Kernel requirement |
|---|---|
| `dd`, `dcfldd` | `CONFIG_BLK_DEV_LOOP` (loop device for disk images) |
| `sleuthkit` / `autopsy` | `CONFIG_BLK_DEV_LOOP`, `CONFIG_FUSE_FS` |
| `volatility` | `CONFIG_PROC_MEM`, `/proc` access |
| `binwalk` | User-space, loop device for extraction |
| `foremost`, `scalpel` | User-space, loop device |
| `ext4/f2fs image mount` | `CONFIG_OVERLAY_FS`, `CONFIG_BLK_DEV_LOOP`, `CONFIG_FUSE_FS` |
| `NTFS mount` | `CONFIG_NTFS_FS`, `CONFIG_NTFS_RW` |
| `exfat / vfat mount` | `CONFIG_EXFAT_FS`, `CONFIG_VFAT_FS` |

---

## 11. NFC / RFID tools

| Tool | Kernel requirement |
|---|---|
| `nfcpy` | `CONFIG_NFC`, `CONFIG_NFC_NCI` |
| `proxmark3` | USB: `CONFIG_USB_ACM` or `CONFIG_USB_SERIAL` |
| `libnfc` | `CONFIG_NFC`, `CONFIG_NFC_NCI` |

---

## 12. SDR / radio tools

| Tool | Kernel requirement |
|---|---|
| `rtl_sdr` (RTL2832U dongle) | `CONFIG_USB_SERIAL`, DVB drivers or custom |
| `gqrx`, `gnuradio` | User-space + RTL dongle USB driver |
| `dump1090` (ADS-B) | User-space + RTL dongle |

---

## 13. AI pentest agent kernel interface

| Function | Kernel requirement |
|---|---|
| Syscall interception via eBPF | `CONFIG_BPF_SYSCALL`, `CONFIG_KPROBE_EVENTS` |
| Network packet tapping | `CONFIG_BPF_STREAM_PARSER`, `CONFIG_SK_BPFILTER` |
| File access monitoring | `CONFIG_FANOTIFY`, `CONFIG_FANOTIFY_ACCESS_PERMISSIONS` |
| Process event stream | `CONFIG_CONNECTOR`, `CONFIG_PROC_EVENTS` |
| Netfilter packet verdict | `CONFIG_NETFILTER_NETLINK_QUEUE` |
| Custom kernel↔agent channel | `CONFIG_GENETLINK` |
| Per-process telemetry | `CONFIG_TASKSTATS`, `CONFIG_TASK_DELAY_ACCT` |
| BPF security hooks | `CONFIG_BPF_LSM` |
| Type-safe eBPF programs | `CONFIG_DEBUG_INFO_BTF` |

# My-UEFI-Bootloader

A lightweight, standalone x86_64 UEFI boot manager written entirely in NASM assembly without external C runtime or toolchain dependencies.

It implements the [Boot Loader Specification](https://uapi-group.org/specifications/specs/boot_loader_specification/) directory hierarchy (standardized by `systemd-boot`), parsing `\loader\loader.conf` and `\loader\entries\*.conf` to render an interactive text menu and chain-load target UEFI binaries.

---

## Features

- **Pure NASM x86_64 Assembly**: Implemented from scratch against the UEFI 2.x specification without libc, GNU-EFI, or EDK2 wrappers.
- **Systemd-Boot Compatible**:
  - Global configuration: `\loader\loader.conf` (`default`, `timeout`).
  - Entry configuration: `\loader\entries\*.conf` (`title`, `efi`, `options`).
- **Chain-Loading via Standard Device Paths**: Constructs UEFI File Device Paths (`MEDIA_DEVICE_PATH` / `MEDIA_FILEPATH_DP`) anchored to the partition's device handle, allowing seamless execution through `LoadImage()` and `StartImage()`.
- **Kernel / Loader Parameter Forwarding**: Forwards the entry `options` command line string to loaded child images via the `EFI_LOADED_IMAGE_PROTOCOL.LoadOptions` interface.
- **Interactive Console Menu**:
  - Arrow keys (`Up` / `Down`) with automatic wraparound.
  - Page navigation (`Page Up` / `Page Down`).
  - Automatic scrolling viewport with indicators (`^ more entries above`, `v more entries below`) when entries exceed visible rows.
  - Live countdown timer with any-key cancellation.
- **Firmware Setup Reboot**: Press `Esc` to set UEFI `OsIndications` and reboot straight into UEFI firmware settings / BIOS setup (`EfiResetCold`).
- **Resilient Error Handling**: Catches missing images, invalid device paths, and displays hex status codes without freezing, gracefully returning to the menu.

---

## Repository Structure

```
.
├── src/
│   ├── bootx64.asm        # Bootloader implementation (efi_main, menu, parser, loader)
│   └── uefi.inc           # UEFI constants, GUIDs, structure offsets, and helper macros
├── examples/
│   └── hello-os.asm       # Minimal demo UEFI OS for testing chain-loading
├── loader/
│   ├── loader.conf        # Global loader settings (default entry, timeout)
│   └── entries/
│       ├── arch.conf      # Sample Linux configuration
│       └── windows.conf   # Sample Windows Boot Manager configuration
├── scripts/
│   ├── build.sh           # Builds the bootloader and demo OS
│   ├── create-image.sh    # Prepares the ESP filesystem and creates esp.img
│   └── run-qemu.sh        # Boots the disk image in QEMU with OVMF
├── Makefile               # Automated build and testing targets
└── README.md
```

---

## Configuration Format

### 1. `\loader\loader.conf`

```ini
# Default entry title or .conf filename (case-insensitive)
default Arch Linux

# Timeout in seconds before auto-booting default (0 disables)
timeout 5
```

### 2. `\loader\entries\<name>.conf`

```ini
title Arch Linux
efi \EFI\arch\grubx64.efi
options root=UUID=12345678-1234-1234-1234-123456789abc rw quiet
```

---

## Prerequisites

Install the required tools on your Linux distribution:

### Arch Linux
```bash
sudo pacman -S nasm lld qemu-system-x86 edk2-ovmf dosfstools mtools
```

### Ubuntu / Debian
```bash
sudo apt install nasm lld qemu-system-x86 ovmf dosfstools mtools
```

### Fedora
```bash
sudo dnf install nasm lld qemu-system-x86 edk2-ovmf dosfstools mtools
```

---

## Building

To assemble and link the bootloader (`BOOTX64.EFI`) and the demo OS (`hello-os.efi`):

```bash
make
```

Or using the build script:
```bash
./scripts/build.sh
```

---

## Testing in QEMU

1. **Create the bootable FAT32 disk image (`build/esp.img`)**:
   ```bash
   make image
   ```

2. **Launch QEMU with OVMF firmware**:
   ```bash
   make run
   ```

The bootloader will start in text mode, display the menu entries, count down from 5 seconds, and chain-load the selected target.

---

## Manual Installation to a Flash Drive / ESP

1. Format your target USB drive partition as FAT32 (`mkfs.vfat -F 32 /dev/sdX1`).
2. Mount the partition:
   ```bash
   sudo mount /dev/sdX1 /mnt
   ```
3. Copy the bootloader and configuration layout:
   ```bash
   sudo mkdir -p /mnt/EFI/BOOT /mnt/loader/entries
   sudo cp build/BOOTX64.EFI /mnt/EFI/BOOT/BOOTX64.EFI
   sudo cp loader/loader.conf /mnt/loader/
   sudo cp loader/entries/*.conf /mnt/loader/entries/
   ```
4. Unmount:
   ```bash
   sudo umount /mnt
   ```

---

## License

This project is licensed under the GNU General Public License v3.0 (GPLv3).

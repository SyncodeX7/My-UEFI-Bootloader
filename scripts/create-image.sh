#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
ESP_DIR="${BUILD_DIR}/esp"
IMG="${BUILD_DIR}/esp.img"
SIZE_MB=64

"${SCRIPT_DIR}/build.sh"

echo "==> Populating EFI System Partition directory layout in ${ESP_DIR}..."
mkdir -p "${ESP_DIR}/EFI/BOOT"
mkdir -p "${ESP_DIR}/EFI/arch"
mkdir -p "${ESP_DIR}/loader/entries"

cp "${BUILD_DIR}/BOOTX64.EFI" "${ESP_DIR}/EFI/BOOT/BOOTX64.EFI"
cp "${BUILD_DIR}/hello-os.efi" "${ESP_DIR}/EFI/arch/grubx64.efi"
cp "${ROOT_DIR}/loader/loader.conf" "${ESP_DIR}/loader/"
cp "${ROOT_DIR}/loader/entries/"*.conf "${ESP_DIR}/loader/entries/"

echo "==> Creating FAT32 disk image: ${IMG} (${SIZE_MB}MB)..."
dd if=/dev/zero of="${IMG}" bs=1M count="${SIZE_MB}" status=none
mkfs.vfat -F 32 -n "ESP" "${IMG}" >/dev/null
mcopy -i "${IMG}" -s "${ESP_DIR}"/* ::/

echo "==> Successfully created ${IMG}"

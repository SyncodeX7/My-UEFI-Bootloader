#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"

echo "==> Building My-UEFI-Bootloader..."
mkdir -p "${BUILD_DIR}"

nasm -f win64 -I "${ROOT_DIR}/src/" -o "${BUILD_DIR}/bootx64.o" "${ROOT_DIR}/src/bootx64.asm"
lld-link /nologo /entry:efi_main /subsystem:efi_application /nodefaultlib /out:"${BUILD_DIR}/BOOTX64.EFI" "${BUILD_DIR}/bootx64.o"

echo "==> Building demo EFI application (hello-os.efi)..."
nasm -f win64 -I "${ROOT_DIR}/src/" -o "${BUILD_DIR}/hello-os.o" "${ROOT_DIR}/examples/hello-os.asm"
lld-link /nologo /entry:efi_main /subsystem:efi_application /nodefaultlib /out:"${BUILD_DIR}/hello-os.efi" "${BUILD_DIR}/hello-os.o"

echo "==> Build successful:"
echo "    - ${BUILD_DIR}/BOOTX64.EFI"
echo "    - ${BUILD_DIR}/hello-os.efi"

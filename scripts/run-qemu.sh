#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
IMG="${BUILD_DIR}/esp.img"

if [[ ! -f "${IMG}" ]]; then
    "${SCRIPT_DIR}/create-image.sh"
fi

# Locate OVMF code and vars firmware
OVMF_CODE=""
OVMF_VARS=""

CANDIDATE_CODES=(
    "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd"
    "/usr/share/OVMF/OVMF_CODE.fd"
    "/usr/share/ovmf/x64/OVMF_CODE.fd"
    "/usr/share/edk2/ovmf/OVMF_CODE.fd"
)

CANDIDATE_VARS=(
    "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
    "/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"
    "/usr/share/OVMF/OVMF_VARS.fd"
    "/usr/share/ovmf/x64/OVMF_VARS.fd"
    "/usr/share/edk2/ovmf/OVMF_VARS.fd"
)

for f in "${CANDIDATE_CODES[@]}"; do
    if [[ -f "$f" ]]; then
        OVMF_CODE="$f"
        break
    fi
done

for f in "${CANDIDATE_VARS[@]}"; do
    if [[ -f "$f" ]]; then
        OVMF_VARS="$f"
        break
    fi
done

if [[ -z "${OVMF_CODE}" ]]; then
    # Fallback to single OVMF.fd
    SINGLE_OVMF=(
        "/usr/share/edk2/x64/OVMF.4m.fd"
        "/usr/share/edk2-ovmf/x64/OVMF.4m.fd"
        "/usr/share/OVMF/OVMF.fd"
        "/usr/share/ovmf/OVMF.fd"
    )
    for f in "${SINGLE_OVMF[@]}"; do
        if [[ -f "$f" ]]; then
            OVMF_CODE="$f"
            break
        fi
    done
fi

if [[ -z "${OVMF_CODE}" ]]; then
    echo "Error: OVMF UEFI firmware not found on system." >&2
    exit 1
fi

ACCEL=""
if [[ -e /dev/kvm ]] && [[ -w /dev/kvm ]]; then
    ACCEL="-enable-kvm -cpu host"
fi

QEMU_ARGS=(
    -machine q35
    -m 256
    -net none
)

if [[ -n "${ACCEL}" ]]; then
    QEMU_ARGS+=(${ACCEL})
fi

if [[ -n "${OVMF_VARS}" ]]; then
    VARS_COPY="${BUILD_DIR}/OVMF_VARS.fd"
    if [[ ! -f "${VARS_COPY}" ]]; then
        cp "${OVMF_VARS}" "${VARS_COPY}"
    fi
    QEMU_ARGS+=(
        -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}"
        -drive if=pflash,format=raw,file="${VARS_COPY}"
    )
else
    QEMU_ARGS+=(-bios "${OVMF_CODE}")
fi

QEMU_ARGS+=(
    -drive if=none,id=esp,file="${IMG}",format=raw
    -device virtio-blk-pci,drive=esp
)

echo "==> Starting QEMU with ${IMG}..."
exec qemu-system-x86_64 "${QEMU_ARGS[@]}" "$@"

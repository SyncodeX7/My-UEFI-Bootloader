# ==============================================================================
# My-UEFI-Bootloader Makefile
# ==============================================================================

NASM      ?= nasm
LLD_LINK  ?= lld-link
MKFS_VFAT ?= mkfs.vfat
MCOPY     ?= mcopy
QEMU      ?= qemu-system-x86_64

BUILD_DIR ?= build
SRC_DIR   ?= src
EXP_DIR   ?= examples
CONF_DIR  ?= loader
SCRIPTS   ?= scripts

NASMFLAGS ?= -f win64 -I $(SRC_DIR)/
LDFLAGS   ?= /nologo /entry:efi_main /subsystem:efi_application /nodefaultlib

TARGET_LOADER := $(BUILD_DIR)/BOOTX64.EFI
TARGET_DEMO   := $(BUILD_DIR)/hello-os.efi
DISK_IMAGE    := $(BUILD_DIR)/esp.img

.PHONY: all clean esp image run qemu test

all: $(TARGET_LOADER) $(TARGET_DEMO)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/bootx64.o: $(SRC_DIR)/bootx64.asm $(SRC_DIR)/uefi.inc | $(BUILD_DIR)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(TARGET_LOADER): $(BUILD_DIR)/bootx64.o
	$(LLD_LINK) $(LDFLAGS) /out:$@ $<

$(BUILD_DIR)/hello-os.o: $(EXP_DIR)/hello-os.asm $(SRC_DIR)/uefi.inc | $(BUILD_DIR)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(TARGET_DEMO): $(BUILD_DIR)/hello-os.o
	$(LLD_LINK) $(LDFLAGS) /out:$@ $<

esp: all
	mkdir -p $(BUILD_DIR)/esp/EFI/BOOT
	mkdir -p $(BUILD_DIR)/esp/EFI/arch
	mkdir -p $(BUILD_DIR)/esp/loader/entries
	cp $(TARGET_LOADER) $(BUILD_DIR)/esp/EFI/BOOT/BOOTX64.EFI
	cp $(TARGET_DEMO) $(BUILD_DIR)/esp/EFI/arch/grubx64.efi
	cp $(CONF_DIR)/loader.conf $(BUILD_DIR)/esp/loader/
	cp $(CONF_DIR)/entries/*.conf $(BUILD_DIR)/esp/loader/entries/

image: esp
	@bash $(SCRIPTS)/create-image.sh

run: image
	@bash $(SCRIPTS)/run-qemu.sh

qemu: run

clean:
	rm -rf $(BUILD_DIR)

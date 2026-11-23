# Makefile for minimal UEFI bootloader

UEFI_CC = clang
LD = lld-link
CFLAGS = -target x86_64-windows -ffreestanding -fno-stack-protector -mno-red-zone -fshort-wchar -Wall -Wextra -Isrc
LDFLAGS = -subsystem:efi_application -entry:efi_main -out:build/BOOTX64.EFI

SRC = $(wildcard src/*.c)
OBJ = $(patsubst src/%.c,build/%.o,$(SRC))

all: build $(OBJ)
	$(LD) $(LDFLAGS) $(OBJ)

build:
	mkdir -p build

build/%.o: src/%.c
	$(UEFI_CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf build

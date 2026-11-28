; ============================================================================
; hello-os.asm - tiny EFI application used to test the bootloader
;
; Build:
;   nasm -f win64 -I src/ -o build/hello-os.o examples/hello-os.asm
;   lld-link /nologo /entry:efi_main /subsystem:efi_application \
;            /nodefaultlib /out:build/hello-os.efi build/hello-os.o
; ============================================================================
bits 64
default rel

%include "uefi.inc"

section .data
align 8
reloc_anchor: dq efi_main

msg_hello:   wstr "Hello from the demo OS!"
msg_body1:   wstr "This image was chain-loaded by My-UEFI-Bootloader."
msg_body2:   wstr "It is a real UEFI application, not a Linux kernel."
msg_prompt:  wstr "Press any key to return to the boot menu..."
msg_newline: dw 13, 10, 0

section .bss
con_out:     resq 1
con_in:      resq 1
bs:          resq 1
key:         resb 8

section .text
global efi_main

efi_main:
    EFI_PROLOGUE
    mov rax, [rdx + ST_BOOT_SERVICES]
    mov [rel bs], rax
    mov rax, [rdx + ST_CON_OUT]
    mov [rel con_out], rax
    mov rax, [rdx + ST_CON_IN]
    mov [rel con_in], rax

    mov ecx, ATTR_NORMAL
    EFI_CALL con_set_attr
    EFI_CALL con_clear

    lea rcx, [rel msg_hello]
    EFI_CALL puts
    lea rcx, [rel msg_newline]
    EFI_CALL puts
    lea rcx, [rel msg_body1]
    EFI_CALL puts
    lea rcx, [rel msg_newline]
    EFI_CALL puts
    lea rcx, [rel msg_body2]
    EFI_CALL puts
    lea rcx, [rel msg_newline]
    EFI_CALL puts
    lea rcx, [rel msg_newline]
    EFI_CALL puts
    lea rcx, [rel msg_prompt]
    EFI_CALL puts

.wait:
    lea rcx, [rel key]
    EFI_CALL read_key
    test eax, eax
    jnz .done
    mov rcx, 50000
    EFI_CALL stall
    jmp .wait
.done:
    xor eax, eax
    EFI_EPILOGUE

; RCX = UTF-16 string
puts:
    EFI_PROLOGUE
    mov rdx, rcx
    mov rcx, [rel con_out]
    mov rax, [rcx + CO_OUTPUT_STRING]
    EFI_CALL rax
    EFI_EPILOGUE

; ECX = attribute
con_set_attr:
    EFI_PROLOGUE
    mov rdx, rcx
    mov rcx, [rel con_out]
    mov rax, [rcx + CO_SET_ATTRIBUTE]
    EFI_CALL rax
    EFI_EPILOGUE

con_clear:
    EFI_PROLOGUE
    mov rcx, [rel con_out]
    mov rax, [rcx + CO_CLEAR_SCREEN]
    EFI_CALL rax
    EFI_EPILOGUE

; RCX = EFI_INPUT_KEY buffer.  Returns EAX=1 when a key was read.
read_key:
    EFI_PROLOGUE
    mov rdx, rcx
    mov rcx, [rel con_in]
    mov rax, [rcx + CI_READ_KEY_STROKE]
    EFI_CALL rax
    test rax, rax
    jnz .none
    mov eax, 1
    EFI_EPILOGUE
.none:
    xor eax, eax
    EFI_EPILOGUE

; RCX = microseconds (note: Stall() takes no This pointer)
stall:
    EFI_PROLOGUE
    mov rax, [rel bs]
    mov rax, [rax + BS_STALL]
    EFI_CALL rax
    EFI_EPILOGUE

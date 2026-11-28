; ============================================================================
; My-UEFI-Bootloader - a small x86_64 UEFI boot manager written in NASM
;
; Entry point: EFI_STATUS efi_main(EFI_HANDLE ImageHandle,
;                                  EFI_SYSTEM_TABLE *SystemTable)
;
; The loader reads \loader\loader.conf and \loader\entries\*.conf using the
; same layout as systemd-boot, draws a text-mode menu and chain-loads the
; selected EFI application with LoadImage()/StartImage().
; ============================================================================
bits 64
default rel

%include "uefi.inc"

; ============================================================================
; read-only data
; ============================================================================
section .data

align 8
; A single absolute pointer forces the linker to emit a .reloc section.  The
; firmware may load the image at an arbitrary address and needs relocations.
image_reloc_anchor: dq efi_main

; protocol GUIDs (little-endian on-disk representation)
loaded_image_guid:
    dd 0x5B1B31A1
    dw 0x9562
    dw 0x11D2
    db 0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

device_path_guid:
    dd 0x09576E91
    dw 0x6D3F
    dw 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

file_system_guid:
    dd 0x964E5B22
    dw 0x6459
    dw 0x11D2
    db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

global_variable_guid:
    dd 0x8BE4DF61
    dw 0x93CA
    dw 0x11D2
    db 0xAA, 0x0D, 0x00, 0xE0, 0x98, 0x03, 0x2B, 0x8C

align 8
os_indications_value: dq 1

; --- user interface strings -------------------------------------------------
str_title:              wstr "My-UEFI-Bootloader 1.0"
str_subtitle:           wstr "UEFI boot menu"
str_hints:              wstr "Up/Down: select    Enter: boot    Esc: firmware setup"
str_more_above:         wstr "  ^ more entries above"
str_more_below:         wstr "  v more entries below"
str_booting_in:         wstr "Booting in "
str_countdown_suffix:   wstr " s  (press any key to cancel)      "
str_no_entries:         wstr "No boot entries were found in \loader\entries."
str_press_key:          wstr "Press any key to continue..."
str_status:             wstr "  status "
str_boot_failed:        wstr "Boot failed."
str_boot_returned:      wstr "The selected image returned control to the bootloader."
str_fw_reboot:          wstr "Rebooting to firmware setup..."
str_init_failed:        wstr "Failed to initialise the UEFI protocols."
str_empty:              dw 0
str_newline:            dw 13, 10, 0

str_separator:
    times 78 dw '-'
    dw 0

; --- file system paths ------------------------------------------------------
path_loader_conf:       wstr "\loader\loader.conf"
path_entries_dir:       wstr "\loader\entries"
path_entries_prefix:    wstr "\loader\entries\"

; --- EFI variable name ------------------------------------------------------
var_os_indications:     wstr "OsIndications"

; ============================================================================
; uninitialised data
; ============================================================================
section .bss

alignb 16
bs:                     resq 1
con_out:                resq 1
con_in:                 resq 1
rt:                     resq 1
image_handle:           resq 1

loaded_image_ptr:       resq 1
device_handle:          resq 1
self_dp:                resq 1
fs_ptr:                 resq 1
root:                   resq 1

open_handle:            resq 1
io_size:                resq 1

cfg_file:               resq 1
cfg_len:                resq 1

dir_handle:             resq 1
dir_bytes:              resq 1

entries_count:          resq 1
selected:               resq 1
default_index:          resq 1
timeout_sec:            resq 1
timeout_active:         resq 1
timeout_ticks:          resq 1
countdown_secs:         resq 1
last_status:            resq 1

draw_i:                 resq 1
draw_idx:               resq 1
draw_row:               resq 1
first_visible:          resq 1

boot_entry_ptr:         resq 1
boot_dp:                resq 1
boot_file:              resq 1
child_handle:           resq 1
child_li:               resq 1
exit_data_size:         resq 1
exit_data:              resq 1
dp_alloc:               resq 1

key_buf:                resb 8
default_name:           resb 256

alignb 16
str_buf:                resb 1024
line_buf:               resb 512
entry_line_buf:         resb 512
num_buf:                resb 64
path_buf:               resb 1024
dir_buf:                resb DIR_BUF_SIZE
file_buf:               resb FILE_BUF_SIZE
entries:                resb MAX_ENTRIES * ENTRY_SIZE

; ============================================================================
; code
; ============================================================================
section .text
global efi_main

; ----------------------------------------------------------------------------
; EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)
; ----------------------------------------------------------------------------
efi_main:
    EFI_PROLOGUE
    mov [rel image_handle], rcx
    mov rax, [rdx + ST_BOOT_SERVICES]
    mov [rel bs], rax
    mov rax, [rdx + ST_CON_OUT]
    mov [rel con_out], rax
    mov rax, [rdx + ST_CON_IN]
    mov [rel con_in], rax
    mov rax, [rdx + ST_RUNTIME_SERVICES]
    mov [rel rt], rax

    ; clear internal state
    mov qword [rel entries_count], 0
    mov qword [rel selected], 0
    mov qword [rel default_index], 0
    mov qword [rel timeout_active], 0
    mov qword [rel timeout_sec], 5
    mov byte [rel default_name], 0

    ; disable the 5-minute watchdog
    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_SET_WATCHDOG_TIMER]

    ; 80x25 text mode, no cursor, clean screen
    xor ecx, ecx
    EFI_CALL con_set_mode
    xor ecx, ecx
    EFI_CALL con_enable_cursor
    mov ecx, ATTR_NORMAL
    EFI_CALL con_set_attr
    EFI_CALL con_clear
    ; --- locate our own loaded image, partition and root directory ---------
    mov rcx, [rel image_handle]
    lea rdx, [rel loaded_image_guid]
    lea r8,  [rel loaded_image_ptr]
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_HANDLE_PROTOCOL]
    test rax, rax
    jnz .init_failed
    mov rcx, [rel loaded_image_ptr]
    mov rax, [rcx + LI_DEVICE_HANDLE]
    mov [rel device_handle], rax

    mov rcx, [rel device_handle]
    lea rdx, [rel device_path_guid]
    lea r8,  [rel self_dp]
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_HANDLE_PROTOCOL]
    test rax, rax
    jnz .init_failed

    mov rcx, [rel device_handle]
    lea rdx, [rel file_system_guid]
    lea r8,  [rel fs_ptr]
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_HANDLE_PROTOCOL]
    test rax, rax
    jnz .init_failed

    mov rcx, [rel fs_ptr]
    lea rdx, [rel root]
    EFI_CALL qword [rcx + 0x08]          ; OpenVolume
    test rax, rax
    jnz .init_failed

    ; --- read configuration and enumerate entries --------------------------
    EFI_CALL load_config
    EFI_CALL scan_entries
    cmp qword [rel entries_count], 0
    jne .have_entries

    lea rcx, [rel str_no_entries]
    mov rdx, 14                          ; EFI_NOT_FOUND
    EFI_CALL print_error
    mov rax, 14
    EFI_EPILOGUE

.have_entries:
    EFI_CALL select_default

.menu:
    EFI_CALL menu_loop
    mov [rel selected], rax

    mov rax, [rel selected]
    imul rax, rax, ENTRY_SIZE
    lea rcx, [rel entries]
    add rcx, rax
    EFI_CALL boot_entry
    test rax, rax
    jz .image_returned

    mov rcx, rax
    EFI_CALL print_boot_error
    mov qword [rel timeout_sec], 0
    jmp .menu

.image_returned:
    mov ecx, ATTR_NORMAL
    EFI_CALL con_set_attr
    xor ecx, ecx
    mov edx, 21
    EFI_CALL con_set_cursor
    lea rcx, [rel str_boot_returned]
    EFI_CALL con_write_utf16
    lea rcx, [rel str_newline]
    EFI_CALL con_write_utf16
    lea rcx, [rel str_press_key]
    EFI_CALL con_write_utf16
    EFI_CALL wait_key
    mov qword [rel timeout_sec], 0
    jmp .menu

.init_failed:
    mov [rel last_status], rax
    lea rcx, [rel str_init_failed]
    mov rdx, rax
    EFI_CALL print_error
    mov rax, [rel last_status]
    EFI_EPILOGUE

; ============================================================================
; console helpers
; ============================================================================

; RCX = UTF-16 string
con_write_utf16:
    EFI_PROLOGUE
    mov rdx, rcx
    mov rcx, [rel con_out]
    mov rax, [rcx + CO_OUTPUT_STRING]
    EFI_CALL rax
    EFI_EPILOGUE

; RCX = ASCIIZ string
con_write_ascii:
    EFI_PROLOGUE
    lea rdx, [rel str_buf]
.loop:
    movzx eax, byte [rcx]
    test al, al
    jz .done
    mov [rdx], al
    mov byte [rdx + 1], 0
    inc rcx
    add rdx, 2
    jmp .loop
.done:
    mov word [rdx], 0
    lea rcx, [rel str_buf]
    EFI_CALL con_write_utf16
    EFI_EPILOGUE

; ECX = text mode
con_set_mode:
    EFI_PROLOGUE
    mov rdx, rcx
    mov rcx, [rel con_out]
    mov rax, [rcx + CO_SET_MODE]
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

; ECX = column, EDX = row
con_set_cursor:
    EFI_PROLOGUE
    mov r8, rdx
    mov edx, ecx
    mov rcx, [rel con_out]
    mov rax, [rcx + CO_SET_CURSOR]
    EFI_CALL rax
    EFI_EPILOGUE

; ECX = visible (0/1)
con_enable_cursor:
    EFI_PROLOGUE
    mov rdx, rcx
    mov rcx, [rel con_out]
    mov rax, [rcx + CO_ENABLE_CURSOR]
    EFI_CALL rax
    EFI_EPILOGUE

; RCX = UTF-16 string, EDX = width in columns
print_line:
    EFI_PROLOGUE
    mov rsi, rcx
    mov r8d, edx
    lea rdi, [rel line_buf]
    xor eax, eax
.copy:
    cmp rax, r8
    jae .pad
    mov cx, [rsi + rax*2]
    test cx, cx
    jz .pad
    mov [rdi + rax*2], cx
    inc rax
    jmp .copy
.pad:
    cmp rax, r8
    jae .term
    mov word [rdi + rax*2], ' '
    inc rax
    jmp .pad
.term:
    mov word [rdi + rax*2], 0
    lea rcx, [rel line_buf]
    EFI_CALL con_write_utf16
    EFI_EPILOGUE

; RCX = unsigned integer
print_uint:
    EFI_PROLOGUE
    mov rax, rcx
    lea rdi, [rel num_buf + 31]
    mov byte [rdi], 0
    mov r8, 10
.loop:
    xor edx, edx
    div r8
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test rax, rax
    jnz .loop
    mov rcx, rdi
    EFI_CALL con_write_ascii
    EFI_EPILOGUE

; RCX = 64-bit value
print_hex64:
    EFI_PROLOGUE
    lea rdi, [rel num_buf]
    mov byte [rdi], '0'
    mov byte [rdi + 1], 'x'
    add rdi, 2
    mov rax, rcx
    mov ecx, 16
.loop:
    rol rax, 4
    mov rdx, rax
    and edx, 0x0F
    cmp dl, 9
    jbe .digit
    add dl, 'a' - 10
    jmp .store
.digit:
    add dl, '0'
.store:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .loop
    mov byte [rdi], 0
    lea rcx, [rel num_buf]
    EFI_CALL con_write_ascii
    EFI_EPILOGUE

; ============================================================================
; keyboard / timer
; ============================================================================

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

; Block until a key is available.  Result is left in key_buf.
wait_key:
    EFI_PROLOGUE
.loop:
    lea rcx, [rel key_buf]
    EFI_CALL read_key
    test eax, eax
    jnz .done
    mov rcx, 50000
    EFI_CALL stall
    jmp .loop
.done:
    EFI_EPILOGUE

; ============================================================================
; error reporting
; ============================================================================

; RCX = UTF-16 message, RDX = EFI_STATUS
print_error:
    EFI_PROLOGUE
    mov [rbp-56], rcx
    mov [rbp-64], rdx
    mov ecx, ATTR_ERROR
    EFI_CALL con_set_attr
    xor ecx, ecx
    mov edx, 22
    EFI_CALL con_set_cursor
    mov rcx, [rbp-56]
    EFI_CALL con_write_utf16
    lea rcx, [rel str_status]
    EFI_CALL con_write_utf16
    mov rcx, [rbp-64]
    EFI_CALL print_hex64
    lea rcx, [rel str_newline]
    EFI_CALL con_write_utf16
    xor ecx, ecx
    mov edx, 23
    EFI_CALL con_set_cursor
    lea rcx, [rel str_press_key]
    EFI_CALL con_write_utf16
    EFI_CALL wait_key
    EFI_EPILOGUE

; RCX = EFI_STATUS from LoadImage/StartImage
print_boot_error:
    EFI_PROLOGUE
    mov [rbp-56], rcx
    mov ecx, ATTR_ERROR
    EFI_CALL con_set_attr
    xor ecx, ecx
    mov edx, 21
    EFI_CALL con_set_cursor
    lea rcx, [rel str_boot_failed]
    EFI_CALL con_write_utf16
    lea rcx, [rel str_status]
    EFI_CALL con_write_utf16
    mov rcx, [rbp-56]
    EFI_CALL print_hex64
    lea rcx, [rel str_newline]
    EFI_CALL con_write_utf16
    xor ecx, ecx
    mov edx, 22
    EFI_CALL con_set_cursor
    lea rcx, [rel str_press_key]
    EFI_CALL con_write_utf16
    EFI_CALL wait_key
    EFI_EPILOGUE

; ============================================================================
; UTF-16 string helpers
; ============================================================================

; RCX = string.  Returns length in RAX (characters, no NUL).
utf16_len:
    xor eax, eax
.loop:
    cmp word [rcx + rax*2], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; RCX = destination, RDX = source, R8 = maximum characters (excluding NUL).
; Returns number of characters copied in RAX.
utf16_copy:
    xor eax, eax
.loop:
    cmp rax, r8
    jae .truncated
    mov r9w, [rdx + rax*2]
    mov [rcx + rax*2], r9w
    test r9w, r9w
    jz .done
    inc rax
    jmp .loop
.truncated:
    mov word [rcx + rax*2], 0
    ret
.done:
    ret

; RCX = a, RDX = b.  Returns EAX=1 if equal (ASCII case-insensitive).
utf16_compare_ci:
    xor r8d, r8d
.loop:
    mov ax, [rcx + r8*2]
    mov r9w, [rdx + r8*2]
    cmp ax, 'A'
    jb .a_done
    cmp ax, 'Z'
    ja .a_done
    add ax, 32
.a_done:
    cmp r9w, 'A'
    jb .b_done
    cmp r9w, 'Z'
    ja .b_done
    add r9w, 32
.b_done:
    cmp ax, r9w
    jne .no
    test ax, ax
    jz .yes
    inc r8
    jmp .loop
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; RCX = UTF-16 file name.  Returns EAX=1 when it ends in .conf.
is_conf_name:
    xor edx, edx
.len:
    cmp word [rcx + rdx*2], 0
    je .len_done
    inc rdx
    jmp .len
.len_done:
    cmp rdx, 5
    jb .no
    sub rdx, 5
    lea rcx, [rcx + rdx*2]
    cmp word [rcx], '.'
    jne .no
    mov ax, [rcx + 2]
    or ax, 0x20
    cmp ax, 'c'
    jne .no
    mov ax, [rcx + 4]
    or ax, 0x20
    cmp ax, 'o'
    jne .no
    mov ax, [rcx + 6]
    or ax, 0x20
    cmp ax, 'n'
    jne .no
    mov ax, [rcx + 8]
    or ax, 0x20
    cmp ax, 'f'
    jne .no
    cmp word [rcx + 10], 0
    jne .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; RCX = destination UTF-16, RDX = start, R8 = end, R9 = max chars,
; R10 = flags (bit 0: path normalisation).  Returns characters written.
copy_value:
    EFI_PROLOGUE
    mov rdi, rcx
    mov rsi, rdx
    mov r11, r8
    xor eax, eax
    test r10b, 1
    jz .copy
    cmp rsi, r11
    jae .copy
    mov dl, [rsi]
    cmp dl, '/'
    je .copy
    cmp dl, '\'
    je .copy
    mov word [rdi], '\'
    add rdi, 2
    inc rax
.copy:
    cmp rsi, r11
    jae .done
    cmp rax, r9
    jae .done
    mov dl, [rsi]
    test r10b, 1
    jz .store
    cmp dl, '/'
    jne .store
    mov dl, '\'
.store:
    mov [rdi], dl
    mov byte [rdi + 1], 0
    add rdi, 2
    inc rsi
    inc rax
    jmp .copy
.done:
    mov word [rdi], 0
    EFI_EPILOGUE

; ============================================================================
; file system helpers
; ============================================================================

; RCX = UTF-16 path, EDX = open mode.  Returns file handle or 0.
open_file:
    EFI_PROLOGUE
    mov r10, rcx
    mov r9, rdx
    mov rcx, [rel root]
    lea rdx, [rel open_handle]
    mov r8, r10
    sub rsp, 48
    mov qword [rsp + 32], 0
    call qword [rcx + FP_OPEN]
    add rsp, 48
    test rax, rax
    jnz .fail
    mov rax, [rel open_handle]
    EFI_EPILOGUE
.fail:
    xor eax, eax
    EFI_EPILOGUE

; RCX = file handle
close_file:
    EFI_PROLOGUE
    mov rax, rcx
    EFI_CALL qword [rax + FP_CLOSE]
    EFI_EPILOGUE

; RCX = file handle, RDX = buffer, R8 = maximum size.
; Returns bytes read, or -1 on error.
read_file:
    EFI_PROLOGUE
    mov [rel io_size], r8
    mov rax, rcx
    mov r8, rdx
    lea rdx, [rel io_size]
    mov rcx, rax
    EFI_CALL qword [rax + FP_READ]
    test rax, rax
    jnz .fail
    mov rax, [rel io_size]
    EFI_EPILOGUE
.fail:
    mov rax, -1
    EFI_EPILOGUE

; ============================================================================
; configuration parsing
; ============================================================================

; Read \loader\loader.conf and apply "default" / "timeout".
load_config:
    EFI_PROLOGUE
    mov qword [rel timeout_sec], 5
    lea rcx, [rel path_loader_conf]
    mov edx, 1
    EFI_CALL open_file
    test rax, rax
    jz .done
    mov [rel cfg_file], rax
    mov rcx, rax
    lea rdx, [rel file_buf]
    mov r8d, FILE_BUF_SIZE
    EFI_CALL read_file
    mov [rel cfg_len], rax
    mov rcx, [rel cfg_file]
    EFI_CALL close_file
    cmp qword [rel cfg_len], -1
    je .done
    lea rcx, [rel file_buf]
    mov rdx, [rel cfg_len]
    EFI_CALL parse_loader_conf
.done:
    EFI_EPILOGUE

; RCX = buffer, RDX = length
parse_loader_conf:
    EFI_PROLOGUE
    mov [rbp-56], rcx                   ; current line
    lea rax, [rcx + rdx]
    mov [rbp-64], rax                   ; end
.line:
    mov rsi, [rbp-56]
    cmp rsi, [rbp-64]
    jae .done
    mov rdi, rsi
.find_eol:
    cmp rdi, [rbp-64]
    jae .eol
    cmp byte [rdi], 10
    je .eol
    inc rdi
    jmp .find_eol
.eol:
    mov [rbp-72], rdi                   ; raw line end
    mov r8, rdi
.trim_end:
    cmp r8, rsi
    jbe .trimmed
    mov al, [r8 - 1]
    cmp al, 13
    je .dec_end
    cmp al, ' '
    je .dec_end
    cmp al, 9
    je .dec_end
    jmp .trimmed
.dec_end:
    dec r8
    jmp .trim_end
.trimmed:
    mov [rbp-80], r8                    ; trimmed end
.skip_lead:
    cmp rsi, r8
    jae .next_line
    mov al, [rsi]
    cmp al, ' '
    je .inc_lead
    cmp al, 9
    je .inc_lead
    jmp .check
.inc_lead:
    inc rsi
    jmp .skip_lead
.check:
    cmp byte [rsi], '#'
    je .next_line
    cmp byte [rsi], ';'
    je .next_line
    mov rax, r8
    sub rax, rsi

    ; "default" keyword
    cmp rax, 7
    jb .try_timeout
    cmp byte [rsi], 'd'
    jne .try_timeout
    cmp byte [rsi+1], 'e'
    jne .try_timeout
    cmp byte [rsi+2], 'f'
    jne .try_timeout
    cmp byte [rsi+3], 'a'
    jne .try_timeout
    cmp byte [rsi+4], 'u'
    jne .try_timeout
    cmp byte [rsi+5], 'l'
    jne .try_timeout
    cmp byte [rsi+6], 't'
    jne .try_timeout
    cmp rax, 7
    je .next_line
    mov dl, [rsi+7]
    cmp dl, ' '
    je .default_ok
    cmp dl, 9
    jne .try_timeout
.default_ok:
    lea rdx, [rsi+7]
.dskip:
    cmp rdx, [rbp-80]
    jae .next_line
    mov al, [rdx]
    cmp al, ' '
    je .dinc
    cmp al, 9
    je .dinc
    jmp .dcopy
.dinc:
    inc rdx
    jmp .dskip
.dcopy:
    lea rcx, [rel default_name]
    mov r8, [rbp-80]
    mov r9d, 127
    xor r10d, r10d
    EFI_CALL copy_value
    jmp .next_line

.try_timeout:
    ; "timeout" keyword
    mov rax, [rbp-80]
    sub rax, rsi
    cmp rax, 7
    jb .next_line
    cmp byte [rsi], 't'
    jne .next_line
    cmp byte [rsi+1], 'i'
    jne .next_line
    cmp byte [rsi+2], 'm'
    jne .next_line
    cmp byte [rsi+3], 'e'
    jne .next_line
    cmp byte [rsi+4], 'o'
    jne .next_line
    cmp byte [rsi+5], 'u'
    jne .next_line
    cmp byte [rsi+6], 't'
    jne .next_line
    cmp rax, 7
    je .next_line
    mov dl, [rsi+7]
    cmp dl, ' '
    je .timeout_ok
    cmp dl, 9
    jne .next_line
.timeout_ok:
    lea rdx, [rsi+7]
.tskip:
    cmp rdx, [rbp-80]
    jae .next_line
    mov al, [rdx]
    cmp al, ' '
    je .tinc
    cmp al, 9
    je .tinc
    jmp .tparse
.tinc:
    inc rdx
    jmp .tskip
.tparse:
    xor eax, eax
.tloop:
    cmp rdx, [rbp-80]
    jae .tstore
    movzx ecx, byte [rdx]
    sub ecx, '0'
    cmp ecx, 9
    ja .tstore
    imul eax, eax, 10
    add eax, ecx
    inc rdx
    jmp .tloop
.tstore:
    cmp eax, 3600
    jbe .tsave
    mov eax, 3600
.tsave:
    mov [rel timeout_sec], rax

.next_line:
    mov rsi, [rbp-72]
    inc rsi
    mov [rbp-56], rsi
    jmp .line
.done:
    EFI_EPILOGUE

; Enumerate \loader\entries\*.conf and parse each file.
scan_entries:
    EFI_PROLOGUE
    lea rcx, [rel path_entries_dir]
    mov edx, 1
    EFI_CALL open_file
    test rax, rax
    jz .done
    mov rbx, rax
.read_loop:
    mov rcx, rbx
    lea rdx, [rel dir_buf]
    mov r8d, DIR_BUF_SIZE
    EFI_CALL read_file
    cmp rax, -1
    je .close
    test rax, rax
    jz .close
    mov [rel dir_bytes], rax
    lea r12, [rel dir_buf]
    lea r13, [r12 + rax]
.entry_loop:
    cmp r12, r13
    jae .read_loop
    mov r14, [r12 + FI_SIZE]
    cmp r14, FI_FILENAME
    jb .next_entry
    mov rax, [r12 + FI_ATTRIBUTE]
    test al, EFI_FILE_DIRECTORY
    jnz .next_entry
    lea rcx, [r12 + FI_FILENAME]
    EFI_CALL is_conf_name
    test eax, eax
    jz .next_entry
    lea rcx, [r12 + FI_FILENAME]
    EFI_CALL load_entry_file
.next_entry:
    add r12, r14
    jmp .entry_loop
.close:
    mov rcx, rbx
    EFI_CALL close_file
.done:
    EFI_EPILOGUE

; RCX = UTF-16 file name inside \loader\entries
load_entry_file:
    EFI_PROLOGUE
    mov [rbp-56], rcx
    lea rcx, [rel path_buf]
    lea rdx, [rel path_entries_prefix]
    mov r8d, 200
    EFI_CALL utf16_copy
    lea rcx, [rel path_buf]
    EFI_CALL utf16_len
    lea rcx, [rel path_buf]
    lea rcx, [rcx + rax*2]
    mov rdx, [rbp-56]
    mov r8d, 100
    EFI_CALL utf16_copy

    lea rcx, [rel path_buf]
    mov edx, 1
    EFI_CALL open_file
    test rax, rax
    jz .fail
    mov [rbp-64], rax
    mov rcx, rax
    lea rdx, [rel file_buf]
    mov r8d, FILE_BUF_SIZE
    EFI_CALL read_file
    mov [rbp-72], rax
    mov rcx, [rbp-64]
    EFI_CALL close_file
    cmp qword [rbp-72], -1
    je .fail
    lea rcx, [rel file_buf]
    mov edx, [rbp-72]
    mov r8, [rbp-56]
    EFI_CALL parse_entry
    EFI_EPILOGUE
.fail:
    xor eax, eax
    EFI_EPILOGUE

; RCX = buffer, EDX = length, R8 = UTF-16 file name.
; Parses one systemd-boot style entry; returns EAX=1 when valid.
parse_entry:
    EFI_PROLOGUE
    mov rax, [rel entries_count]
    cmp rax, MAX_ENTRIES
    jae .invalid
    mov [rbp-56], rcx                   ; p
    mov eax, edx
    lea rax, [rcx + rax]
    mov [rbp-64], rax                   ; end
    mov [rbp-80], r8                    ; file name

    mov rax, [rel entries_count]
    imul rax, rax, ENTRY_SIZE
    lea rdi, [rel entries]
    add rdi, rax
    mov [rbp-72], rdi                   ; entry pointer

    xor eax, eax
    mov rcx, ENTRY_SIZE / 8
    rep stosq

    mov rcx, [rbp-72]
    add rcx, ENTRY_NAME
    mov rdx, [rbp-80]
    mov r8d, 127
    EFI_CALL utf16_copy

.line:
    mov rsi, [rbp-56]
    cmp rsi, [rbp-64]
    jae .lines_done
    mov rdi, rsi
.find_eol:
    cmp rdi, [rbp-64]
    jae .eol
    cmp byte [rdi], 10
    je .eol
    inc rdi
    jmp .find_eol
.eol:
    mov [rbp-88], rdi
    mov r8, rdi
.trim_end:
    cmp r8, rsi
    jbe .trimmed
    mov al, [r8 - 1]
    cmp al, 13
    je .dec_end
    cmp al, ' '
    je .dec_end
    cmp al, 9
    je .dec_end
    jmp .trimmed
.dec_end:
    dec r8
    jmp .trim_end
.trimmed:
    mov [rbp-96], r8
.skip_lead:
    cmp rsi, r8
    jae .next_line
    mov al, [rsi]
    cmp al, ' '
    je .inc_lead
    cmp al, 9
    je .inc_lead
    jmp .check
.inc_lead:
    inc rsi
    jmp .skip_lead
.check:
    cmp byte [rsi], '#'
    je .next_line
    cmp byte [rsi], ';'
    je .next_line
    mov rax, r8
    sub rax, rsi

    ; --- title -------------------------------------------------------------
    cmp rax, 5
    jb .try_efi
    cmp byte [rsi], 't'
    jne .try_efi
    cmp byte [rsi+1], 'i'
    jne .try_efi
    cmp byte [rsi+2], 't'
    jne .try_efi
    cmp byte [rsi+3], 'l'
    jne .try_efi
    cmp byte [rsi+4], 'e'
    jne .try_efi
    cmp rax, 5
    je .next_line
    mov dl, [rsi+5]
    cmp dl, ' '
    je .title_ok
    cmp dl, 9
    jne .try_efi
.title_ok:
    lea rdx, [rsi+5]
.title_skip:
    cmp rdx, [rbp-96]
    jae .next_line
    mov al, [rdx]
    cmp al, ' '
    je .title_inc
    cmp al, 9
    je .title_inc
    jmp .title_copy
.title_inc:
    inc rdx
    jmp .title_skip
.title_copy:
    mov rcx, [rbp-72]
    add rcx, ENTRY_TITLE
    mov r8, [rbp-96]
    mov r9d, 127
    xor r10d, r10d
    EFI_CALL copy_value
    jmp .next_line

    ; --- efi ---------------------------------------------------------------
.try_efi:
    mov rax, [rbp-96]
    sub rax, rsi
    cmp rax, 3
    jb .try_options
    cmp byte [rsi], 'e'
    jne .try_options
    cmp byte [rsi+1], 'f'
    jne .try_options
    cmp byte [rsi+2], 'i'
    jne .try_options
    cmp rax, 3
    je .next_line
    mov dl, [rsi+3]
    cmp dl, ' '
    je .efi_ok
    cmp dl, 9
    jne .try_options
.efi_ok:
    lea rdx, [rsi+3]
.efi_skip:
    cmp rdx, [rbp-96]
    jae .next_line
    mov al, [rdx]
    cmp al, ' '
    je .efi_inc
    cmp al, 9
    je .efi_inc
    jmp .efi_copy
.efi_inc:
    inc rdx
    jmp .efi_skip
.efi_copy:
    mov rcx, [rbp-72]
    add rcx, ENTRY_EFI
    mov r8, [rbp-96]
    mov r9d, 255
    mov r10d, 1
    EFI_CALL copy_value
    jmp .next_line

    ; --- options -----------------------------------------------------------
.try_options:
    mov rax, [rbp-96]
    sub rax, rsi
    cmp rax, 7
    jb .next_line
    cmp byte [rsi], 'o'
    jne .next_line
    cmp byte [rsi+1], 'p'
    jne .next_line
    cmp byte [rsi+2], 't'
    jne .next_line
    cmp byte [rsi+3], 'i'
    jne .next_line
    cmp byte [rsi+4], 'o'
    jne .next_line
    cmp byte [rsi+5], 'n'
    jne .next_line
    cmp byte [rsi+6], 's'
    jne .next_line
    cmp rax, 7
    je .next_line
    mov dl, [rsi+7]
    cmp dl, ' '
    je .opt_ok
    cmp dl, 9
    jne .next_line
.opt_ok:
    lea rdx, [rsi+7]
.opt_skip:
    cmp rdx, [rbp-96]
    jae .next_line
    mov al, [rdx]
    cmp al, ' '
    je .opt_inc
    cmp al, 9
    je .opt_inc
    jmp .opt_copy
.opt_inc:
    inc rdx
    jmp .opt_skip
.opt_copy:
    mov rcx, [rbp-72]
    add rcx, ENTRY_OPT
    mov r8, [rbp-96]
    mov r9d, 255
    xor r10d, r10d
    EFI_CALL copy_value
    mov rdi, [rbp-72]
    mov rax, [rdi + ENTRY_OPT]
    ; store UTF-16 length in bytes (including NUL)
    lea rcx, [rdi + ENTRY_OPT]
    EFI_CALL utf16_len
    inc rax
    shl rax, 1
    mov rdi, [rbp-72]
    mov [rdi + ENTRY_OPTLEN], rax

.next_line:
    mov rsi, [rbp-88]
    inc rsi
    mov [rbp-56], rsi
    jmp .line

.lines_done:
    mov rdi, [rbp-72]
    cmp word [rdi + ENTRY_TITLE], 0
    jne .have_title
    ; derive a title from the file name, dropping a .conf suffix
    lea rcx, [rdi + ENTRY_TITLE]
    mov rdx, [rbp-80]
    mov r8d, 127
    EFI_CALL utf16_copy
    mov rdi, [rbp-72]
    add rdi, ENTRY_TITLE
    xor rcx, rcx
    mov rdx, -1
.find_dot:
    mov ax, [rdi + rcx*2]
    test ax, ax
    jz .dot_done
    cmp ax, '.'
    jne .dot_next
    mov rdx, rcx
.dot_next:
    inc rcx
    jmp .find_dot
.dot_done:
    cmp rdx, -1
    je .have_title
    lea rsi, [rdi + rdx*2]
    cmp word [rsi], '.'
    jne .have_title
    mov ax, [rsi+2]
    or ax, 0x20
    cmp ax, 'c'
    jne .have_title
    mov ax, [rsi+4]
    or ax, 0x20
    cmp ax, 'o'
    jne .have_title
    mov ax, [rsi+6]
    or ax, 0x20
    cmp ax, 'n'
    jne .have_title
    mov ax, [rsi+8]
    or ax, 0x20
    cmp ax, 'f'
    jne .have_title
    cmp word [rsi+10], 0
    jne .have_title
    mov word [rsi], 0

.have_title:
    mov rdi, [rbp-72]
    cmp word [rdi + ENTRY_EFI], 0
    je .invalid
    inc qword [rel entries_count]
    mov eax, 1
    EFI_EPILOGUE
.invalid:
    xor eax, eax
    EFI_EPILOGUE

; Pick the entry named by loader.conf "default" (title or file name).
select_default:
    EFI_PROLOGUE
    mov qword [rel selected], 0
    cmp byte [rel default_name], 0
    je .done
    xor r12, r12
.loop:
    cmp r12, [rel entries_count]
    jae .done
    mov rax, r12
    imul rax, rax, ENTRY_SIZE
    lea rsi, [rel entries]
    add rsi, rax
    lea rcx, [rel default_name]
    lea rdx, [rsi + ENTRY_TITLE]
    EFI_CALL utf16_compare_ci
    test eax, eax
    jnz .found
    lea rcx, [rel default_name]
    lea rdx, [rsi + ENTRY_NAME]
    EFI_CALL utf16_compare_ci
    test eax, eax
    jnz .found
    inc r12
    jmp .loop
.found:
    mov [rel selected], r12
.done:
    mov rax, [rel selected]
    mov [rel default_index], rax
    EFI_EPILOGUE

; ============================================================================
; menu
; ============================================================================

; Draw the countdown line from timeout_ticks.
draw_countdown:
    EFI_PROLOGUE
    mov rax, [rel timeout_ticks]
    add rax, 9
    xor edx, edx
    mov rcx, 10
    div rcx
    mov [rel countdown_secs], rax

    xor ecx, ecx
    mov edx, 19
    EFI_CALL con_set_cursor
    mov ecx, ATTR_HINT
    EFI_CALL con_set_attr
    lea rcx, [rel str_booting_in]
    EFI_CALL con_write_utf16
    mov rcx, [rel countdown_secs]
    EFI_CALL print_uint
    lea rcx, [rel str_countdown_suffix]
    EFI_CALL con_write_utf16
    EFI_EPILOGUE

; Draw the complete menu.
draw_menu:
    EFI_PROLOGUE
    mov ecx, ATTR_NORMAL
    EFI_CALL con_set_attr
    EFI_CALL con_clear

    ; title
    xor ecx, ecx
    xor edx, edx
    EFI_CALL con_set_cursor
    mov ecx, ATTR_TITLE
    EFI_CALL con_set_attr
    lea rcx, [rel str_title]
    EFI_CALL con_write_utf16

    ; separator row 1
    xor ecx, ecx
    mov edx, 1
    EFI_CALL con_set_cursor
    mov ecx, ATTR_DIM
    EFI_CALL con_set_attr
    lea rcx, [rel str_separator]
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line

    ; compute first visible entry
    mov rax, [rel selected]
    mov rdx, [rel entries_count]
    cmp rdx, VISIBLE_ENTRIES
    jbe .first_zero
    sub rax, 6
    jns .check_max
    xor eax, eax
.check_max:
    mov rcx, rdx
    sub rcx, VISIBLE_ENTRIES
    cmp rax, rcx
    jbe .store_first
    mov rax, rcx
    jmp .store_first
.first_zero:
    xor eax, eax
.store_first:
    mov [rel first_visible], rax

    ; "more above" row 2
    xor ecx, ecx
    mov edx, 2
    EFI_CALL con_set_cursor
    mov ecx, ATTR_DIM
    EFI_CALL con_set_attr
    cmp qword [rel first_visible], 0
    je .no_above
    lea rcx, [rel str_more_above]
    jmp .print_above
.no_above:
    lea rcx, [rel str_empty]
.print_above:
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line

    mov qword [rel draw_i], 0
.entry_loop:
    mov rax, [rel draw_i]
    cmp rax, VISIBLE_ENTRIES
    jae .after_entries
    mov rcx, [rel first_visible]
    add rcx, rax
    cmp rcx, [rel entries_count]
    jae .after_entries
    mov [rel draw_idx], rcx
    add rax, ENTRY_ROW_BASE
    mov [rel draw_row], rax

    imul rcx, rcx, ENTRY_SIZE
    lea rsi, [rel entries]
    add rsi, rcx

    ; build " > title" or "   title"
    lea rdi, [rel entry_line_buf]
    mov word [rdi], ' '
    mov word [rdi+2], ' '
    mov word [rdi+4], ' '
    mov rax, [rel selected]
    cmp rax, [rel draw_idx]
    jne .prefix_done
    mov word [rdi+2], '>'
.prefix_done:
    add rdi, 6
    lea rdx, [rsi + ENTRY_TITLE]
    xor ecx, ecx
.copy_title:
    cmp ecx, 72
    jae .title_done
    mov ax, [rdx + rcx*2]
    test ax, ax
    jz .title_done
    mov [rdi + rcx*2], ax
    inc ecx
    jmp .copy_title
.title_done:
    mov word [rdi + rcx*2], 0

    mov ecx, ATTR_NORMAL
    mov rax, [rel selected]
    cmp rax, [rel draw_idx]
    jne .attr_done
    mov ecx, ATTR_SELECTED
.attr_done:
    EFI_CALL con_set_attr
    xor ecx, ecx
    mov rdx, [rel draw_row]
    EFI_CALL con_set_cursor
    lea rcx, [rel entry_line_buf]
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line

    inc qword [rel draw_i]
    jmp .entry_loop

.after_entries:
    ; clear any rows not used by entries
.clear_loop:
    mov rax, [rel draw_i]
    cmp rax, VISIBLE_ENTRIES
    jae .after_clear
    add rax, ENTRY_ROW_BASE
    mov [rel draw_row], rax
    mov ecx, ATTR_NORMAL
    EFI_CALL con_set_attr
    xor ecx, ecx
    mov rdx, [rel draw_row]
    EFI_CALL con_set_cursor
    lea rcx, [rel str_empty]
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line
    inc qword [rel draw_i]
    jmp .clear_loop
.after_clear:

    ; "more below" row 15
    xor ecx, ecx
    mov edx, 15
    EFI_CALL con_set_cursor
    mov ecx, ATTR_DIM
    EFI_CALL con_set_attr
    mov rax, [rel first_visible]
    add rax, VISIBLE_ENTRIES
    cmp rax, [rel entries_count]
    jae .no_below
    lea rcx, [rel str_more_below]
    jmp .print_below
.no_below:
    lea rcx, [rel str_empty]
.print_below:
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line

    ; blank row 16
    xor ecx, ecx
    mov edx, 16
    EFI_CALL con_set_cursor
    mov ecx, ATTR_NORMAL
    EFI_CALL con_set_attr
    lea rcx, [rel str_empty]
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line

    ; separator row 17
    xor ecx, ecx
    mov edx, 17
    EFI_CALL con_set_cursor
    mov ecx, ATTR_DIM
    EFI_CALL con_set_attr
    lea rcx, [rel str_separator]
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line

    ; hints row 18
    xor ecx, ecx
    mov edx, 18
    EFI_CALL con_set_cursor
    mov ecx, ATTR_HINT
    EFI_CALL con_set_attr
    lea rcx, [rel str_hints]
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line

    ; countdown / empty row 19
    cmp qword [rel timeout_active], 0
    je .no_countdown
    EFI_CALL draw_countdown
    jmp .done
.no_countdown:
    xor ecx, ecx
    mov edx, 19
    EFI_CALL con_set_cursor
    mov ecx, ATTR_NORMAL
    EFI_CALL con_set_attr
    lea rcx, [rel str_empty]
    mov edx, SCREEN_WIDTH
    EFI_CALL print_line
.done:
    EFI_EPILOGUE

; Process the key in key_buf.  Returns EAX=1 to boot the selection.
handle_key:
    EFI_PROLOGUE
    movzx eax, word [rel key_buf]
    cmp al, 0x01                        ; up arrow
    je .up
    cmp al, 0x02                        ; down arrow
    je .down
    cmp al, 0x06                        ; page up
    je .page_up
    cmp al, 0x07                        ; page down
    je .page_down
    cmp al, 0x17                        ; escape
    je .escape
    movzx eax, word [rel key_buf + 2]
    cmp ax, 0x0D                        ; carriage return
    je .boot
    cmp ax, 0x0A                        ; line feed
    je .boot
    xor eax, eax
    EFI_EPILOGUE

.up:
    mov rax, [rel selected]
    test rax, rax
    jnz .up_dec
    mov rax, [rel entries_count]
.up_dec:
    dec rax
    mov [rel selected], rax
    xor eax, eax
    EFI_EPILOGUE

.down:
    mov rax, [rel selected]
    inc rax
    cmp rax, [rel entries_count]
    jb .down_store
    xor eax, eax
.down_store:
    mov [rel selected], rax
    xor eax, eax
    EFI_EPILOGUE

.page_up:
    mov rax, [rel selected]
    sub rax, VISIBLE_ENTRIES
    jns .page_up_store
    xor eax, eax
.page_up_store:
    mov [rel selected], rax
    xor eax, eax
    EFI_EPILOGUE

.page_down:
    mov rax, [rel selected]
    add rax, VISIBLE_ENTRIES
    cmp rax, [rel entries_count]
    jb .page_down_store
    mov rax, [rel entries_count]
    dec rax
.page_down_store:
    mov [rel selected], rax
    xor eax, eax
    EFI_EPILOGUE

.escape:
    EFI_CALL firmware_setup
    xor eax, eax
    EFI_EPILOGUE

.boot:
    mov eax, 1
    EFI_EPILOGUE

; Run the interactive menu.  Returns the selected index in RAX.
menu_loop:
    EFI_PROLOGUE
    mov qword [rel timeout_active], 0
    mov rax, [rel timeout_sec]
    test rax, rax
    jz .draw
    imul rax, rax, 10
    mov [rel timeout_ticks], rax
    mov qword [rel timeout_active], 1
.draw:
    EFI_CALL draw_menu
.loop:
    lea rcx, [rel key_buf]
    EFI_CALL read_key
    test eax, eax
    jz .no_key
    mov qword [rel timeout_active], 0
    EFI_CALL handle_key
    test eax, eax
    jnz .boot
    EFI_CALL draw_menu
    jmp .loop
.no_key:
    cmp qword [rel timeout_active], 0
    je .idle
    mov rcx, 100000
    EFI_CALL stall
    dec qword [rel timeout_ticks]
    jz .timeout
    mov rax, [rel timeout_ticks]
    xor edx, edx
    mov rcx, 10
    div rcx
    test rdx, rdx
    jnz .loop
    EFI_CALL draw_countdown
    jmp .loop
.idle:
    mov rcx, 50000
    EFI_CALL stall
    jmp .loop
.timeout:
.boot:
    mov rax, [rel selected]
    EFI_EPILOGUE

; ============================================================================
; chain-loading
; ============================================================================

; RCX = destination, RDX = source, R8 = length
copy_mem:
    EFI_PROLOGUE
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_COPY_MEM]
    EFI_EPILOGUE

; RCX = UTF-16 EFI path.  Returns a newly allocated device path or 0.
build_device_path:
    EFI_PROLOGUE
    mov [rbp-80], rcx                   ; file path
    mov rsi, [rel self_dp]
    test rsi, rsi
    jz .fail
    mov rdi, rsi
.find_end:
    movzx eax, byte [rdi]
    movzx edx, byte [rdi + 1]
    movzx ecx, word [rdi + 2]
    test ecx, ecx
    jz .fail
    cmp al, 0x7F
    jne .next
    cmp dl, 0xFF
    je .found
.next:
    add rdi, rcx
    jmp .find_end
.found:
    sub rdi, rsi
    mov [rbp-56], rdi                   ; base length without End node

    mov rcx, [rbp-80]
    EFI_CALL utf16_len
    mov [rbp-64], rax                   ; path length in characters
    inc rax
    shl rax, 1
    add rax, 4                          ; FilePath node size
    add rax, [rbp-56]
    add rax, 4                          ; End node
    mov [rbp-72], rax                   ; total allocation size

    mov rcx, 2                          ; EfiLoaderData
    mov rdx, rax
    lea r8, [rel dp_alloc]
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_ALLOCATE_POOL]
    test rax, rax
    jnz .fail

    mov rcx, [rel dp_alloc]
    mov rdx, [rel self_dp]
    mov r8, [rbp-56]
    EFI_CALL copy_mem

    mov rdi, [rel dp_alloc]
    add rdi, [rbp-56]
    mov byte [rdi], 4                   ; MEDIA_DEVICE_PATH
    mov byte [rdi + 1], 4               ; MEDIA_FILEPATH_DP
    mov rax, [rbp-64]
    inc rax
    shl rax, 1
    add rax, 4
    mov [rdi + 2], ax
    add rdi, 4
    mov rcx, rdi
    mov rdx, [rbp-80]
    mov r8, [rbp-64]
    inc r8
    EFI_CALL utf16_copy

    mov rdi, [rel dp_alloc]
    add rdi, [rbp-56]
    mov rax, [rbp-64]
    inc rax
    shl rax, 1
    add rax, 4
    add rdi, rax
    mov byte [rdi], 0x7F                ; END_DEVICE_PATH
    mov byte [rdi + 1], 0xFF
    mov word [rdi + 2], 4

    mov rax, [rel dp_alloc]
    EFI_EPILOGUE
.fail:
    xor eax, eax
    EFI_EPILOGUE

; RCX = pointer to a boot entry.  Returns the EFI_STATUS of the chain-load.
boot_entry:
    EFI_PROLOGUE
    mov [rbp-56], rcx
    mov [rel boot_entry_ptr], rcx

    ; make sure the target exists before building a device path
    lea rcx, [rcx + ENTRY_EFI]
    mov edx, 1
    EFI_CALL open_file
    test rax, rax
    jz .not_found
    mov rcx, rax
    EFI_CALL close_file

    mov rcx, [rbp-56]
    lea rcx, [rcx + ENTRY_EFI]
    EFI_CALL build_device_path
    test rax, rax
    jz .bad_path
    mov [rel boot_dp], rax

    ; LoadImage(FALSE, image_handle, dp, NULL, 0, &child_handle)
    xor ecx, ecx
    mov rdx, [rel image_handle]
    mov r8, [rel boot_dp]
    xor r9d, r9d
    sub rsp, 48
    mov qword [rsp + 32], 0
    lea rax, [rel child_handle]
    mov [rsp + 40], rax
    mov rax, [rel bs]
    call qword [rax + BS_LOAD_IMAGE]
    add rsp, 48
    mov [rbp-64], rax

    mov rcx, [rel boot_dp]
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_FREE_POOL]

    mov rax, [rbp-64]
    test rax, rax
    jnz .return_status

    ; pass "options" to the child through its LoadedImage protocol
    mov rdi, [rbp-56]
    cmp qword [rdi + ENTRY_OPTLEN], 0
    je .start

    mov rcx, [rel child_handle]
    lea rdx, [rel loaded_image_guid]
    lea r8, [rel child_li]
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_HANDLE_PROTOCOL]
    test rax, rax
    jnz .start

    mov rax, [rel child_li]
    mov rdi, [rbp-56]
    lea rdx, [rdi + ENTRY_OPT]
    mov [rax + LI_LOAD_OPTIONS], rdx
    mov rdx, [rdi + ENTRY_OPTLEN]
    mov [rax + LI_LOAD_OPTIONS_SIZE], edx

.start:
    mov qword [rel exit_data], 0
    mov rcx, [rel child_handle]
    lea rdx, [rel exit_data_size]
    lea r8, [rel exit_data]
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_START_IMAGE]
    mov [rbp-64], rax

    cmp qword [rel exit_data], 0
    je .return_status
    mov rcx, [rel exit_data]
    mov rax, [rel bs]
    EFI_CALL qword [rax + BS_FREE_POOL]

.return_status:
    mov rax, [rbp-64]
    EFI_EPILOGUE
.not_found:
    mov rax, 14                         ; EFI_NOT_FOUND
    EFI_EPILOGUE
.bad_path:
    mov rax, 2                          ; EFI_INVALID_PARAMETER
    EFI_EPILOGUE

; Ask the firmware to reboot into its setup UI (Esc key).
firmware_setup:
    EFI_PROLOGUE
    lea rcx, [rel var_os_indications]
    lea rdx, [rel global_variable_guid]
    mov r8d, 7                          ; NV | BS | RT
    mov r9d, 8
    sub rsp, 48
    lea rax, [rel os_indications_value]
    mov [rsp + 32], rax
    mov rax, [rel rt]
    call qword [rax + RT_SET_VARIABLE]
    add rsp, 48

    mov ecx, ATTR_HINT
    EFI_CALL con_set_attr
    xor ecx, ecx
    mov edx, 20
    EFI_CALL con_set_cursor
    lea rcx, [rel str_fw_reboot]
    EFI_CALL con_write_utf16
    mov rcx, 250000
    EFI_CALL stall

    xor ecx, ecx                        ; EfiResetCold = 0
    xor edx, edx                        ; ResetStatus = EFI_SUCCESS
    xor r8d, r8d                        ; DataSize = 0
    xor r9d, r9d                        ; ResetData = NULL
    mov rax, [rel rt]
    EFI_CALL qword [rax + RT_RESET_SYSTEM]
    EFI_EPILOGUE

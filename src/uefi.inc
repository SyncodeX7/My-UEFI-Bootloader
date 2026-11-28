; ============================================================================
; uefi.inc - UEFI x86_64 constants, structure offsets and helper macros
; ============================================================================
%ifndef UEFI_INC
%define UEFI_INC

; --- EFI_SYSTEM_TABLE -------------------------------------------------------
%define ST_CON_IN_HANDLE      0x28
%define ST_CON_IN             0x30
%define ST_CON_OUT_HANDLE     0x38
%define ST_CON_OUT            0x40
%define ST_STD_ERR_HANDLE     0x48
%define ST_STD_ERR            0x50
%define ST_RUNTIME_SERVICES   0x58
%define ST_BOOT_SERVICES      0x60

; --- EFI_BOOT_SERVICES ------------------------------------------------------
%define BS_ALLOCATE_POOL      0x40
%define BS_FREE_POOL          0x48
%define BS_HANDLE_PROTOCOL    0x98
%define BS_LOAD_IMAGE         0xC8
%define BS_START_IMAGE        0xD0
%define BS_EXIT               0xD8
%define BS_STALL              0xF8
%define BS_SET_WATCHDOG_TIMER 0x100
%define BS_COPY_MEM           0x160

; --- EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL ---------------------------------------
%define CO_RESET              0x00
%define CO_OUTPUT_STRING      0x08
%define CO_TEST_STRING        0x10
%define CO_QUERY_MODE         0x18
%define CO_SET_MODE           0x20
%define CO_SET_ATTRIBUTE      0x28
%define CO_CLEAR_SCREEN       0x30
%define CO_SET_CURSOR         0x38
%define CO_ENABLE_CURSOR      0x40

; --- EFI_SIMPLE_TEXT_INPUT_PROTOCOL ----------------------------------------
%define CI_RESET              0x00
%define CI_READ_KEY_STROKE    0x08
%define CI_WAIT_FOR_KEY       0x10

; --- EFI_FILE_PROTOCOL ------------------------------------------------------
%define FP_OPEN               0x08
%define FP_CLOSE              0x10
%define FP_READ               0x20
%define FP_GET_INFO           0x40

; --- EFI_LOADED_IMAGE_PROTOCOL ---------------------------------------------
%define LI_DEVICE_HANDLE      0x18
%define LI_FILE_PATH          0x20
%define LI_LOAD_OPTIONS_SIZE  0x30
%define LI_LOAD_OPTIONS       0x38

; --- EFI_RUNTIME_SERVICES ---------------------------------------------------
%define RT_SET_VARIABLE       0x58
%define RT_RESET_SYSTEM       0x68

; --- EFI_FILE_INFO ----------------------------------------------------------
%define FI_SIZE               0x00
%define FI_ATTRIBUTE          0x48
%define FI_FILENAME           0x50
%define EFI_FILE_DIRECTORY    0x10

; --- text attributes --------------------------------------------------------
%define ATTR_NORMAL           0x0F          ; white on black
%define ATTR_SELECTED         0x1F          ; white on blue
%define ATTR_TITLE            0x0B          ; cyan on black
%define ATTR_DIM              0x08          ; dark grey on black
%define ATTR_HINT             0x07          ; grey on black
%define ATTR_ERROR            0x0C          ; red on black

; --- menu geometry ----------------------------------------------------------
%define SCREEN_WIDTH          78
%define VISIBLE_ENTRIES       12
%define ENTRY_ROW_BASE        3

; --- boot entry structure ---------------------------------------------------
%define MAX_ENTRIES           16
%define ENTRY_TITLE           0             ; 256 bytes (128 UTF-16 chars)
%define ENTRY_EFI             256           ; 512 bytes (256 UTF-16 chars)
%define ENTRY_OPT             768           ; 512 bytes (256 UTF-16 chars)
%define ENTRY_NAME            1280          ; 256 bytes (128 UTF-16 chars)
%define ENTRY_OPTLEN          1536          ; 8 bytes
%define ENTRY_SIZE            1568

%define FILE_BUF_SIZE         16384
%define DIR_BUF_SIZE          8192

; --- macros -----------------------------------------------------------------
; Standard UEFI x64 function prologue.  Preserves the Microsoft x64
; non-volatile registers and keeps RSP 16-byte aligned for firmware calls.
%macro EFI_PROLOGUE 0
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    sub  rsp, 160
%endmacro

%macro EFI_EPILOGUE 0
    lea  rsp, [rbp-48]
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
%endmacro

; Call a function pointer with the 32-byte shadow space required by the
; Microsoft x64 ABI.  RSP is assumed 16-byte aligned before the macro.
%macro EFI_CALL 1
    sub  rsp, 32
    call %1
    add  rsp, 32
%endmacro

; Emit a NUL-terminated UTF-16LE string.
%macro wstr 1
    %strlen %%len %1
    %assign %%i 1
    %rep %%len
        %substr %%ch %1 %%i
        db %%ch, 0
        %assign %%i %%i+1
    %endrep
    dw 0
%endmacro

%endif ; UEFI_INC

// Minimal UEFI definitions for a freestanding bootloader
#ifndef EFI_H_
#define EFI_H_

#include <stddef.h>
#include <stdint.h>

// Define EFIAPI for Microsoft x64 calling convention
#define EFIAPI __attribute__((ms_abi))

// Basic EFI types
typedef uint64_t EFI_STATUS;
typedef void *EFI_HANDLE;
typedef uint16_t CHAR16;
typedef uint8_t  UINT8;
typedef uint16_t UINT16;
typedef uint32_t UINT32;
typedef uint64_t UINT64;
typedef UINT64   EFI_PHYSICAL_ADDRESS;
typedef UINT64   EFI_VIRTUAL_ADDRESS;

typedef unsigned long UINTN;

// Forward declarations
struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL;
struct _EFI_BOOT_SERVICES;
struct _EFI_RUNTIME_SERVICES;
struct _EFI_SYSTEM_TABLE;

// Simple Text Output Protocol (only what we need)
typedef struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL {
    EFI_STATUS (*Reset)(EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *This, UINTN ExtendedVerification);
    EFI_STATUS (*OutputString)(EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *This, const CHAR16 *String);
    // ... other members omitted for brevity
};

// Simple Text Input Protocol (placeholder)
typedef struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL EFI_SIMPLE_TEXT_INPUT_PROTOCOL;
struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL {
    // ... members omitted
};

// Boot Services (only a few we will use)
typedef struct _EFI_BOOT_SERVICES EFI_BOOT_SERVICES;
struct _EFI_BOOT_SERVICES {
    EFI_STATUS (*SetWatchdogTimer)(UINTN Timeout, UINT64 WatchdogCode, UINTN DataSize, CHAR16 *WatchdogData);
    // ... other members omitted
};

// System Table
typedef struct _EFI_SYSTEM_TABLE EFI_SYSTEM_TABLE;
struct _EFI_SYSTEM_TABLE {
    CHAR16                      *FirmwareVendor;
    UINT32                      FirmwareRevision;
    EFI_HANDLE                  ConsoleInHandle;
    EFI_SIMPLE_TEXT_INPUT_PROTOCOL *ConIn;
    EFI_HANDLE                  ConsoleOutHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *ConOut;
    EFI_HANDLE                  StandardErrorHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *StdErr;
    EFI_RUNTIME_SERVICES        *RuntimeServices;
    EFI_BOOT_SERVICES           *BootServices;
    UINTN                       NumberOfTableEntries;
    void                        *ConfigurationTable;
};

// Helper macro to convert ASCII to UTF-16 (simple for literals)
#define UTF16(str) ((CHAR16 *)L##str)

#endif // EFI_H_
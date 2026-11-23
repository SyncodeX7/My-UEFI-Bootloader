#include "efi.h"

// Entry point for UEFI application
EFI_STATUS EFIAPI efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable) {
    // Save SystemTable pointer globally if needed (omitted)
    // Print a message using Simple Text Output Protocol
    const CHAR16 *msg = UTF16("Bootloader initialized\r\n");
    SystemTable->ConOut->OutputString(SystemTable->ConOut, msg);
    // Return success
    return 0; // EFI_SUCCESS is 0
}
